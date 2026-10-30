# frozen_string_literal: true

require "json"

module InvoicesTracker
  # Reads the version numbers of the app out of `xcodebuild -showBuildSettings
  # -json` output and checks that they are fit to name and ship a release. Pure
  # parsing and validation with no I/O; callers run xcodebuild and pass its
  # output.
  module BuildSettings
    Versions = Struct.new(:marketing_version, :build, keyword_init: true)

    # The user-visible version: two or three numeric parts, "1.0" or "1.2.3".
    # Anchored with \A and \z because ^ and $ also match at a line break, which
    # would let "1.0\n" pass into a file name.
    MARKETING_VERSION_FORMAT = /\A\d+\.\d+(\.\d+)?\z/

    # The build number: a positive whole number without a leading zero.
    BUILD_FORMAT = /\A[1-9]\d*\z/

    module_function

    # xcodebuild prints one entry per target of the scheme, each with its own
    # settings, and the tests target's versions differ from the app's. Only the
    # entry of `target` is read, so the release is never named after another one.
    #
    # A setting the project does not define comes back as nil.
    def versions(show_build_settings_json, target:)
      entry = JSON.parse(show_build_settings_json).find { |candidate| candidate["target"] == target }
      raise ArgumentError, "no build settings for target #{target}" unless entry

      settings = entry.fetch("buildSettings")
      Versions.new(marketing_version: settings["MARKETING_VERSION"], build: settings["CURRENT_PROJECT_VERSION"])
    end

    # The problems that make these versions unusable for a release, empty when
    # they are fine. A value that is present but empty is malformed, not unset.
    def errors(versions)
      found = []

      marketing_version = versions.marketing_version
      if marketing_version.nil?
        found << "MARKETING_VERSION is not set"
      elsif !MARKETING_VERSION_FORMAT.match?(marketing_version)
        found << "MARKETING_VERSION '#{marketing_version}' is not X.Y or X.Y.Z"
      end

      build = versions.build
      if build.nil?
        found << "CURRENT_PROJECT_VERSION is not set"
      elsif !BUILD_FORMAT.match?(build)
        found << "CURRENT_PROJECT_VERSION '#{build}' is not a positive whole number"
      end

      found
    end
  end
end
