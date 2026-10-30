# frozen_string_literal: true

require "minitest/autorun"

# The README says how to set up and start the release workflow, and AGENTS.md points to it. The checks look for the
# facts the text has to carry (names, commands, warnings), not for its wording.
class InvoicesTrackerReleaseDocsTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  README = File.join(REPO_ROOT, "fastlane", "README.md")
  AGENTS = File.join(REPO_ROOT, "AGENTS.md")

  # The secrets of the environment `release`, the ones the workflow reads.
  SECRETS = %w[
    ASC_ISSUER_ID ASC_KEY_ID ASC_KEY_P8 DEVELOPER_ID_P12 DEVELOPER_ID_P12_PASSWORD SPARKLE_PRIVATE_KEY
  ].freeze

  # The suites the CI build leaves out.
  LEFT_OUT_SUITES = %w[
    InvoiceListPerformanceTests InvoiceNetIncomePerformanceTests InvoiceRepositoryPerformanceTests
    SearchPerformanceTests
  ].freeze

  def test_the_readme_has_a_section_on_releasing_from_github
    assert_match(/^## Release from GitHub$/, File.read(README, encoding: "UTF-8"))
  end

  def test_the_readme_says_how_to_create_the_release_environment_and_every_secret
    assert_match(/environment named `release`/, section)
    assert_match(/Selected branches and tags/, section)
    assert_match(/add `main`/, section)
    SECRETS.each do |name|
      assert_match(/^\s*gh secret set #{name} .*--env release/, section, "no command that sets #{name}")
    end
  end

  def test_the_readme_says_how_to_export_the_developer_id_and_the_sparkle_key
    assert_includes section, "base64 -i"
    assert_includes section, "pbcopy"
    assert_includes section, "~/SparkleTools/bin/generate_keys --account InvoicesTracker -x"
    assert_match(%r{gh secret set SPARKLE_PRIVATE_KEY --env release --repo Chlup/InvoicesTracker < }, section)
    assert_match(/delete the file/i, section)
  end

  def test_the_readme_says_to_keep_a_backup_of_the_sparkle_key_and_why
    assert_match(/backup of the Sparkle key/, section)
    assert_match(/can never accept another update/, section)
  end

  def test_the_readme_shows_how_to_start_a_run_from_the_web_and_from_a_terminal
    assert_match(/Actions tab/, section)
    assert_includes section_on_one_line_per_command,
                    'gh workflow run release.yml -f branch=main -f version=1.7.0 -f build=10 -f deploy=true ' \
                    '-f changelog="$(cat notes.md)"'
  end

  def test_the_readme_explains_each_box_and_how_the_changelog_takes_line_breaks
    %w[branch version build changelog skip_tests deploy].each do |name|
      assert_includes section, "`#{name}`", "the box #{name} is not explained"
    end
    assert_includes section, '`\n`'
  end

  def test_the_readme_says_where_the_results_land
    assert_includes section, "InvoicesTracker-<version>-<build>.dmg"
    assert_includes section, "v<version>-<build>"
    assert_includes section, "appcast.xml"
    assert_match(/Latest release/, section)
  end

  def test_the_readme_says_what_to_do_after_a_failed_deploy
    assert_match(/draft/, section)
    assert_match(/Releases page/, section)
  end

  def test_the_readme_warns_about_hand_made_releases_and_about_who_may_use_the_secrets
    assert_match(/Only the workflow should create releases/, section)
    assert_match(/anyone with write access/i, section)
  end

  def test_the_readme_names_the_test_signing_of_the_runner_and_the_suites_it_leaves_out
    assert_match(/ad hoc/, section)
    LEFT_OUT_SUITES.each { |suite| assert_includes section, "`#{suite}`" }
  end

  # The preflight's message about a missing setting names fastlane/.env, which a runner does not have.
  def test_the_readme_says_that_on_a_runner_the_settings_come_from_the_secrets
    assert_includes section, "`fastlane/.env`"
    assert_match(/secrets of the `release` environment/, section)
  end

  def test_agents_md_names_the_workflow_and_points_to_the_readme_section
    agents = File.read(AGENTS, encoding: "UTF-8")

    assert_includes agents, ".github/workflows/release.yml"
    assert_match(/`fastlane\/README\.md`, "Release from GitHub"/, agents)
  end

  private

  # The text of the README between the heading "Release from GitHub" and the next heading of its level. The files
  # are read as UTF-8 whatever the locale of the process is.
  def section
    @section ||= File.read(README, encoding: "UTF-8")[/^## Release from GitHub$.*?(?=^## |\z)/m].to_s
  end

  # The section with each command that continues on the next line (a backslash at the end of the line) joined.
  def section_on_one_line_per_command
    section.gsub(/ \\\n\s*/, " ")
  end
end
