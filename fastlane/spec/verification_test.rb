# frozen_string_literal: true

require "minitest/autorun"
require "invoices_tracker/verification"

class InvoicesTrackerVerificationTest < Minitest::Test
  DMG = "/r/x.dmg"
  TEAM = "3VN358756R"

  NOTARIZED = "/r/x.dmg: accepted\nsource=Notarized Developer ID\n" \
              "origin=Developer ID Application: Michal  Fousek (3VN358756R)\n"

  # Shaped like `codesign -dv --verbose=2` of a signed disk image.
  CODESIGN = <<~OUT
    Executable=/r/x.dmg
    Identifier=x
    Format=disk image
    CodeDirectory v=20500 size=303 flags=0x0(none) hashes=3+0 location=embedded
    Signature size=9056
    Authority=Developer ID Application: Michal  Fousek (3VN358756R)
    Authority=Developer ID Certification Authority
    Authority=Apple Root CA
    Timestamp=20. 10. 2026 at 10:00:00
    Info.plist=not bound
    TeamIdentifier=3VN358756R
    Sealed Resources=none
    Internal requirements=none
  OUT

  def gatekeeper_errors(output, path: DMG)
    InvoicesTracker::Verification.gatekeeper_errors(output, path: path)
  end

  def staple_errors(output)
    InvoicesTracker::Verification.staple_errors(output, path: DMG)
  end

  def team_errors(output)
    InvoicesTracker::Verification.team_errors(output, path: DMG, team_id: TEAM)
  end

  def test_a_notarized_developer_id_dmg_passes_gatekeeper
    assert_empty gatekeeper_errors(NOTARIZED)
  end

  def test_a_rejected_or_unnotarized_dmg_fails_gatekeeper
    assert_equal ["Gatekeeper does not accept /r/x.dmg as notarized Developer ID: /r/x.dmg: rejected"],
                 gatekeeper_errors("/r/x.dmg: rejected\nsource=Unnotarized Developer ID\n")
    assert_equal ["Gatekeeper does not accept /r/x.dmg as notarized Developer ID: /r/x.dmg: accepted"],
                 gatekeeper_errors("/r/x.dmg: accepted\nsource=Developer ID\n")
  end

  # The verdict has to be about the image that was checked.
  def test_gatekeeper_accepting_another_file_does_not_count
    assert_equal 1, gatekeeper_errors(NOTARIZED.gsub("/r/x.dmg", "/r/y.dmg")).size
  end

  def test_the_path_is_matched_literally
    path = "/Users/me/My Releases (1)/x+y.dmg"

    assert_empty gatekeeper_errors("#{path}: accepted\nsource=Notarized Developer ID\n", path: path)
  end

  def test_gatekeeper_without_any_output_still_names_the_problem
    assert_equal ["Gatekeeper does not accept /r/x.dmg as notarized Developer ID: no output"], gatekeeper_errors("")
  end

  def test_staple_validation
    assert_empty staple_errors("Processing: /r/x.dmg\nThe validate action worked!\n")

    assert_equal ["/r/x.dmg has no valid notarization ticket stapled"],
                 staple_errors("Processing: /r/x.dmg\n/r/x.dmg does not have a ticket stapled to it.\n")
    assert_equal 1, staple_errors("Processing: /r/x.dmg\nThe validate action failed!\n").size
    assert_equal 1, staple_errors("").size
  end

  def test_team_of_the_signature
    assert_empty team_errors(CODESIGN)

    ["TeamIdentifier=EXAMPLE123", "TeamIdentifier=not set"].each do |line|
      assert_equal ["/r/x.dmg is not signed by team 3VN358756R (#{line})"],
                   team_errors(CODESIGN.sub("TeamIdentifier=3VN358756R", line))
    end
  end

  # An id that merely starts with the team's is another team.
  def test_the_team_identifier_must_match_the_whole_line
    errors = team_errors(CODESIGN.sub("TeamIdentifier=3VN358756R", "TeamIdentifier=3VN358756RX"))

    assert_equal ["/r/x.dmg is not signed by team 3VN358756R (TeamIdentifier=3VN358756RX)"], errors
  end

  def test_an_unsigned_image_has_no_team
    assert_equal ["/r/x.dmg is not signed by team 3VN358756R (no TeamIdentifier)"],
                 team_errors("/r/x.dmg: code object is not signed at all\n")
  end
end
