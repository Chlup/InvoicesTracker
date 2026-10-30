# frozen_string_literal: true

require "minitest/autorun"
require "invoices_tracker/build_settings"

class InvoicesTrackerBuildSettingsTest < Minitest::Test
  # `xcodebuild -showBuildSettings -json` prints one entry per target of the
  # scheme. The tests target has different values on purpose, so reading the
  # wrong entry shows.
  JSON_OUT = '[{"action":"build","target":"InvoicesTracker","buildSettings":{"MARKETING_VERSION":"1.0","CURRENT_PROJECT_VERSION":"1"}},' \
             '{"action":"build","target":"InvoicesTrackerTests","buildSettings":{"MARKETING_VERSION":"9.9","CURRENT_PROJECT_VERSION":"99"}}]'

  def versions(marketing_version, build)
    InvoicesTracker::BuildSettings::Versions.new(marketing_version: marketing_version, build: build)
  end

  def errors(marketing_version, build)
    InvoicesTracker::BuildSettings.errors(versions(marketing_version, build))
  end

  # What is wrong with the numbers typed for a release when the branch's are
  # `project`.
  def mismatches(project, version:, build:)
    InvoicesTracker::BuildSettings.mismatch_errors(project, version: version, build: build)
  end

  def test_reads_the_versions_of_the_app_target
    result = InvoicesTracker::BuildSettings.versions(JSON_OUT, target: "InvoicesTracker")

    assert_equal "1.0", result.marketing_version
    assert_equal "1", result.build
  end

  def test_a_missing_target_raises
    error = assert_raises(ArgumentError) { InvoicesTracker::BuildSettings.versions(JSON_OUT, target: "Nope") }

    assert_equal "no build settings for target Nope", error.message
  end

  # A setting the project does not define is absent from the entry.
  def test_settings_the_project_does_not_define_are_nil
    json = '[{"action":"build","target":"InvoicesTracker","buildSettings":{}}]'
    result = InvoicesTracker::BuildSettings.versions(json, target: "InvoicesTracker")

    assert_nil result.marketing_version
    assert_nil result.build
  end

  def test_accepts_two_and_three_part_versions
    assert_empty errors("1.0", "1")
    assert_empty errors("1.2.3", "1")
  end

  def test_rejects_other_versions
    ["1", "1.0b", "v1.0", "", "1.2.3.4", "1.0\n"].each do |bad|
      assert_equal ["MARKETING_VERSION '#{bad}' is not X.Y or X.Y.Z"], errors(bad, "1"), bad.inspect
    end
  end

  def test_accepts_positive_whole_numbers_as_builds
    ["1", "10", "45", "2048"].each do |build|
      assert_empty errors("1.0", build), build
    end
  end

  def test_rejects_builds_that_are_not_positive_whole_numbers
    ["0", "1.2", "01", "", "-3", "7\n"].each do |bad|
      assert_equal ["CURRENT_PROJECT_VERSION '#{bad}' is not a positive whole number"], errors("1.0", bad), bad.inspect
    end
  end

  def test_missing_values_are_errors
    assert_equal ["MARKETING_VERSION is not set", "CURRENT_PROJECT_VERSION is not set"],
                 InvoicesTracker::BuildSettings.errors(InvoicesTracker::BuildSettings::Versions.new)
  end

  def test_both_problems_are_reported_version_first
    assert_equal ["MARKETING_VERSION 'v1' is not X.Y or X.Y.Z",
                  "CURRENT_PROJECT_VERSION '0' is not a positive whole number"],
                 errors("v1", "0")
  end

  def test_typed_numbers_that_are_the_projects_have_no_mismatch
    assert_equal [], mismatches(versions("1.7.0", "10"), version: "1.7.0", build: "10")
    assert_equal [], mismatches(versions("1.7", "2048"), version: "1.7", build: "2048")
  end

  def test_typed_values_are_trimmed_and_a_v_prefix_is_refused
    project = versions("1.7.0", "10")

    assert_equal [], mismatches(project, version: " 1.7.0 ", build: " 10\n")
    assert_equal ["the typed version 'v1.7.0' is not X.Y or X.Y.Z"],
                 mismatches(project, version: "v1.7.0", build: "10")
    assert_equal ["the typed version 'v1.7.0' is not X.Y or X.Y.Z"],
                 mismatches(project, version: " v1.7.0\n", build: "10")
  end

  def test_a_typed_build_that_is_not_a_positive_whole_number_is_refused
    project = versions("1.7.0", "10")

    assert_equal ["the typed build '10a' is not a positive whole number"],
                 mismatches(project, version: "1.7.0", build: "10a")
    ["0", "010", "1.5", "-3", ""].each do |bad|
      assert_equal ["the typed build '#{bad}' is not a positive whole number"],
                   mismatches(project, version: "1.7.0", build: bad), bad.inspect
    end
  end

  def test_typed_values_that_are_missing_are_refused_like_empty_ones
    assert_equal ["the typed version '' is not X.Y or X.Y.Z",
                  "the typed build '' is not a positive whole number"],
                 mismatches(versions("1.7.0", "10"), version: nil, build: nil)
  end

  def test_numbers_other_than_the_projects_ask_for_a_bump_in_a_pr
    old = versions("1.6.0", "9")

    assert_equal ["the branch's MARKETING_VERSION is 1.6.0, not the typed 1.7.0 — bump it in a PR first",
                  "the branch's CURRENT_PROJECT_VERSION is 9, not the typed 10 — bump it in a PR first"],
                 mismatches(old, version: "1.7.0", build: "10")
  end

  def test_only_the_number_that_differs_is_reported
    assert_equal ["the branch's CURRENT_PROJECT_VERSION is 9, not the typed 10 — bump it in a PR first"],
                 mismatches(versions("1.7.0", "9"), version: "1.7.0", build: "10")
    assert_equal ["the branch's MARKETING_VERSION is 1.6.0, not the typed 1.7.0 — bump it in a PR first"],
                 mismatches(versions("1.6.0", "10"), version: "1.7.0", build: "10")
  end

  # A typed number is the text the release is named after, so 1.7 is not 1.7.0.
  def test_numbers_are_compared_as_text
    assert_equal ["the branch's MARKETING_VERSION is 1.7, not the typed 1.7.0 — bump it in a PR first"],
                 mismatches(versions("1.7", "10"), version: "1.7.0", build: "10")
  end

  # The typed value is wrong in itself, so there is nothing to compare: the
  # error is the format one only, whatever the project holds.
  def test_a_format_error_replaces_the_comparison_for_that_value
    assert_equal ["the typed version 'v1.7.0' is not X.Y or X.Y.Z",
                  "the branch's CURRENT_PROJECT_VERSION is 9, not the typed 10 — bump it in a PR first"],
                 mismatches(versions("1.6.0", "9"), version: "v1.7.0", build: "10")
    assert_equal ["the branch's MARKETING_VERSION is 1.6.0, not the typed 1.7.0 — bump it in a PR first",
                  "the typed build '10a' is not a positive whole number"],
                 mismatches(versions("1.6.0", "9"), version: "1.7.0", build: "10a")
    assert_equal ["the typed version 'v1.7.0' is not X.Y or X.Y.Z",
                  "the typed build '10a' is not a positive whole number"],
                 mismatches(versions("1.6.0", "9"), version: "v1.7.0", build: "10a")
  end

  # `errors` reports a number the project does not define as such; here it
  # also differs from what was typed, and the message must still read.
  def test_a_number_the_project_does_not_define_is_a_mismatch
    assert_equal ["the branch's MARKETING_VERSION is unset, not the typed 1.7.0 — bump it in a PR first",
                  "the branch's CURRENT_PROJECT_VERSION is unset, not the typed 10 — bump it in a PR first"],
                 mismatches(InvoicesTracker::BuildSettings::Versions.new, version: "1.7.0", build: "10")
    assert_equal ["the branch's MARKETING_VERSION is unset, not the typed 1.7.0 — bump it in a PR first",
                  "the branch's CURRENT_PROJECT_VERSION is unset, not the typed 10 — bump it in a PR first"],
                 mismatches(versions("", ""), version: "1.7.0", build: "10")
  end
end
