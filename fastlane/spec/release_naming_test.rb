# frozen_string_literal: true

require "minitest/autorun"
require "invoices_tracker/release"
require "invoices_tracker/release_naming"

class InvoicesTrackerReleaseNamingTest < Minitest::Test
  def test_tag_joins_version_and_build_after_a_v
    assert_equal "v1.7.0-10", InvoicesTracker::ReleaseNaming.tag(version: "1.7.0", build: "10")
  end

  def test_title_names_the_app_the_version_and_the_build
    assert_equal "InvoicesTracker 1.7.0 (10)",
                 InvoicesTracker::ReleaseNaming.title(version: "1.7.0", build: "10")
  end

  def test_download_prefix_is_the_asset_folder_of_the_tag
    assert_equal "https://github.com/Chlup/InvoicesTracker/releases/download/v1.7.0-10/",
                 InvoicesTracker::ReleaseNaming.download_prefix(version: "1.7.0", build: "10")
  end

  def test_notes_filename_replaces_the_disk_image_extension_with_md
    assert_equal "InvoicesTracker-1.7.0-10.md",
                 InvoicesTracker::ReleaseNaming.notes_filename("InvoicesTracker-1.7.0-10.dmg")
  end

  def test_the_release_constants_name_the_repository_and_its_feed
    assert_equal "Chlup/InvoicesTracker", InvoicesTracker::Release::REPOSITORY
    assert_equal "https://github.com/Chlup/InvoicesTracker/releases", InvoicesTracker::Release::RELEASES_URL
    assert_equal "https://github.com/Chlup/InvoicesTracker/releases/latest/download/appcast.xml",
                 InvoicesTracker::Release::FEED_URL
  end
end
