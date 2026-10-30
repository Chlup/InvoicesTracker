# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"

class InvoicesTrackerReleaseScriptTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  SCRIPT = "Scripts/release.sh"

  def test_help_prints_usage_and_exits_zero
    stdout, _stderr, status = run_script("--help")

    assert_equal 0, status.exitstatus
    assert_includes stdout, "Usage: Scripts/release.sh [--skip-tests]"
  end

  def test_the_short_help_flag_prints_usage_too
    stdout, _stderr, status = run_script("-h")

    assert_equal 0, status.exitstatus
    assert_includes stdout, "Usage: Scripts/release.sh [--skip-tests]"
  end

  def test_runs_the_dmg_lane_with_tests_by_default
    stdout, _stderr, status = run_script(env: { "FASTLANE_CMD" => "echo" })

    assert_equal 0, status.exitstatus
    assert_equal "dmg skip_tests:false\n", stdout
  end

  def test_skip_tests_is_passed_on
    stdout, _stderr, status = run_script("--skip-tests", env: { "FASTLANE_CMD" => "echo" })

    assert_equal 0, status.exitstatus
    assert_equal "dmg skip_tests:true\n", stdout
  end

  def test_an_unknown_argument_is_an_error
    stdout, stderr, status = run_script("--frobnicate")

    assert_equal 2, status.exitstatus
    assert_includes stderr, "unknown argument: --frobnicate"
    assert_empty stdout, "a bad argument must not start the lane"
  end

  def test_runs_from_the_repository_root_whatever_the_callers_directory
    with_probe do |elsewhere, probe|
      stdout, _stderr, status = run_script(
        env: { "FASTLANE_CMD" => probe }, chdir: elsewhere, script: File.join(REPO_ROOT, SCRIPT)
      )

      assert_equal 0, status.exitstatus
      assert_equal File.realpath(REPO_ROOT), File.realpath(stdout.split("|").first)
    end
  end

  def test_gives_fastlane_a_utf8_locale_when_the_caller_has_none
    with_probe do |_dir, probe|
      stdout, _stderr, status = run_script(env: { "FASTLANE_CMD" => probe, "LANG" => nil, "LC_ALL" => nil })

      assert_equal 0, status.exitstatus
      assert_equal ["en_US.UTF-8", "en_US.UTF-8"], stdout.chomp.split("|").last(2)
    end
  end

  def test_keeps_the_locale_the_caller_has
    with_probe do |_dir, probe|
      stdout, _stderr, status = run_script(
        env: { "FASTLANE_CMD" => probe, "LANG" => "C.UTF-8", "LC_ALL" => "C.UTF-8" }
      )

      assert_equal 0, status.exitstatus
      assert_equal ["C.UTF-8", "C.UTF-8"], stdout.chomp.split("|").last(2)
    end
  end

  private

  # FASTLANE_CMD defaults to echo, so no test can ever start a real lane.
  def run_script(*args, env: {}, chdir: REPO_ROOT, script: SCRIPT)
    Open3.capture3({ "FASTLANE_CMD" => "echo" }.merge(env), script, *args, chdir: chdir)
  end

  # Yields a scratch directory and an executable that stands in for fastlane:
  # it ignores its arguments and prints "<cwd>|<LANG>|<LC_ALL>".
  def with_probe
    Dir.mktmpdir do |dir|
      probe = File.join(dir, "probe")
      File.write(probe, "#!/bin/sh\necho \"$PWD|$LANG|$LC_ALL\"\n")
      File.chmod(0o755, probe)
      yield dir, probe
    end
  end
end
