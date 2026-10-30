# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "openssl"
require "rbconfig"
require "invoices_tracker/ci_keychain"

class InvoicesTrackerCiKeychainTest < Minitest::Test
  # A password with every kind of character a shell treats specially, so a helper
  # that put it into a command line as text would break on it.
  PASSWORD = %q(pa'ss "w" $x)

  # pbeWithSHA1And3-KeyTripleDES-CBC, the encryption that `PBE-SHA1-3DES` names.
  TRIPLE_DES = "1.2.840.113549.1.12.1.3"

  # PBES2, the encryption OpenSSL 3 uses unless it is told otherwise.
  PBES2 = "1.2.840.113549.1.5.13"

  # pbeWithSHA1And40BitRC2-CBC, the encryption of a certificate in a file written
  # the old way. OpenSSL 3 reads it only through its legacy provider.
  RC2_40 = "1.2.840.113549.1.12.1.6"

  # A .p12 file written the old way, as LibreSSL writes it: the certificate
  # encrypted with RC2-40, the key with 3DES, a SHA-1 integrity check. Made once,
  # from a throwaway key and certificate (not a real one), with /usr/bin/openssl:
  #
  #   openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem \
  #     -days 36500 -subj "/CN=Legacy Encryption Fixture"
  #   openssl pkcs12 -export -inkey key.pem -in cert.pem -name "Legacy Encryption Fixture" \
  #     -passout pass:<LEGACY_PASSWORD> -out legacy.p12
  #
  # It is a fixture because a test cannot make such a file without loading the
  # legacy provider, which is what the code under test has to do on its own.
  LEGACY_P12 = File.read(File.join(__dir__, "fixtures", "legacy_encryption.p12.base64")).unpack1("m")
  LEGACY_PASSWORD = %q(legacy 'pw' "1")

  # The file that defines the helper, as these tests loaded it, so that a Ruby
  # which a test starts runs the very code under test.
  HELPER_FILE = InvoicesTracker::CiKeychain.method(:rewrap_p12).source_location.first

  # What `rewrap_p12` says of a file that uses an encryption it cannot read.
  UNREADABLE_ENCRYPTION = "the Developer ID .p12 uses an encryption this Ruby's OpenSSL cannot read — " \
                          "export it again from Keychain Access"

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

  def test_rewrap_p12_rejects_data_that_is_not_a_p12_without_blaming_the_password
    error = assert_raises(ArgumentError) do
      InvoicesTracker::CiKeychain.rewrap_p12("not a p12 file", password: PASSWORD, new_password: "throwaway")
    end

    assert_equal "the Developer ID .p12 in DEVELOPER_ID_P12 is damaged or is not a .p12 file", error.message
  end

  def test_the_legacy_fixture_encrypts_its_certificate_with_rc2
    assert_equal 1, LEGACY_P12.scan(object_id_der(RC2_40)).size
    refute_includes LEGACY_P12, object_id_der(PBES2)
  end

  def test_rewrap_p12_opens_a_file_whose_certificate_is_encrypted_with_rc2
    rewrapped = InvoicesTracker::CiKeychain.rewrap_p12(LEGACY_P12, password: LEGACY_PASSWORD, new_password: "throwaway")
    opened = OpenSSL::PKCS12.new(rewrapped, "throwaway")

    assert_equal "/CN=Legacy Encryption Fixture", opened.certificate.subject.to_s
    assert_equal 14_797_446_449_193_623_025, opened.certificate.serial.to_i
    assert opened.certificate.check_private_key(opened.key), "the key is the key of the certificate"
    assert_equal 2, rewrapped.scan(object_id_der(TRIPLE_DES)).size
  end

  def test_rewrap_p12_still_reports_a_wrong_password_for_a_file_with_rc2_as_a_wrong_password
    error = assert_raises(ArgumentError) do
      InvoicesTracker::CiKeychain.rewrap_p12(LEGACY_P12, password: "not the password", new_password: "throwaway")
    end

    assert_equal "the Developer ID .p12 cannot be opened with DEVELOPER_ID_P12_PASSWORD", error.message
  end

  def test_rewrap_p12_says_the_encryption_is_unreadable_when_this_openssl_has_no_providers
    output = rewrap_the_legacy_fixture_in_a_new_ruby("OpenSSL.send(:remove_const, :Provider)")

    assert_equal UNREADABLE_ENCRYPTION, output
  end

  def test_rewrap_p12_says_the_encryption_is_unreadable_when_the_legacy_provider_cannot_be_loaded
    output = rewrap_the_legacy_fixture_in_a_new_ruby(<<~'RUBY')
      OpenSSL::Provider.singleton_class.prepend(Module.new do
        def load(name)
          raise OpenSSL::Provider::ProviderError, "Failed to load #{name} provider" if name == "legacy"

          super
        end
      end)
    RUBY

    assert_equal UNREADABLE_ENCRYPTION, output
  end

  def test_rewrap_p12_reads_a_file_at_most_twice_when_the_legacy_provider_does_not_help
    output = rewrap_the_legacy_fixture_in_a_new_ruby(<<~'RUBY')
      reads = 0
      at_exit { puts "read #{reads} times" }
      OpenSSL::Provider.singleton_class.prepend(Module.new { def load(_name) = nil })
      OpenSSL::PKCS12.singleton_class.prepend(Module.new do
        define_method(:new) do |*arguments|
          raise "read more than twice" if (reads += 1) > 2

          super(*arguments)
        end
      end)
    RUBY

    assert_equal "#{UNREADABLE_ENCRYPTION}\nread 2 times", output
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

  # What `rewrap_p12` makes of the legacy fixture, with the right password, in a
  # new Ruby where the Ruby code `setup` has run first: the message of the
  # ArgumentError it raises, or "rewrapped". A new Ruby is needed because a
  # provider that one test loads stays loaded for every test after it. It starts
  # without Bundler, which it does not need and which takes long to load.
  def rewrap_the_legacy_fixture_in_a_new_ruby(setup)
    script = <<~'RUBY'
      begin
        InvoicesTracker::CiKeychain.rewrap_p12($stdin.binmode.read, password: ARGV.fetch(0), new_password: "x")
        puts "rewrapped"
      rescue ArgumentError => e
        puts e.message
      end
    RUBY
    output, errors, status = Open3.capture3({ "RUBYOPT" => nil, "RUBYLIB" => nil }, RbConfig.ruby, "-r", "openssl",
                                            "-r", HELPER_FILE, "-e", "#{setup}\n#{script}", LEGACY_PASSWORD,
                                            stdin_data: LEGACY_P12, binmode: true)
    assert status.success?, errors
    output.force_encoding(Encoding::UTF_8).strip
  end
end
