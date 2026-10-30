# frozen_string_literal: true

require "minitest/autorun"
require "open3"

# Bundler on the release runner. ruby/setup-ruby installs the gems into the checkout, and the lane refuses a working
# copy with files git does not know, so what Bundler writes there must be ignored.
#
# The lockfile lists no platform for the runner. RubyGems takes the platform from the Ruby build
# (RbConfig::CONFIG["arch"]), not from the machine the Ruby runs on: the Ruby of a Mac that has moved on to macOS 27
# still reports arm64-darwin-25, and the prebuilt Ruby that ruby/setup-ruby installs reports the platform of the macOS
# it was built on. So no platform can be listed for the runner with any certainty. What lets a frozen install work on
# any runner is that the lockfile lists the `ruby` platform and holds no platform-specific gem.
class InvoicesTrackerBundlerOnTheRunnerTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)

  def test_the_lockfile_keeps_the_ruby_platform_and_lists_no_platform_specific_gem
    lockfile = File.read(File.join(REPO_ROOT, "Gemfile.lock"), encoding: "UTF-8")
    platforms = lockfile[/^PLATFORMS\n((?:  .+\n)+)/, 1].to_s.lines.map(&:strip)
    # The gems of the GEM section: four spaces, the name, the version in parentheses. A gem made for one platform has
    # the platform behind its version, as in "nokogiri (1.16.0-arm64-darwin)".
    gems = lockfile.scan(/^    (\S+) \(([^)]+)\)$/)
    platform_specific = gems.select { |_name, version| version.include?("-") }
                            .map { |name, version| "#{name} (#{version})" }

    assert_includes platforms, "ruby"
    refute_empty gems, "no gem found in the lockfile"
    assert_empty platform_specific, "gems made for one platform: #{platform_specific.join(', ')}"
  end

  def test_git_ignores_what_setup_ruby_writes_into_the_checkout
    %w[.bundle/config vendor/bundle/ruby/4.0.0/gems/fastlane-2.240.1/lib/fastlane.rb].each do |path|
      _output, status = Open3.capture2e("git", "-C", REPO_ROOT, "check-ignore", "-q", "--", path)

      assert_equal 0, status.exitstatus, "git does not ignore #{path}"
    end
  end
end
