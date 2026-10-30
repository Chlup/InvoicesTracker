# frozen_string_literal: true

module InvoicesTracker
  # Reads the App Store Connect API key settings out of the environment and
  # works out where the key file is. Each setting has two accepted names: this
  # lane's own, and fastlane's standard one, which counts when the first is not
  # set. No I/O: callers pass the environment and a check for whether a file
  # exists. The key file itself is never read.
  module ApiKeySettings
    Setting = Struct.new(:name, :alternative, keyword_init: true) do
      # Both names, for a message about a setting that is not set.
      def label
        "#{name} (or #{alternative})"
      end
    end

    KEY_ID = Setting.new(name: "ASC_KEY_ID", alternative: "APP_STORE_CONNECT_API_KEY_KEY_ID").freeze
    ISSUER_ID = Setting.new(name: "ASC_ISSUER_ID", alternative: "APP_STORE_CONNECT_API_KEY_ISSUER_ID").freeze
    KEY_FILEPATH = Setting.new(name: "ASC_KEY_FILEPATH", alternative: "APP_STORE_CONNECT_API_KEY_KEY_FILEPATH").freeze

    # - `key_id`, `issuer_id`: the values, nil when not set.
    # - `key_file_candidates`: where the key file was looked for, in order;
    #   empty when no key path is set.
    # - `key_file`: the first candidate that exists, nil when none does.
    # - `missing`: the Settings set under neither name, in a fixed order.
    Result = Struct.new(:key_id, :issuer_id, :key_file, :key_file_candidates, :missing, keyword_init: true)

    module_function

    # `env` is read like ENV. `file_exists` takes a path and says whether a file
    # is there.
    def resolve(env, fastlane_dir:, repo_root:, file_exists:)
      key_path = value(env, KEY_FILEPATH)
      candidates = key_path ? key_file_candidates(key_path, fastlane_dir: fastlane_dir, repo_root: repo_root) : []

      Result.new(
        key_id: value(env, KEY_ID),
        issuer_id: value(env, ISSUER_ID),
        key_file: candidates.find { |path| file_exists.call(path) },
        key_file_candidates: candidates,
        missing: [KEY_ID, ISSUER_ID, KEY_FILEPATH].reject { |setting| value(env, setting) }
      )
    end

    # The value under the setting's own name, else under fastlane's. An empty
    # or blank value counts as not set, so it falls through to the other name.
    def value(env, setting)
      [setting.name, setting.alternative].each do |name|
        found = env[name].to_s.strip
        return found unless found.empty?
      end
      nil
    end
    private_class_method :value

    # An absolute path is used as it is. A relative one is looked up under
    # fastlane/ first, where this lane's .env.example puts the key, then under
    # the repository root, which is where fastlane's own actions resolve its
    # standard setting from.
    def key_file_candidates(key_path, fastlane_dir:, repo_root:)
      return [key_path] if File.absolute_path?(key_path)

      [File.expand_path(key_path, fastlane_dir), File.expand_path(key_path, repo_root)].uniq
    end
    private_class_method :key_file_candidates
  end
end
