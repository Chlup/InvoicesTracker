# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "invoices_tracker/release_manifest"

class InvoicesTrackerReleaseManifestTest < Minitest::Test
  Manifest = InvoicesTracker::ReleaseManifest

  DMG_SHA = "a" * 64
  APPCAST_SHA = "b" * 64
  COMMIT = "0123456789abcdef0123456789abcdef01234567"

  def contents(latest_tag:)
    Manifest.contents(version: "1.7.0", build: "10", commit: COMMIT, dmg: "InvoicesTracker-1.7.0-10.dmg",
                      dmg_sha256: DMG_SHA, appcast_sha256: APPCAST_SHA, latest_tag: latest_tag)
  end

  def test_the_contents_describe_the_release_and_its_files
    assert_equal({ "version" => "1.7.0",
                   "build" => "10",
                   "tag" => "v1.7.0-10",
                   "title" => "InvoicesTracker 1.7.0 (10)",
                   "commit" => COMMIT,
                   "dmg" => "InvoicesTracker-1.7.0-10.dmg",
                   "dmg_sha256" => DMG_SHA,
                   "appcast_sha256" => APPCAST_SHA,
                   "notes" => "release-notes.md",
                   "latest_tag_seen" => "v1.6.0-9" },
                 contents(latest_tag: "v1.6.0-9"))
  end

  def test_the_keys_come_in_the_documented_order
    assert_equal %w[version build tag title commit dmg dmg_sha256 appcast_sha256 notes latest_tag_seen],
                 contents(latest_tag: nil).keys
  end

  # The publish job compares the Latest release it finds with this one, and an
  # empty string reads as "nothing was published".
  def test_no_latest_release_is_an_empty_string
    assert_equal "", contents(latest_tag: nil)["latest_tag_seen"]
  end

  def test_the_notes_file_name_is_the_one_the_feed_folder_holds
    assert_equal "release-notes.md", Manifest::NOTES_FILE_NAME
    assert_equal "release.json", Manifest::FILE_NAME
    assert_equal Manifest::NOTES_FILE_NAME, contents(latest_tag: nil)["notes"]
  end

  # The publish job reads the file with jq; every value is text.
  def test_the_json_parses_back_to_the_contents_and_ends_with_a_line_break
    text = Manifest.json(contents(latest_tag: "v1.6.0-9"))

    assert_equal contents(latest_tag: "v1.6.0-9"), JSON.parse(text)
    assert text.end_with?("}\n")
    assert(JSON.parse(text).values.all?(String))
  end
end
