# frozen_string_literal: true

require "minitest/autorun"
require "invoices_tracker/api_key_settings"

class InvoicesTrackerApiKeySettingsTest < Minitest::Test
  SETTINGS = InvoicesTracker::ApiKeySettings

  # Every setting under this lane's own names, with a bare key file name.
  OWN_NAMES = {
    "ASC_KEY_ID" => "KEY123",
    "ASC_ISSUER_ID" => "issuer-1",
    "ASC_KEY_FILEPATH" => "AuthKey_KEY123.p8"
  }.freeze

  # Every setting under fastlane's standard names. fastlane's own actions run
  # from the repository root, so its key paths are relative to the root.
  STANDARD_NAMES = {
    "APP_STORE_CONNECT_API_KEY_KEY_ID" => "KEY456",
    "APP_STORE_CONNECT_API_KEY_ISSUER_ID" => "issuer-2",
    "APP_STORE_CONNECT_API_KEY_KEY_FILEPATH" => "fastlane/AuthKey_KEY456.p8"
  }.freeze

  # `existing` are the files that are there; nothing touches the disk.
  def resolve(env, existing: [])
    SETTINGS.resolve(env, fastlane_dir: "/r/fastlane", repo_root: "/r", file_exists: ->(path) { existing.include?(path) })
  end

  def values(result)
    [result.key_id, result.issuer_id, result.key_file]
  end

  def test_the_lanes_own_names
    result = resolve(OWN_NAMES, existing: ["/r/fastlane/AuthKey_KEY123.p8"])

    assert_equal ["KEY123", "issuer-1", "/r/fastlane/AuthKey_KEY123.p8"], values(result)
    assert_empty result.missing
  end

  def test_fastlanes_standard_names
    result = resolve(STANDARD_NAMES, existing: ["/r/fastlane/AuthKey_KEY456.p8"])

    assert_equal ["KEY456", "issuer-2", "/r/fastlane/AuthKey_KEY456.p8"], values(result)
    assert_empty result.missing
  end

  def test_the_lanes_own_name_comes_first_when_both_are_set
    result = resolve(OWN_NAMES.merge(STANDARD_NAMES),
                     existing: ["/r/fastlane/AuthKey_KEY123.p8", "/r/fastlane/AuthKey_KEY456.p8"])

    assert_equal ["KEY123", "issuer-1", "/r/fastlane/AuthKey_KEY123.p8"], values(result)
  end

  def test_an_empty_or_blank_own_name_falls_through_to_the_standard_one
    env = STANDARD_NAMES.merge("ASC_KEY_ID" => "", "ASC_ISSUER_ID" => " \t", "ASC_KEY_FILEPATH" => "\n")
    result = resolve(env, existing: ["/r/fastlane/AuthKey_KEY456.p8"])

    assert_equal ["KEY456", "issuer-2", "/r/fastlane/AuthKey_KEY456.p8"], values(result)
    assert_empty result.missing
  end

  def test_values_are_stripped
    env = { "ASC_KEY_ID" => " KEY123 ", "ASC_ISSUER_ID" => "issuer-1\n", "ASC_KEY_FILEPATH" => " AuthKey_KEY123.p8 " }
    result = resolve(env, existing: ["/r/fastlane/AuthKey_KEY123.p8"])

    assert_equal ["KEY123", "issuer-1", "/r/fastlane/AuthKey_KEY123.p8"], values(result)
  end

  def test_a_setting_set_under_neither_name_is_missing
    result = resolve({ "ASC_KEY_ID" => "KEY123", "APP_STORE_CONNECT_API_KEY_ISSUER_ID" => "  " })

    assert_nil result.issuer_id
    assert_equal [SETTINGS::ISSUER_ID, SETTINGS::KEY_FILEPATH], result.missing
  end

  def test_with_nothing_set_all_three_are_missing_in_order
    result = resolve({})

    assert_equal [nil, nil, nil], values(result)
    assert_equal [SETTINGS::KEY_ID, SETTINGS::ISSUER_ID, SETTINGS::KEY_FILEPATH], result.missing
  end

  def test_a_setting_is_named_by_both_of_its_names
    assert_equal "ASC_KEY_ID (or APP_STORE_CONNECT_API_KEY_KEY_ID)", SETTINGS::KEY_ID.label
    assert_equal "ASC_ISSUER_ID (or APP_STORE_CONNECT_API_KEY_ISSUER_ID)", SETTINGS::ISSUER_ID.label
    assert_equal "ASC_KEY_FILEPATH (or APP_STORE_CONNECT_API_KEY_KEY_FILEPATH)", SETTINGS::KEY_FILEPATH.label
  end

  # Where the key file is looked for.

  def test_an_absolute_key_path_is_used_as_it_is
    result = resolve(OWN_NAMES.merge("ASC_KEY_FILEPATH" => "/keys/AuthKey.p8"), existing: ["/keys/AuthKey.p8"])

    assert_equal ["/keys/AuthKey.p8"], result.key_file_candidates
    assert_equal "/keys/AuthKey.p8", result.key_file
  end

  def test_an_absolute_key_path_that_is_not_there_is_the_only_one_tried
    result = resolve(OWN_NAMES.merge("ASC_KEY_FILEPATH" => "/keys/AuthKey.p8"))

    assert_equal ["/keys/AuthKey.p8"], result.key_file_candidates
    assert_nil result.key_file
  end

  def test_a_relative_key_path_is_looked_up_under_fastlane_first
    result = resolve(OWN_NAMES, existing: ["/r/fastlane/AuthKey_KEY123.p8", "/r/AuthKey_KEY123.p8"])

    assert_equal ["/r/fastlane/AuthKey_KEY123.p8", "/r/AuthKey_KEY123.p8"], result.key_file_candidates
    assert_equal "/r/fastlane/AuthKey_KEY123.p8", result.key_file
  end

  def test_a_relative_key_path_is_found_under_the_repository_root_when_not_under_fastlane
    result = resolve(STANDARD_NAMES, existing: ["/r/fastlane/AuthKey_KEY456.p8"])

    assert_equal ["/r/fastlane/fastlane/AuthKey_KEY456.p8", "/r/fastlane/AuthKey_KEY456.p8"], result.key_file_candidates
    assert_equal "/r/fastlane/AuthKey_KEY456.p8", result.key_file
  end

  def test_a_relative_key_path_found_in_neither_place_lists_both
    result = resolve(OWN_NAMES)

    assert_equal ["/r/fastlane/AuthKey_KEY123.p8", "/r/AuthKey_KEY123.p8"], result.key_file_candidates
    assert_nil result.key_file
  end

  def test_without_a_key_path_there_is_nothing_to_look_for
    result = resolve(OWN_NAMES.reject { |name, _| name == "ASC_KEY_FILEPATH" }, existing: ["/r/fastlane"])

    assert_empty result.key_file_candidates
    assert_nil result.key_file
    assert_equal [SETTINGS::KEY_FILEPATH], result.missing
  end
end
