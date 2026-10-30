# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "yaml"
require "invoices_tracker/ci_build"

# Reads .github/workflows/release.yml as data and pins what a review of it would look for: who can start a run and
# with what, which job holds which permission and which secret, how the inputs and the secrets reach shell code, and
# that every action is pinned. The workflow cannot start before it is on main, so these checks and actionlint are
# what vouch for it until then.
class InvoicesTrackerReleaseWorkflowTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  WORKFLOW = File.join(REPO_ROOT, ".github", "workflows", "release.yml")
  ACTIONLINT_CONFIG = File.join(REPO_ROOT, ".github", "actionlint.yaml")

  # The secrets of the environment `release`, and the only ones the workflow reads.
  SECRETS = %w[
    ASC_ISSUER_ID ASC_KEY_ID ASC_KEY_P8 DEVELOPER_ID_P12 DEVELOPER_ID_P12_PASSWORD SPARKLE_PRIVATE_KEY
  ].freeze

  # The oldest version of actions/upload-artifact that can upload a file without zipping it (`archive: false`).
  OLDEST_UPLOAD_ARTIFACT = Gem::Version.new("7.0.2")

  # A `uses:` line as the file spells it: the action, a full commit hash, and the version in a comment.
  PINNED_USES = /
    \A\s*(?:-\s+)?uses:\s+
    (?<action>[\w.-]+\/[\w.-]+)@(?<sha>[0-9a-f]{40})
    \s+\#\s+v(?<version>\d+(?:\.\d+)*)\s*\z
  /x

  # What the lane step runs: the typed values reach the lane through the environment, as quoted variables.
  LANE_COMMAND = 'bundle exec fastlane ci_dmg version:"$VERSION" build:"$BUILD" ' \
                 'deploy:"$DEPLOY" skip_tests:"$SKIP_TESTS"'

  # --- the start of a run ------------------------------------------------------------------------------------

  def test_a_run_is_started_by_hand_and_in_no_other_way
    assert_equal ["workflow_dispatch"], triggers.keys
  end

  def test_the_form_has_exactly_these_inputs
    assert_equal %w[branch build changelog deploy skip_tests version], inputs.keys.sort
    assert_equal({ "type" => "string", "required" => true, "default" => "main" }, input_facts("branch"))
    assert_equal({ "type" => "string", "required" => true }, input_facts("version"))
    assert_equal({ "type" => "string", "required" => true }, input_facts("build"))
    assert_equal({ "type" => "string", "required" => false }, input_facts("changelog"))
    assert_equal({ "type" => "boolean", "default" => false }, input_facts("skip_tests"))
    assert_equal({ "type" => "boolean", "default" => false }, input_facts("deploy"))
  end

  def test_every_input_says_what_it_is_for
    inputs.each do |name, input|
      refute_empty input["description"].to_s, "the input #{name} has no description"
    end
  end

  # The form is one line, so the description has to say how to start a new line: a backslash and n, kept as typed.
  def test_the_changelog_input_says_how_to_start_a_new_line
    assert_includes inputs.fetch("changelog").fetch("description"), '\n'
  end

  def test_runs_queue_one_behind_the_other_and_none_is_cancelled
    assert_equal({ "group" => "release", "cancel-in-progress" => false, "queue" => "max" },
                 workflow.fetch("concurrency"))
  end

  def test_the_token_reads_unless_a_job_asks_for_more
    assert_equal({ "contents" => "read" }, workflow.fetch("permissions"))
  end

  def test_the_run_name_shows_the_version_the_build_the_branch_and_whether_it_deploys
    name = workflow.fetch("run-name")
    %w[inputs.version inputs.build inputs.branch inputs.deploy].each do |expression|
      assert_includes name, expression
    end
  end

  # --- the build job -----------------------------------------------------------------------------------------

  def test_the_build_job_runs_on_the_xcode_runner_in_the_release_environment_with_xcode_27_1
    build = job("build")

    assert_equal "xcode-27", build["runs-on"]
    assert_equal "release", build["environment"]
    assert_equal({ "contents" => "read" }, build["permissions"])
    assert_equal "/Applications/Xcode_27.1.app/Contents/Developer", build.fetch("env")["DEVELOPER_DIR"]
  end

  # The lane refuses a working copy with changes, and Bundler may rewrite Gemfile.lock when it finds the platform of
  # the runner missing from it. A frozen bundle fails instead of rewriting the file.
  def test_bundler_may_not_rewrite_the_lockfile_on_the_runner
    assert_equal "true", job("build").fetch("env")["BUNDLE_FROZEN"]
  end

  def test_the_build_job_may_wait_long_for_notarization
    assert_operator job("build").fetch("timeout-minutes"), :>=, 60
  end

  # fastlane waits 3 seconds by default for xcodebuild to print the build settings, and fails after a few retries.
  def test_fastlane_waits_longer_than_a_cold_runner_needs_for_the_build_settings
    assert_operator job("build").fetch("env").fetch("FASTLANE_XCODEBUILD_SETTINGS_TIMEOUT").to_i, :>=, 30
  end

  def test_only_a_collaborator_who_started_the_workflow_from_main_gets_past_the_first_step
    first = steps_of("build").first

    assert_equal({ "GH_TOKEN" => "${{ github.token }}" }, first.fetch("env"))
    run = first.fetch("run")
    assert_includes run, "refs/heads/main"
    assert_match(%r{gh api "?repos/\$GITHUB_REPOSITORY/collaborators/\$GITHUB_ACTOR/permission"? --jq \.role_name}, run)
    assert_match(/admin\s*\|\s*maintain\s*\|\s*write/, run)
    assert_includes run, "::error::"
    assert_includes run, "exit 1"
  end

  def test_the_branch_is_checked_out_without_leaving_the_token_in_the_working_copy
    checkout = step_using("build", "actions/checkout")

    assert_equal "checkout", checkout["id"]
    assert_equal "${{ inputs.branch }}", checkout.dig("with", "ref")
    assert_equal false, checkout.dig("with", "persist-credentials")
  end

  # The Ruby comes from .ruby-version, which is what ruby/setup-ruby reads when it is not told a version.
  def test_ruby_and_the_bundle_are_set_up_from_the_checkout
    setup = step_using("build", "ruby/setup-ruby")

    assert_equal({ "bundler-cache" => true }, setup["with"])
  end

  def test_the_api_key_is_written_for_its_owner_alone_and_found_through_the_environment
    step = step_running("build", "AuthKey_")
    run = step.fetch("run")

    assert_equal %w[ASC_KEY_ID ASC_KEY_P8], step.fetch("env").keys.sort
    assert_match(/^umask 077$/, run)
    assert_includes run, %q(printf '%s\n' "$ASC_KEY_P8" > "$RUNNER_TEMP/asc/AuthKey_$ASC_KEY_ID.p8")
    assert_includes run, %q(echo "ASC_KEY_FILEPATH=$RUNNER_TEMP/asc/AuthKey_$ASC_KEY_ID.p8" >> "$GITHUB_ENV")
  end

  def test_the_lane_gets_the_inputs_and_the_secrets_it_reads_through_its_environment
    step = step_running("build", "fastlane ci_dmg")

    assert_equal LANE_COMMAND, step.fetch("run").strip
    env = step.fetch("env")
    assert_equal "${{ inputs.version }}", env["VERSION"]
    assert_equal "${{ inputs.build }}", env["BUILD"]
    assert_equal "${{ inputs.deploy }}", env["DEPLOY"]
    assert_equal "${{ inputs.skip_tests }}", env["SKIP_TESTS"]
    assert_equal "${{ inputs.changelog }}", env["RELEASE_CHANGELOG"]
    assert_equal "${{ github.token }}", env["GH_TOKEN"]
    %w[DEVELOPER_ID_P12 DEVELOPER_ID_P12_PASSWORD ASC_KEY_ID ASC_ISSUER_ID].each do |name|
      assert_equal "${{ secrets.#{name} }}", env[name]
    end
  end

  # Only a deploy's preflight looks at the Sparkle key, so a build without a deploy does not get it at all.
  def test_the_lane_gets_the_sparkle_key_only_when_deploying
    env = step_running("build", "fastlane ci_dmg").fetch("env")

    assert_equal "${{ inputs.deploy && secrets.SPARKLE_PRIVATE_KEY || '' }}", env["SPARKLE_PRIVATE_KEY"]
  end

  def test_each_secret_reaches_only_the_steps_that_need_it
    readers = [
      [step_running("build", "AuthKey_"), %w[ASC_KEY_ID ASC_KEY_P8]],
      [step_running("build", "fastlane ci_dmg"),
       %w[ASC_ISSUER_ID ASC_KEY_ID DEVELOPER_ID_P12 DEVELOPER_ID_P12_PASSWORD SPARKLE_PRIVATE_KEY]],
      [step_running("build", "fastlane sparkle_feed"), %w[SPARKLE_PRIVATE_KEY]]
    ]

    readers.each do |step, names|
      assert_equal names, secrets_in(step), "the secrets of the step #{step['name'].inspect}"
    end
    (steps_of("build") - readers.map(&:first)).each do |step|
      assert_empty secrets_in(step), "the step #{step['name'].inspect} must not read a secret"
    end
    assert_empty secrets_in(job("build").reject { |key, _| key == "steps" }),
                 "the settings of the build job itself must not read a secret"
    assert_empty secrets_in(workflow.reject { |key, _| key == "jobs" }), "no secret outside the jobs"
  end

  def test_the_workflow_reads_exactly_the_secrets_of_the_release_environment
    assert_equal SECRETS, secrets_in(workflow)
  end

  # The upload comes right after the lane, before any step of the feed, so a deploy that fails still leaves the DMG.
  def test_the_dmg_is_uploaded_as_the_file_it_is
    uploads = steps_of("build").select { |step| step["uses"].to_s.start_with?("actions/upload-artifact@") }
    dmg = uploads.select { |step| step.dig("with", "archive") == false }

    assert_equal 1, dmg.size
    assert_equal "build/InvoicesTracker-${{ inputs.version }}-${{ inputs.build }}.dmg", dmg.first.dig("with", "path")
    assert_equal "error", dmg.first.dig("with", "if-no-files-found")
    refute dmg.first.key?("if"), "the DMG is uploaded whether or not the run deploys"
  end

  def test_the_feed_is_made_and_uploaded_only_when_deploying
    feed = step_running("build", "fastlane sparkle_feed")
    upload = find_step("build") { |step| step.dig("with", "name") == "release-feed" }

    assert_equal %q(bundle exec fastlane sparkle_feed version:"$VERSION" build:"$BUILD"), feed.fetch("run").strip
    assert_equal %w[BUILD GH_TOKEN RELEASE_CHANGELOG SPARKLE_PRIVATE_KEY VERSION], feed.fetch("env").keys.sort
    assert_equal "${{ secrets.SPARKLE_PRIVATE_KEY }}", feed.fetch("env")["SPARKLE_PRIVATE_KEY"]
    assert_equal "inputs.deploy", feed["if"]
    assert_match(%r{\Aactions/upload-artifact@}, upload["uses"])
    assert_equal "build/feed/", upload.dig("with", "path")
    assert_equal "error", upload.dig("with", "if-no-files-found")
    assert_equal "inputs.deploy", upload["if"]
  end

  def test_the_key_file_and_the_keychain_are_removed_however_the_job_ended
    cleanup = find_step("build") { |step| step["if"].to_s.include?("always()") }
    run = cleanup.fetch("run")

    assert_equal "always()", cleanup["if"]
    assert_includes run, '"$RUNNER_TEMP/asc"'
    assert_includes run, InvoicesTracker::CiBuild::KEYCHAIN_NAME
    assert_includes run, "security delete-keychain"
  end

  def test_the_summary_names_the_commit_the_version_the_build_and_the_dmg
    step = step_running("build", "GITHUB_STEP_SUMMARY")

    assert_equal "${{ steps.checkout.outputs.commit }}", step.fetch("env")["COMMIT"]
    assert_equal "${{ inputs.version }}", step.fetch("env")["VERSION"]
    assert_equal "${{ inputs.build }}", step.fetch("env")["BUILD"]
    assert_includes step.fetch("run"), "InvoicesTracker-$VERSION-$BUILD.dmg"
    assert_includes step.fetch("run"), "$COMMIT"
  end

  def test_the_steps_of_the_build_job_run_in_this_order
    order = [
      ->(step) { step["run"].to_s.include?("collaborators/") },
      ->(step) { step["uses"].to_s.start_with?("actions/checkout@") },
      ->(step) { step["uses"].to_s.start_with?("ruby/setup-ruby@") },
      ->(step) { step["run"].to_s.include?("AuthKey_") },
      ->(step) { step["run"].to_s.include?("fastlane ci_dmg") },
      ->(step) { step.dig("with", "archive") == false },
      ->(step) { step["run"].to_s.include?("fastlane sparkle_feed") },
      ->(step) { step.dig("with", "name") == "release-feed" },
      ->(step) { step["if"] == "always()" },
      ->(step) { step["run"].to_s.include?("GITHUB_STEP_SUMMARY") }
    ]

    positions = order.map { |matches| steps_of("build").index(&matches) }

    refute_includes positions, nil
    assert_equal positions.sort, positions
    assert_equal steps_of("build").size, positions.size, "a step that is not in the list"
  end

  # --- the publish job ---------------------------------------------------------------------------------------

  def test_the_publish_job_runs_after_a_build_that_succeeded_and_only_when_deploying
    publish = job("publish")

    assert_equal ["build"], Array(publish["needs"])
    assert_includes publish["if"], "inputs.deploy"
    assert_includes publish["if"], "needs.build.result == 'success'"
  end

  def test_the_publish_job_writes_to_the_repository_and_holds_nothing_else
    publish = job("publish")

    assert_equal "ubuntu-latest", publish["runs-on"]
    assert_equal({ "contents" => "write" }, publish["permissions"])
    refute publish.key?("environment"), "the publish job must not reach the environment's secrets"
    refute_includes JSON.generate(publish), "secrets.", "the publish job must not read a secret"
  end

  def test_the_publish_job_runs_the_script_of_the_workflows_own_commit
    checkout = step_using("publish", "actions/checkout")
    download = step_using("publish", "actions/download-artifact")
    publish = step_running("publish", "Scripts/ci/publish-release.sh")

    assert_equal "${{ github.sha }}", checkout.dig("with", "ref")
    assert_equal false, checkout.dig("with", "persist-credentials")
    assert_equal "release-feed", download.dig("with", "name")
    assert_equal "Scripts/ci/publish-release.sh #{download.dig('with', 'path')}", publish.fetch("run").strip
    assert_equal({ "GH_TOKEN" => "${{ github.token }}" }, publish.fetch("env"))
    assert_equal %w[actions/checkout actions/download-artifact],
                 steps_of("publish").filter_map { |step| step["uses"]&.split("@")&.first }
  end

  # --- shell code and actions --------------------------------------------------------------------------------

  def test_no_input_or_secret_is_spliced_into_shell_code
    run_texts.each do |text|
      refute_match(/\$\{\{\s*(inputs\.|github\.event\.inputs\.|secrets\.)/, text)
    end
  end

  # Other contexts can carry what somebody typed too (a branch name, a commit message); none is needed in shell code.
  def test_no_expression_at_all_is_spliced_into_shell_code
    refute_empty run_texts
    run_texts.each { |text| refute_includes text, "${{" }
  end

  def test_every_action_is_pinned_to_a_full_commit_and_names_its_version_in_a_comment
    used = all_steps.filter_map { |step| step["uses"] }
    lines = workflow_lines.grep(/^\s*(?:-\s+)?uses:/)

    refute_empty used
    assert_equal used.size, lines.size
    used.each { |action| assert_match(%r{\A[\w.-]+/[\w.-]+@[0-9a-f]{40}\z}, action) }
    lines.each { |line| assert_match(PINNED_USES, line) }
  end

  def test_upload_artifact_is_new_enough_to_upload_a_file_without_zipping_it
    versions = workflow_lines.filter_map do |line|
      match = PINNED_USES.match(line)
      match && match[:action] == "actions/upload-artifact" ? Gem::Version.new(match[:version]) : nil
    end

    refute_empty versions
    versions.each { |version| assert_operator version, :>=, OLDEST_UPLOAD_ARTIFACT }
  end

  # --- actionlint --------------------------------------------------------------------------------------------

  # actionlint 1.7.12 knows neither the runner label nor the `queue` key that GitHub added to `concurrency` in May
  # 2026. Each entry is dropped once actionlint knows it.
  def test_actionlint_is_told_about_the_xcode_runner_and_the_queue_key
    config = YAML.safe_load(File.read(ACTIONLINT_CONFIG, encoding: "UTF-8"), aliases: false)

    assert_equal ["xcode-27"], config.dig("self-hosted-runner", "labels")
    assert_equal ['unexpected key "queue" for "concurrency" section'],
                 config.dig("paths", ".github/workflows/release.yml", "ignore")
  end

  def test_actionlint_has_nothing_to_report
    output, status = Open3.capture2e("actionlint", chdir: REPO_ROOT)

    assert status.success?, "actionlint reported:\n#{output}"
  rescue Errno::ENOENT
    skip "actionlint is not installed (brew install actionlint)"
  end

  private

  # The workflow as Psych reads it. Psych reads the key `on` as the boolean true. The files are read as UTF-8
  # whatever the locale of the process is.
  def workflow
    @workflow ||= YAML.safe_load(File.read(WORKFLOW, encoding: "UTF-8"), aliases: false)
  end

  # The lines of the workflow file as they are written, comments included.
  def workflow_lines
    File.readlines(WORKFLOW, encoding: "UTF-8")
  end

  def triggers
    workflow.fetch(true)
  end

  def inputs
    triggers.fetch("workflow_dispatch").fetch("inputs")
  end

  def input_facts(name)
    inputs.fetch(name).slice("type", "required", "default")
  end

  def job(name)
    workflow.fetch("jobs").fetch(name)
  end

  def steps_of(job_name)
    job(job_name).fetch("steps")
  end

  def all_steps
    workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps") }
  end

  def run_texts
    all_steps.filter_map { |step| step["run"] }
  end

  # The one step of the job for which the block is true.
  def find_step(job_name)
    found = steps_of(job_name).select { |step| yield(step) }
    assert_equal 1, found.size, "expected one such step in the job #{job_name}, found #{found.size}"
    found.first
  end

  def step_running(job_name, text)
    find_step(job_name) { |step| step["run"].to_s.include?(text) }
  end

  def step_using(job_name, action)
    find_step(job_name) { |step| step["uses"].to_s.start_with?("#{action}@") }
  end

  # The names of the secrets that something (a step, a job, a whole workflow) reads, sorted.
  def secrets_in(thing)
    JSON.generate(thing).scan(/secrets\.(\w+)/).flatten.uniq.sort
  end
end
