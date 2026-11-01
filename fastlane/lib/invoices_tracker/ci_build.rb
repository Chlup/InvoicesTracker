# frozen_string_literal: true

module InvoicesTracker
  # What a release build on a GitHub-hosted runner does differently from one on
  # Michal's Mac: where it may run, the flags it is started with, the tests it
  # leaves out, how the test build is signed, and how the archive finds the
  # Developer ID identity in the temporary keychain. Pure: the lane runs the
  # tools with what these give.
  module CiBuild
    # The test target of the scheme, which names the suites to leave out.
    TEST_TARGET = "InvoicesTrackerTests"

    # The suites that fail when an operation takes longer than 500 ms. GitHub's
    # shared runners are slower than Michal's Mac, so on CI they would fail
    # without anything being wrong; the local lane still runs them.
    SKIPPED_TEST_SUITES = %w[
      InvoiceListPerformanceTests
      InvoiceNetIncomePerformanceTests
      InvoiceRepositoryPerformanceTests
      SearchPerformanceTests
    ].freeze

    # The build settings of the test build. The runner has no Apple Development
    # certificate, so the app and its tests are signed ad hoc (`-`): manual
    # signing with no team and no profile, so that xcodebuild looks for neither.
    TEST_XCARGS = [
      "-skipMacroValidation",
      "CODE_SIGN_IDENTITY=-",
      "CODE_SIGN_STYLE=Manual",
      "DEVELOPMENT_TEAM=",
      "PROVISIONING_PROFILE_SPECIFIER="
    ].freeze

    # The name of the temporary keychain, in the runner's temporary folder. The
    # workflow deletes a keychain of this name that a failed run left behind.
    KEYCHAIN_NAME = "invoices-release.keychain-db"

    module_function

    # The tests the CI build leaves out, as `run_tests` takes them for
    # `-skip-testing`: `<test target>/<suite>`. A new list on every call.
    def skip_testing
      SKIPPED_TEST_SUITES.map { |suite| "#{TEST_TARGET}/#{suite}" }
    end

    # The arguments for xcodebuild when it builds and runs the tests on CI, one
    # word each. A new list on every call.
    def test_xcargs
      TEST_XCARGS.dup
    end

    # The arguments for xcodebuild when it archives the app on CI, one word
    # each. The app target alone is switched to manual signing in the project
    # file, with the Developer ID identity and profile, so nothing here forces
    # a signing setting onto the package targets. codesign is pointed at
    # `keychain`, the temporary keychain that holds the identity. There is no
    # `-allowProvisioningUpdates`: the runner must not register itself as a
    # device or change the profile.
    def archive_xcargs(keychain:)
      ["-skipMacroValidation", "OTHER_CODE_SIGN_FLAGS=--keychain #{keychain}"]
    end

    # The temporary keychain inside `runner_temp`, the runner's temporary
    # folder, which the runner empties after every job.
    def keychain_path(runner_temp)
      File.join(runner_temp, KEYCHAIN_NAME)
    end

    # Why the CI lane must not run in the environment `env`, read like ENV;
    # empty when it may. It changes the user's keychain search list and works
    # in the runner's temporary folder, so it runs only where `CI` is `true`, as
    # GitHub sets it, and `RUNNER_TEMP` names that folder.
    def environment_errors(env)
      errors = []
      errors << "this lane runs only on a CI runner (CI=true); on a Mac, use the dmg lane" unless env["CI"] == "true"
      errors << "RUNNER_TEMP is not set" if env["RUNNER_TEMP"].to_s.strip.empty?
      errors
    end

    # A lane option that is true or false. fastlane turns `true` and `false` on
    # its command line into booleans; the text of either counts as well, and a
    # missing option is false. Raises ArgumentError for anything else, quoting
    # the value with `inspect`, so a typo never quietly picks the other choice
    # and a line break in it cannot start a new line of the log.
    def flag(value, name:)
      case value
      when true, "true" then true
      when false, "false", nil then false
      else raise ArgumentError, "#{name} must be true or false, not #{value.inspect}"
      end
    end
  end
end
