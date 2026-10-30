# frozen_string_literal: true

require "minitest/autorun"

# The README says how to set up and start the release workflow, and AGENTS.md points to it. The checks look for the
# facts the text has to carry (names, commands, warnings), not for its wording or where it wraps a line.
class InvoicesTrackerReleaseDocsTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  README = File.join(REPO_ROOT, "fastlane", "README.md")
  AGENTS = File.join(REPO_ROOT, "AGENTS.md")

  # The secrets of the environment `release`, the ones the workflow reads.
  SECRETS = %w[
    ASC_ISSUER_ID ASC_KEY_ID ASC_KEY_P8 DEVELOPER_ID_P12 DEVELOPER_ID_P12_PASSWORD SPARKLE_PRIVATE_KEY
  ].freeze

  # What every command that sets a secret of the environment carries.
  SECRET_FLAGS = "--env release --repo Chlup/InvoicesTracker"

  # The suites the CI build leaves out.
  LEFT_OUT_SUITES = %w[
    InvoiceListPerformanceTests InvoiceNetIncomePerformanceTests InvoiceRepositoryPerformanceTests
    SearchPerformanceTests
  ].freeze

  def test_the_readme_has_a_section_on_releasing_from_github
    assert_match(/^## Release from GitHub$/, File.read(README, encoding: "UTF-8"))
  end

  def test_the_readme_says_how_to_create_the_release_environment_and_every_secret
    assert_match(/environment named `release`/, prose)
    assert_match(/Selected branches and tags/, prose)
    assert_match(/add `main`/, prose)
    SECRETS.each do |name|
      assert_match(/\bgh secret set #{name} .*--env release/, section, "no command that sets #{name}")
    end
  end

  # The repository is public and the keys are private: no key may end up in a file that is part of the checkout, and
  # none needs to sit in the clipboard. The .p12 goes from its file straight into the secret, and its file is saved
  # outside the checkout.
  def test_the_readme_pipes_the_developer_id_straight_into_the_secret_and_keeps_it_out_of_the_clipboard
    assert_match(%r{base64 -i (?:~|/)\S*\.p12 \| gh secret set DEVELOPER_ID_P12 #{SECRET_FLAGS}}, section)
    refute_match(/pbcopy|pbpaste/, section)
    assert_match(/\.p12 file[^.]*outside the checkout/, prose)
  end

  # The Sparkle key is exported into a temporary folder that is made for it, set as the secret from there, and the
  # folder is removed, so that the key file is never in the working directory.
  def test_the_readme_exports_the_sparkle_key_into_a_temporary_folder_outside_the_checkout
    commands = section_on_one_line_per_command

    assert_includes commands, "dir=$(mktemp -d)"
    assert_includes commands, '/generate_keys" --account InvoicesTracker -x "$dir/sparkle-key.txt"'
    assert_includes commands, %(gh secret set SPARKLE_PRIVATE_KEY #{SECRET_FLAGS} < "$dir/sparkle-key.txt")
    assert_includes commands, 'rm -rf "$dir"'
    refute_match(/-x sparkle-key\.txt|< sparkle-key\.txt/, section)
    assert_match(/temporary folder outside the checkout/, prose)
  end

  # An interactive zsh does not skip a # comment unless it is set to, so a command with a comment behind it, pasted
  # from the README, would run the comment as a command and leave an assignment before it unset.
  def test_no_command_line_of_the_readme_ends_in_a_comment
    commands = section.lines.select { |line| line.start_with?("    ") }

    refute_empty commands
    commented = commands.grep(/\s#(\s|$)/)
    assert_empty commented, "commands with a comment behind them: #{commented.map(&:strip).join(' | ')}"
  end

  # Sparkle's tools are unpacked in different places on different Macs.
  def test_the_readme_puts_generate_keys_in_the_bin_folder_of_the_sparkle_download_and_fixes_no_path
    assert_match(%r{`bin` folder of the Sparkle 2\.10\.1 download, for example `~/SparkleTools/bin`}, prose)
    refute_match(%r{^\s*~/SparkleTools/bin/generate_keys}, section)
  end

  def test_the_readme_says_to_keep_a_backup_of_the_sparkle_key_and_why
    assert_match(/backup of the Sparkle key/, prose)
    assert_match(/can never accept another update/, prose)
  end

  # The exported file is the only copy outside the keychain, and the folder with it is removed by a command. A block
  # of commands is pasted whole, so the advice to back the file up has to stand before the block that removes the
  # folder, and that command has to be a block of its own, to be pasted once the backup is made.
  def test_the_readme_has_the_backup_of_the_sparkle_key_before_the_command_that_removes_it
    backup = section.index(/backup of the Sparkle key/)
    removal = section.index('rm -rf "$dir"')

    refute_nil backup
    refute_nil removal
    assert_operator backup, :<, removal, "the advice to keep a backup comes after the command that removes the key"
    removal_block = command_blocks.find { |block| block.include?('rm -rf "$dir"') }
    %w[generate_keys mktemp].each do |command|
      refute_includes removal_block, command, "the removal is pasted together with #{command}, before any backup"
    end
    refute_includes removal_block, "gh secret set"
  end

  def test_the_readme_shows_how_to_start_a_run_from_the_web_and_from_a_terminal
    assert_match(/Actions tab/, prose)
    assert_includes section_on_one_line_per_command,
                    'gh workflow run release.yml -f branch=main -f version=1.7.0 -f build=10 -f deploy=true ' \
                    '-f changelog="$(cat notes.md)"'
  end

  def test_the_readme_explains_each_box_and_how_the_changelog_takes_line_breaks
    %w[branch version build changelog skip_tests deploy].each do |name|
      assert_includes section, "`#{name}`", "the box #{name} is not explained"
    end
    assert_includes section, '`\n`'
    assert_match(/spaces around them are ignored/i, prose)
  end

  def test_the_readme_says_where_the_results_land
    assert_includes section, "InvoicesTracker-<version>-<build>.dmg"
    assert_includes section, "v<version>-<build>"
    assert_includes section, "appcast.xml"
    assert_match(/Latest release/, prose)
  end

  def test_the_readme_says_what_to_do_after_a_failed_deploy
    assert_match(/draft/, prose)
    assert_match(/Releases page/, prose)
  end

  def test_the_readme_warns_about_hand_made_releases_and_about_who_may_use_the_secrets
    assert_match(/Only the workflow should create releases/, prose)
    assert_match(/anyone with write access/i, prose)
  end

  def test_the_readme_names_the_test_signing_of_the_runner_and_the_suites_it_leaves_out
    assert_match(/ad hoc/, prose)
    LEFT_OUT_SUITES.each { |suite| assert_includes section, "`#{suite}`" }
  end

  # The preflight's message about a missing setting names fastlane/.env, which a runner does not have.
  def test_the_readme_says_that_on_a_runner_the_settings_come_from_the_secrets
    assert_includes section, "`fastlane/.env`"
    assert_match(/secrets of the `release` environment/, prose)
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

  # The commands of the section as the reader pastes them: each run of lines indented by four spaces is one block.
  def command_blocks
    section.lines.slice_when { |before, after| before.start_with?("    ") != after.start_with?("    ") }
           .select { |lines| lines.first.start_with?("    ") }
           .map(&:join)
  end

  # The section with every run of white space, a line break included, made one space, for sentences that wrap.
  def prose
    section.gsub(/\s+/, " ")
  end
end
