# frozen_string_literal: true

require "minitest/autorun"
require "invoices_tracker/api_key_settings"
require "invoices_tracker/preflight"
require "invoices_tracker/signing_identity"

class InvoicesTrackerPreflightTest < Minitest::Test
  SETTINGS = InvoicesTracker::ApiKeySettings
  KEY_FILE = "/r/fastlane/AuthKey_X.p8"
  ROOT_KEY_FILE = "/r/AuthKey_X.p8"
  NO_IDENTITY = "no valid 'Developer ID Application' identity for team 3VN358756R in the keychain"

  # A context in which every check passes; each test breaks what it examines.
  def good_context(**overrides)
    identity = InvoicesTracker::SigningIdentity::Identity.new(
      sha1: "C" * 40, name: "Developer ID Application: Michal  Fousek (3VN358756R)"
    )
    InvoicesTracker::Preflight::Context.new(
      **{
        dirty_paths: [], missing_tools: [],
        api_key_settings: key_settings,
        identity_result: InvoicesTracker::SigningIdentity::Result.new(identity: identity, error: nil),
        version_errors: []
      }.merge(overrides)
    )
  end

  # Settings that are all set, with the key file found where it was looked for
  # first; each test changes what it examines.
  def key_settings(**overrides)
    SETTINGS::Result.new(
      **{
        key_id: "X", issuer_id: "issuer", key_file: KEY_FILE,
        key_file_candidates: [KEY_FILE, ROOT_KEY_FILE], missing: []
      }.merge(overrides)
    )
  end

  def key_file_not_found
    key_settings(key_file: nil)
  end

  def failed_identity(message)
    InvoicesTracker::SigningIdentity::Result.new(identity: nil, error: message)
  end

  def check(**overrides)
    InvoicesTracker::Preflight.check(good_context(**overrides))
  end

  def test_a_good_context_is_ok
    report = check

    assert_predicate report, :ok?
    assert_empty report.errors
  end

  def test_uncommitted_changes_stop_the_lane
    report = check(dirty_paths: ["?? notes.txt"])

    refute_predicate report, :ok?
    assert_equal ["uncommitted changes — commit or stash them first: ?? notes.txt"], report.errors
  end

  def test_long_change_lists_are_cut_after_ten
    error = check(dirty_paths: (1..12).map { |i| " M file#{i}.swift" }).errors.fetch(0)

    assert error.end_with?(" …"), error
    assert_includes error, " M file10.swift"
    refute_includes error, "file11.swift"
  end

  def test_ten_changed_paths_are_listed_in_full
    paths = (1..10).map { |i| "?? f#{i}" }

    assert_equal ["uncommitted changes — commit or stash them first: #{paths.join(', ')}"],
                 check(dirty_paths: paths).errors
  end

  def test_each_problem_is_reported
    report = check(
      missing_tools: ["create-dmg"],
      api_key_settings: key_settings(key_id: nil, key_file: nil, missing: [SETTINGS::KEY_ID]),
      identity_result: failed_identity(NO_IDENTITY),
      version_errors: ["MARKETING_VERSION '1' is not X.Y or X.Y.Z"]
    )

    refute_predicate report, :ok?
    assert_equal [
      "create-dmg is not installed — brew install create-dmg",
      "ASC_KEY_ID (or APP_STORE_CONNECT_API_KEY_KEY_ID) is not set in fastlane/.env (see fastlane/.env.example)",
      "App Store Connect API key file not found: /r/fastlane/AuthKey_X.p8 or /r/AuthKey_X.p8",
      NO_IDENTITY,
      "MARKETING_VERSION '1' is not X.Y or X.Y.Z"
    ], report.errors
  end

  def test_errors_come_in_a_fixed_order_with_one_for_each_missing_tool_and_setting
    report = check(
      dirty_paths: ["?? a.txt"], missing_tools: ["create-dmg", "other-tool"],
      api_key_settings: key_settings(
        key_id: nil, issuer_id: nil, key_file: nil, missing: [SETTINGS::KEY_ID, SETTINGS::ISSUER_ID]
      ),
      identity_result: failed_identity(NO_IDENTITY), version_errors: ["version one", "version two"]
    )

    assert_equal [
      "uncommitted changes — commit or stash them first: ?? a.txt",
      "create-dmg is not installed — brew install create-dmg",
      "other-tool is not installed — brew install other-tool",
      "ASC_KEY_ID (or APP_STORE_CONNECT_API_KEY_KEY_ID) is not set in fastlane/.env (see fastlane/.env.example)",
      "ASC_ISSUER_ID (or APP_STORE_CONNECT_API_KEY_ISSUER_ID) is not set in fastlane/.env (see fastlane/.env.example)",
      "App Store Connect API key file not found: /r/fastlane/AuthKey_X.p8 or /r/AuthKey_X.p8",
      NO_IDENTITY,
      "version one",
      "version two"
    ], report.errors
  end

  # The error names every path the key file was looked for at.
  def test_a_key_file_found_nowhere_names_each_place_it_was_looked_for
    assert_equal ["App Store Connect API key file not found: /r/fastlane/AuthKey_X.p8 or /r/AuthKey_X.p8"],
                 check(api_key_settings: key_file_not_found).errors
    assert_equal ["App Store Connect API key file not found: /keys/AuthKey_X.p8"],
                 check(api_key_settings: key_settings(key_file: nil, key_file_candidates: ["/keys/AuthKey_X.p8"])).errors
  end

  def test_a_key_file_found_in_the_second_place_is_fine
    assert_predicate check(api_key_settings: key_settings(key_file: ROOT_KEY_FILE)), :ok?
  end

  # No key path means the setting that holds it is not set, which is reported
  # as such; there is no file to look for.
  def test_without_a_key_path_only_the_missing_setting_is_reported
    report = check(
      api_key_settings: key_settings(key_file: nil, key_file_candidates: [], missing: [SETTINGS::KEY_FILEPATH])
    )

    assert_equal [
      "ASC_KEY_FILEPATH (or APP_STORE_CONNECT_API_KEY_KEY_FILEPATH) is not set in fastlane/.env " \
      "(see fastlane/.env.example)"
    ], report.errors
  end
end
