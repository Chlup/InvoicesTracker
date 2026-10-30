# frozen_string_literal: true

require_relative "working_copy"

module InvoicesTracker
  # Turns the facts gathered before a release build into one ordered list of
  # problems, so everything that is wrong shows at once instead of one thing per
  # run. No I/O: the lane gathers the facts and acts on the verdict.
  module Preflight
    # What the lane found out about the working copy and the machine:
    # - `dirty_paths`: the lines of `git status --porcelain`, which lists
    #   untracked files that are not ignored as well as modified ones.
    # - `missing_tools`: required command-line tools that are not installed.
    # - `api_key_settings`: the ApiKeySettings::Result for the App Store
    #   Connect API key: the settings that are not set, and where the key file
    #   was looked for and found.
    # - `identity_result`: the SigningIdentity::Result of the keychain lookup.
    # - `version_errors`: the problems BuildSettings.errors found.
    Context = Struct.new(
      :dirty_paths, :missing_tools, :api_key_settings, :identity_result, :version_errors,
      keyword_init: true
    )

    Report = Struct.new(:errors) do
      def ok?
        errors.empty?
      end
    end

    # The Homebrew formula to install for a tool whose formula is not named like
    # the tool: python3 comes from `python`. Every other tool is installed by its
    # own name.
    FORMULAE = { "python3" => "python" }.freeze

    module_function

    # The errors come in a fixed order: the working copy, missing tools, missing
    # settings, the key file, the signing identity, the versions.
    def check(ctx)
      errors = []

      unless ctx.dirty_paths.empty?
        errors << "uncommitted changes — commit or stash them first: #{WorkingCopy.list_paths(ctx.dirty_paths)}"
      end

      ctx.missing_tools.each do |tool|
        errors << "#{tool} is not installed — brew install #{FORMULAE.fetch(tool, tool)}"
      end

      settings = ctx.api_key_settings
      settings.missing.each do |setting|
        errors << "#{setting.label} is not set in fastlane/.env (see fastlane/.env.example)"
      end

      # Without a configured path there is no file to look for; the setting that
      # holds the path is reported above when it is missing.
      if settings.key_file.nil? && !settings.key_file_candidates.empty?
        errors << "App Store Connect API key file not found: #{settings.key_file_candidates.join(' or ')}"
      end

      errors << ctx.identity_result.error unless ctx.identity_result.ok?
      errors.concat(ctx.version_errors)

      Report.new(errors)
    end
  end
end
