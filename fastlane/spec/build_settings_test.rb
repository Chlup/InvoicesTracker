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
end
