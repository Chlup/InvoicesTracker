# frozen_string_literal: true

require "minitest/autorun"
require "invoices_tracker/dmg"

class InvoicesTrackerDmgTest < Minitest::Test
  def test_filename_joins_name_version_and_build
    assert_equal "InvoicesTracker-1.0-1.dmg",
                 InvoicesTracker::Dmg.filename(app_name: "InvoicesTracker", version: "1.0", build: "1")
  end

  def test_filename_turns_spaces_into_hyphens
    assert_equal "Invoices-Tracker-1.2.3-45.dmg",
                 InvoicesTracker::Dmg.filename(app_name: " Invoices  Tracker ", version: "1.2.3", build: "45")
  end

  def test_create_dmg_command_lays_out_the_app_and_the_applications_link
    assert_equal [
      "create-dmg", "--volname", "InvoicesTracker",
      "--window-pos", "200", "120", "--window-size", "600", "400", "--icon-size", "128",
      "--icon", "InvoicesTracker.app", "150", "190", "--app-drop-link", "450", "190",
      "--hide-extension", "InvoicesTracker.app", "/r/build/release/x.dmg", "/r/build/release/dmg-staging"
    ], InvoicesTracker::Dmg.create_dmg_command(
      app_bundle: "InvoicesTracker.app", source_dir: "/r/build/release/dmg-staging",
      dmg_path: "/r/build/release/x.dmg", volname: "InvoicesTracker"
    )
  end

  def test_create_dmg_command_adds_the_volume_icon_only_when_given
    cmd = InvoicesTracker::Dmg.create_dmg_command(
      app_bundle: "InvoicesTracker.app", source_dir: "/s", dmg_path: "/d.dmg", volname: "InvoicesTracker",
      volicon: "/a/AppIcon.icns"
    )
    assert_equal ["create-dmg", "--volname", "InvoicesTracker", "--volicon", "/a/AppIcon.icns"], cmd.first(5)
    refute_includes InvoicesTracker::Dmg.create_dmg_command(
      app_bundle: "InvoicesTracker.app", source_dir: "/s", dmg_path: "/d.dmg", volname: "InvoicesTracker"
    ), "--volicon"
  end

  def test_codesign_command_signs_with_the_given_identity_and_a_secure_timestamp
    assert_equal ["codesign", "--sign", "C0FFEE", "--timestamp", "--force", "/d.dmg"],
                 InvoicesTracker::Dmg.codesign_command(path: "/d.dmg", identity: "C0FFEE")
  end

  # There is deliberately no default: a bare "Developer ID Application" selector
  # would also match another team's certificate in the same keychain.
  def test_codesign_command_has_no_default_identity
    assert_raises(ArgumentError) { InvoicesTracker::Dmg.codesign_command(path: "/d.dmg") }
  end
end
