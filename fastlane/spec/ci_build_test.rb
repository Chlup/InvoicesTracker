# frozen_string_literal: true

require "minitest/autorun"
require "shellwords"
require "invoices_tracker/ci_build"

class InvoicesTrackerCiBuildTest < Minitest::Test
  CiBuild = InvoicesTracker::CiBuild

  def test_skip_testing_names_exactly_the_four_timing_suites_of_the_test_target
    assert_equal ["InvoicesTrackerTests/InvoiceListPerformanceTests",
                  "InvoicesTrackerTests/InvoiceNetIncomePerformanceTests",
                  "InvoicesTrackerTests/InvoiceRepositoryPerformanceTests",
                  "InvoicesTrackerTests/SearchPerformanceTests"],
                 CiBuild.skip_testing
  end

  # The runner has no Apple Development certificate, so the test build signs
  # ad hoc: no identity, no team and no profile, and manual signing so that
  # xcodebuild does not try to fetch any.
  def test_the_test_build_signs_ad_hoc_and_skips_macro_validation
    assert_equal ["-skipMacroValidation", "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=",
                  "PROVISIONING_PROFILE_SPECIFIER="],
                 CiBuild.test_xcargs
  end

  # fastlane splits xcargs like a shell command line, so the joined form must
  # come back as the same words.
  def test_the_test_xcargs_survive_a_shell_round_trip
    assert_equal CiBuild.test_xcargs, Shellwords.split(Shellwords.join(CiBuild.test_xcargs))
  end

  def test_the_lists_cannot_be_changed_by_a_caller
    CiBuild.test_xcargs << "EXTRA=1"
    CiBuild.skip_testing << "InvoicesTrackerTests/Other"

    refute_includes CiBuild.test_xcargs, "EXTRA=1"
    refute_includes CiBuild.skip_testing, "InvoicesTrackerTests/Other"
  end

  # codesign is told which keychain holds the identity. The flag and the path
  # are the value of one build setting, so they stay one word on the command
  # line that fastlane builds from the joined form.
  def test_the_archive_signs_from_the_temporary_keychain_without_provisioning_updates
    xcargs = CiBuild.archive_xcargs(keychain: "/runner/temp/invoices-release.keychain-db")

    assert_equal ["-skipMacroValidation", "OTHER_CODE_SIGN_FLAGS=--keychain /runner/temp/invoices-release.keychain-db"],
                 xcargs
    assert_equal xcargs, Shellwords.split(Shellwords.join(xcargs))
    refute(xcargs.any? { |arg| arg.include?("allowProvisioningUpdates") })
  end

  def test_the_keychain_lives_in_the_runners_temporary_folder
    assert_equal "/Users/runner/work/_temp/invoices-release.keychain-db",
                 CiBuild.keychain_path("/Users/runner/work/_temp")
  end

  def test_a_ci_runner_with_a_temporary_folder_may_run_the_lane
    assert_empty CiBuild.environment_errors({ "CI" => "true", "RUNNER_TEMP" => "/Users/runner/work/_temp" })
  end

  def test_outside_ci_or_without_a_temporary_folder_the_lane_refuses_with_both_reasons
    assert_equal ["this lane runs only on a CI runner (CI=true); on a Mac, use the dmg lane",
                  "RUNNER_TEMP is not set"],
                 CiBuild.environment_errors({})
    assert_equal ["this lane runs only on a CI runner (CI=true); on a Mac, use the dmg lane"],
                 CiBuild.environment_errors({ "CI" => "1", "RUNNER_TEMP" => "/tmp/x" })
    assert_equal ["RUNNER_TEMP is not set"], CiBuild.environment_errors({ "CI" => "true", "RUNNER_TEMP" => "  " })
  end

  # fastlane turns `true`, `yes`, `false` and `no` on its command line into
  # booleans before the lane sees them; a caller in Ruby may pass the text.
  def test_a_flag_is_true_or_false_and_absent_means_false
    assert_equal true, CiBuild.flag(true, name: :deploy)
    assert_equal true, CiBuild.flag("true", name: :deploy)
    assert_equal false, CiBuild.flag(false, name: :deploy)
    assert_equal false, CiBuild.flag("false", name: :deploy)
    assert_equal false, CiBuild.flag(nil, name: :deploy)
  end

  # A typo must not quietly turn a deploy into a dry run, or the reverse.
  def test_any_other_flag_value_is_refused_and_shown_quoted
    ["True", "1", "", "deploy\n::error::x"].each do |bad|
      error = assert_raises(ArgumentError, bad.inspect) { CiBuild.flag(bad, name: :deploy) }

      assert_equal "deploy must be true or false, not #{bad.inspect}", error.message
      refute_includes error.message, "\n"
    end
  end
end
