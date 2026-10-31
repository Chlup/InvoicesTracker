# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"

# The keys a release needs are private and the repository is public. A key file that lands in the checkout must never
# be something to commit: the preflight lists every untracked file that git does not ignore under "uncommitted
# changes — commit or stash them first", which reads like an invitation to commit it. The checks ask git itself, in a
# scratch repository that holds a copy of the repository's .gitignore and none of the settings of the machine, so a
# global ignore file of the person who runs them cannot make a missing entry look fine.
class InvoicesTrackerGitignoreTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  GITIGNORE = File.join(REPO_ROOT, ".gitignore")

  # Git without the settings of the machine: no global or system configuration, and no global ignore file.
  GIT_ENVIRONMENT = { "GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_NOSYSTEM" => "1",
                      "XDG_CONFIG_HOME" => File::NULL }.freeze

  # Where a private key may end up: the App Store Connect key and its settings beside the lane (fastlane/.env is where
  # the README has the settings go), and the Developer ID identity exported from the keychain as a .p12 file, in the
  # root of the checkout or in any folder of it.
  PRIVATE_FILES = %w[
    fastlane/.env
    fastlane/AuthKey_ABC123DEFG.p8
    AuthKey_ABC123DEFG.p8
    DeveloperID.p12
    fastlane/DeveloperID.p12
    Scripts/ci/DeveloperID.p12
    build/DeveloperID.p12
  ].freeze

  # Files that look a little like them and are committed: the base64 text of a .p12 that the keychain specs use, and
  # the env files with no settings in them.
  COMMITTED_FILES = %w[
    fastlane/spec/fixtures/legacy_encryption.p12.base64
    fastlane/.env.default
    fastlane/.env.example
  ].freeze

  # An empty repository with a copy of the .gitignore.
  def setup
    @repository = Dir.mktmpdir("gitignore-check-")
    _output, status = Open3.capture2e(GIT_ENVIRONMENT, "git", "init", "--quiet", @repository)
    raise "git init failed in #{@repository}" unless status.success?

    FileUtils.cp(GITIGNORE, File.join(@repository, ".gitignore"))
  rescue Errno::ENOENT
    skip "git is not installed"
  end

  def teardown
    FileUtils.rm_rf(@repository)
  end

  def test_a_private_key_file_in_the_checkout_is_ignored_wherever_it_is
    not_ignored = PRIVATE_FILES.reject { |path| ignored?(path) }

    assert_empty not_ignored, "git would offer these for a commit: #{not_ignored.join(', ')}"
  end

  def test_the_committed_files_next_to_them_are_not_ignored
    ignored = COMMITTED_FILES.select { |path| ignored?(path) }

    assert_empty ignored, "git would not take these in: #{ignored.join(', ')}"
  end

  private

  # Whether the .gitignore makes git ignore `path`, which need not exist. `git check-ignore` says yes with status 0
  # and no with status 1; any other status means that git could not answer.
  def ignored?(path)
    output, status = Open3.capture2e(GIT_ENVIRONMENT, "git", "-C", @repository, "check-ignore", "--quiet", "--", path)
    assert_includes [0, 1], status.exitstatus, "git check-ignore could not answer for #{path}: #{output}"
    status.success?
  end
end
