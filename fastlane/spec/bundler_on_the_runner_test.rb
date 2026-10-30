# frozen_string_literal: true

require "minitest/autorun"
require "open3"

# Bundler on the release runner. ruby/setup-ruby installs the gems into the checkout, and the lane refuses a working
# copy with files git does not know, so what Bundler writes there must be ignored. The lockfile must already list the
# runner's platform, or Bundler on the runner could rewrite it.
class InvoicesTrackerBundlerOnTheRunnerTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)

  # RubyGems names a platform after the number of the Darwin kernel, which is 27 on macOS 27.
  RUNNER_PLATFORM = "arm64-darwin-27"

  def test_the_lockfile_lists_the_platform_of_the_runner
    lockfile = File.read(File.join(REPO_ROOT, "Gemfile.lock"))
    platforms = lockfile[/^PLATFORMS\n((?:  .+\n)+)/, 1].to_s.lines.map(&:strip)

    assert_includes platforms, RUNNER_PLATFORM
  end

  def test_git_ignores_what_setup_ruby_writes_into_the_checkout
    %w[.bundle/config vendor/bundle/ruby/4.0.0/gems/fastlane-2.240.1/lib/fastlane.rb].each do |path|
      _output, status = Open3.capture2e("git", "-C", REPO_ROOT, "check-ignore", "-q", "--", path)

      assert_equal 0, status.exitstatus, "git does not ignore #{path}"
    end
  end
end
