# frozen_string_literal: true

require "json"

module InvoicesTracker
  # Reads the version numbers of the app, and the Info.plist file it merges,
  # out of `xcodebuild -showBuildSettings -json` output, checks that the
  # numbers are fit to name and ship a release, and checks that they are the
  # ones typed for a release. Pure parsing and validation with no I/O; callers
  # run xcodebuild and pass its output.
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
      settings = target_settings(show_build_settings_json, target)
      Versions.new(marketing_version: settings["MARKETING_VERSION"], build: settings["CURRENT_PROJECT_VERSION"])
    end

    # The INFOPLIST_FILE setting of `target`, as the project writes it: the
    # Info.plist file that Xcode merges into the one it generates, which holds
    # the update settings, usually relative to the project's folder. Nil when
    # the target does not set it, or sets it to blank text. Raises
    # ArgumentError like `versions` when the output has no entry for `target`.
    def info_plist_file(show_build_settings_json, target:)
      file = target_settings(show_build_settings_json, target)["INFOPLIST_FILE"].to_s
      file.strip.empty? ? nil : file
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

    # The problems with the version and the build typed for a release, empty
    # when they are fine. Typed text tends to carry a space or a line break, so
    # both are trimmed first. Each must be in the format of its number (a `v`
    # before the version is refused) and must be the branch's own, since a
    # release is named after what the branch builds and its numbers are bumped
    # in a pull request, never at release time. The first argument holds the
    # branch's numbers, as `BuildSettings.versions` reads them; a number the
    # branch does not define differs from any typed one. A typed number that is
    # not in its format is reported as that alone: there is nothing to compare
    # it with.
    def mismatch_errors(versions, version:, build:)
      found = []

      typed_version = version.to_s.strip
      if !MARKETING_VERSION_FORMAT.match?(typed_version)
        found << "the typed version '#{typed_version}' is not X.Y or X.Y.Z"
      elsif versions.marketing_version != typed_version
        found << "the branch's MARKETING_VERSION is #{branch_number(versions.marketing_version)}, " \
                 "not the typed #{typed_version} — bump it in a PR first"
      end

      typed_build = build.to_s.strip
      if !BUILD_FORMAT.match?(typed_build)
        found << "the typed build '#{typed_build}' is not a positive whole number"
      elsif versions.build != typed_build
        found << "the branch's CURRENT_PROJECT_VERSION is #{branch_number(versions.build)}, " \
                 "not the typed #{typed_build} — bump it in a PR first"
      end

      found
    end

    # The problems with the format of the version and the build typed for a
    # release, version first, empty when both are well formed: the part of
    # `mismatch_errors` that needs no branch, in the same words. Both are
    # trimmed first. For a check before the branch's numbers are known, or when
    # they could not be read.
    def typed_format_errors(version:, build:)
      found = []

      typed_version = version.to_s.strip
      unless MARKETING_VERSION_FORMAT.match?(typed_version)
        found << "the typed version '#{typed_version}' is not X.Y or X.Y.Z"
      end

      typed_build = build.to_s.strip
      found << "the typed build '#{typed_build}' is not a positive whole number" unless BUILD_FORMAT.match?(typed_build)

      found
    end

    # The build settings of `target` in the output of `xcodebuild
    # -showBuildSettings -json`, which has one entry per target of the scheme.
    # The output is read as UTF-8, which it is, whatever its string is
    # labelled with: Open3 labels it with the locale's encoding, which may be
    # US-ASCII, and the parser refuses any other letter under that label.
    # Raises ArgumentError when it has no entry for `target`.
    def target_settings(show_build_settings_json, target)
      json = show_build_settings_json.to_s.dup.force_encoding(Encoding::UTF_8)
      entry = JSON.parse(json).find { |candidate| candidate["target"] == target }
      raise ArgumentError, "no build settings for target #{target}" unless entry

      entry.fetch("buildSettings")
    end
    private_class_method :target_settings

    # A number of the branch as it reads in a message: the number itself, or
    # "unset" when the branch does not define it.
    def branch_number(value)
      value.to_s.empty? ? "unset" : value
    end
    private_class_method :branch_number
  end
end
