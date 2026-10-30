# frozen_string_literal: true

require "minitest/autorun"
require "openssl"
require "invoices_tracker/ci_keychain"

class InvoicesTrackerCiKeychainTest < Minitest::Test
  # A password with every kind of character a shell treats specially, so a helper
  # that put it into a command line as text would break on it.
  PASSWORD = %q(pa'ss "w" $x)

  # pbeWithSHA1And3-KeyTripleDES-CBC, the encryption that `PBE-SHA1-3DES` names.
  TRIPLE_DES = "1.2.840.113549.1.12.1.3"

  # PBES2, the encryption OpenSSL 3 uses unless it is told otherwise.
  PBES2 = "1.2.840.113549.1.5.13"

  def test_rewrap_p12_opens_with_the_new_password_and_keeps_the_key_and_the_certificate
    key, certificate = self_signed_identity("Test Developer ID", serial: 4242)
    original = OpenSSL::PKCS12.create(PASSWORD, "id", key, certificate).to_der

    rewrapped = InvoicesTracker::CiKeychain.rewrap_p12(original, password: PASSWORD, new_password: "throwaway")
    opened = OpenSSL::PKCS12.new(rewrapped, "throwaway")

    assert_equal 4242, opened.certificate.serial.to_i
    assert_equal certificate.to_der, opened.certificate.to_der
    assert_equal key.to_der, opened.key.to_der
  end

  def test_rewrap_p12_no_longer_opens_with_the_old_password
    key, certificate = self_signed_identity("Test Developer ID")
    original = OpenSSL::PKCS12.create(PASSWORD, "id", key, certificate).to_der

    rewrapped = InvoicesTracker::CiKeychain.rewrap_p12(original, password: PASSWORD, new_password: "throwaway")

    assert_raises(OpenSSL::PKCS12::PKCS12Error) { OpenSSL::PKCS12.new(rewrapped, PASSWORD) }
  end

  def test_rewrap_p12_encrypts_the_key_and_the_certificate_with_triple_des_and_not_with_pbes2
    key, certificate = self_signed_identity("Test Developer ID")
    original = OpenSSL::PKCS12.create(PASSWORD, "id", key, certificate).to_der

    rewrapped = InvoicesTracker::CiKeychain.rewrap_p12(original, password: PASSWORD, new_password: "throwaway")

    assert_equal 2, rewrapped.scan(object_id_der(TRIPLE_DES)).size
    refute_includes rewrapped, object_id_der(PBES2)
  end

  def test_rewrap_p12_keeps_the_other_certificates_of_the_file
    key, certificate = self_signed_identity("Test Developer ID")
    _, issuer = self_signed_identity("Test Certification Authority", serial: 1)
    original = OpenSSL::PKCS12.create(PASSWORD, "id", key, certificate, [issuer]).to_der

    rewrapped = InvoicesTracker::CiKeychain.rewrap_p12(original, password: PASSWORD, new_password: "throwaway")

    assert_equal [issuer.to_der], Array(OpenSSL::PKCS12.new(rewrapped, "throwaway").ca_certs).map(&:to_der)
  end

  def test_rewrap_p12_rejects_a_wrong_password_without_quoting_any_password
    key, certificate = self_signed_identity("Test Developer ID")
    original = OpenSSL::PKCS12.create(PASSWORD, "id", key, certificate).to_der

    error = assert_raises(ArgumentError) do
      InvoicesTracker::CiKeychain.rewrap_p12(original, password: "not the password", new_password: "throwaway")
    end

    assert_equal "the Developer ID .p12 cannot be opened with DEVELOPER_ID_P12_PASSWORD", error.message
    [PASSWORD, "not the password", "throwaway"].each do |password|
      refute_includes error.message, password
      refute_includes error.cause.to_s, password
    end
  end

  def test_rewrap_p12_rejects_data_that_is_not_a_p12_with_the_same_message
    error = assert_raises(ArgumentError) do
      InvoicesTracker::CiKeychain.rewrap_p12("not a p12 file", password: PASSWORD, new_password: "throwaway")
    end

    assert_equal "the Developer ID .p12 cannot be opened with DEVELOPER_ID_P12_PASSWORD", error.message
  end

  def test_setup_commands_make_a_keychain_that_codesign_may_use_and_put_it_first_in_the_search_list
    assert_equal [
      ["security", "create-keychain", "-p", "kpw", "/t/ci.keychain-db"],
      ["security", "set-keychain-settings", "-lut", "21600", "/t/ci.keychain-db"],
      ["security", "unlock-keychain", "-p", "kpw", "/t/ci.keychain-db"],
      ["security", "import", "/t/id.p12", "-k", "/t/ci.keychain-db", "-f", "pkcs12", "-P", "throwaway",
       "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"],
      ["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", "kpw",
       "/t/ci.keychain-db"],
      ["security", "list-keychains", "-d", "user", "-s", "/t/ci.keychain-db", "/u/login.keychain-db"]
    ], InvoicesTracker::CiKeychain.setup_commands(keychain: "/t/ci.keychain-db", keychain_password: "kpw",
                                                  p12_path: "/t/id.p12", p12_password: "throwaway",
                                                  search_list: ["/u/login.keychain-db"])
  end

  def test_setup_commands_keep_every_keychain_of_the_search_list_in_order_behind_the_new_one
    commands = InvoicesTracker::CiKeychain.setup_commands(
      keychain: "/t/ci.keychain-db", keychain_password: "kpw", p12_path: "/t/id.p12", p12_password: "throwaway",
      search_list: ["/u/a b.keychain-db", "/Library/Keychains/System.keychain"]
    )

    assert_equal ["security", "list-keychains", "-d", "user", "-s", "/t/ci.keychain-db", "/u/a b.keychain-db",
                  "/Library/Keychains/System.keychain"],
                 commands.last
  end

  def test_teardown_commands_restore_the_search_list_and_then_delete_the_keychain
    assert_equal [["security", "list-keychains", "-d", "user", "-s", "/u/login.keychain-db"],
                  ["security", "delete-keychain", "/t/ci.keychain-db"]],
                 InvoicesTracker::CiKeychain.teardown_commands(keychain: "/t/ci.keychain-db",
                                                               search_list: ["/u/login.keychain-db"])
  end

  def test_parse_search_list_reads_the_quoted_paths_of_list_keychains
    assert_equal ["/Users/r/Library/Keychains/login.keychain-db", "/Library/Keychains/System.keychain"],
                 InvoicesTracker::CiKeychain.parse_search_list(
                   "    \"/Users/r/Library/Keychains/login.keychain-db\"\n    \"/Library/Keychains/System.keychain\"\n"
                 )
  end

  def test_parse_search_list_keeps_the_spaces_inside_a_path
    assert_equal ["/Users/r/My Keychains/a b.keychain-db"],
                 InvoicesTracker::CiKeychain.parse_search_list("    \"/Users/r/My Keychains/a b.keychain-db\"\n")
  end

  def test_parse_search_list_skips_lines_that_are_not_a_quoted_path
    assert_equal ["/u/login.keychain-db"],
                 InvoicesTracker::CiKeychain.parse_search_list("\n  \"/u/login.keychain-db\"  \nsecurity: a note\n\n")
  end

  def test_parse_search_list_is_empty_for_an_empty_list
    assert_empty InvoicesTracker::CiKeychain.parse_search_list("")
    assert_empty InvoicesTracker::CiKeychain.parse_search_list(nil)
  end

  private

  # A throwaway RSA key and the self-signed certificate of it, the shape of the
  # identity inside a .p12.
  def self_signed_identity(common_name, serial: 1)
    key = OpenSSL::PKey::RSA.new(2048)
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = serial
    certificate.subject = certificate.issuer = OpenSSL::X509::Name.parse("/CN=#{common_name}")
    certificate.public_key = key.public_key
    certificate.not_before = Time.now - 60
    certificate.not_after = Time.now + 3600
    certificate.sign(key, "SHA256")
    [key, certificate]
  end

  # The DER encoding of an object identifier, which is how an algorithm is named
  # inside a .p12.
  def object_id_der(oid)
    OpenSSL::ASN1::ObjectId.new(oid).to_der
  end
end
