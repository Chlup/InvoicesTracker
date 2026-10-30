# frozen_string_literal: true

require "minitest/autorun"
require "invoices_tracker/signing_identity"

class InvoicesTrackerSigningIdentityTest < Minitest::Test
  TEAM = "3VN358756R"
  NAME = "Developer ID Application: Michal  Fousek (3VN358756R)"

  # Shaped like `security find-identity -v -p codesigning` on the real keychain,
  # which also holds another team's Developer ID certificate and this team's
  # distribution certificate. The SHA-1s are placeholders.
  OUTPUT = <<~OUT
      1) #{"A" * 40} "Apple Development: Michal  Fousek (S8YH6TS4BM)"
      5) #{"B" * 40} "Developer ID Application: Example Company LLC (EXAMPLE123)"
      8) #{"D" * 40} "Apple Distribution: Michal  Fousek (3VN358756R)"
     11) #{"C" * 40} "Developer ID Application: Michal  Fousek (3VN358756R)"
         11 valid identities found
  OUT

  def developer_id(output, team_id: TEAM)
    InvoicesTracker::SigningIdentity.developer_id(output, team_id: team_id)
  end

  def test_picks_the_developer_id_of_the_team
    result = developer_id(OUTPUT)

    assert_predicate result, :ok?
    assert_nil result.error
    assert_equal "C" * 40, result.identity.sha1
    assert_equal NAME, result.identity.name
  end

  def test_never_picks_another_teams_developer_id
    assert_equal "B" * 40, developer_id(OUTPUT, team_id: "EXAMPLE123").identity.sha1

    without_ours = OUTPUT.lines.reject { |line| line.include?("C" * 40) }.join
    result = developer_id(without_ours)

    refute_predicate result, :ok?
    assert_nil result.identity
    assert_equal "no valid 'Developer ID Application' identity for team 3VN358756R in the keychain", result.error
  end

  # The same certificate shows up once per keychain that holds it.
  def test_the_same_certificate_listed_twice_counts_once
    result = developer_id(OUTPUT + "  12) #{"C" * 40} \"#{NAME}\"\n")

    assert_predicate result, :ok?
    assert_equal "C" * 40, result.identity.sha1
  end

  def test_two_certificates_of_the_team_are_an_error
    result = developer_id(OUTPUT + "  12) #{"E" * 40} \"#{NAME}\"\n")

    refute_predicate result, :ok?
    assert_nil result.identity
    assert_equal "several 'Developer ID Application' identities for team 3VN358756R in the keychain: #{NAME}, #{NAME}",
                 result.error
  end

  def test_a_distribution_identity_is_not_a_developer_id
    result = developer_id("  1) #{"D" * 40} \"Apple Distribution: Michal  Fousek (3VN358756R)\"\n")

    refute_predicate result, :ok?
    assert_nil result.identity
  end

  # A line with anything after the closing quote, such as a certificate-status
  # note, is not an identity to sign with.
  def test_a_listing_with_a_trailing_status_is_not_usable
    revoked = "  1) #{"C" * 40} \"#{NAME}\" (CSSMERR_TP_CERT_REVOKED)\n"

    refute_predicate developer_id(revoked), :ok?
  end
end
