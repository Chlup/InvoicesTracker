# frozen_string_literal: true

require "openssl"

module InvoicesTracker
  # The temporary keychain a CI build signs with. On a GitHub-hosted runner the
  # Developer ID certificate arrives as a .p12 file and its password, both from
  # secrets, and `security import` takes that password only as an argument. So
  # the file is first encrypted again under a throwaway password, and only the
  # throwaway password reaches a command line. The commands that make the
  # keychain, fill it and remove it are built here as arrays to run without a
  # shell. Pure apart from the OpenSSL work of encrypting the file again, which
  # may load OpenSSL's legacy provider into the process: callers run the
  # commands.
  module CiKeychain
    # The OpenSSL name of the password-based encryption that the file made by
    # `rewrap_p12` uses for its key and for its certificate:
    # pbeWithSHA1And3-KeyTripleDES-CBC. Without it OpenSSL 3 writes PBES2 with
    # AES-256, which macOS reads only from macOS 15 on.
    PKCS12_ENCRYPTION = "PBE-SHA1-3DES"

    # The friendly name that `rewrap_p12` stores in the file for the identity. It
    # is only a label: no code looks an identity up by it.
    FRIENDLY_NAME = "Developer ID"

    # How long the keychain stays unlocked, in seconds: six hours, long enough
    # that it does not lock during a release job.
    LOCK_TIMEOUT_SECONDS = 21_600

    # The tools that may use the imported key without a prompt.
    TRUSTED_TOOLS = ["/usr/bin/codesign", "/usr/bin/security"].freeze

    # The partition list that lets `codesign` and Apple's other tools use the
    # imported key without a prompt, as `security set-key-partition-list` takes
    # it.
    PARTITION_LIST = "apple-tool:,apple:,codesign:"

    # One keychain in the output of `security list-keychains`: its path in double
    # quotes, on a line of its own and indented.
    LISTED_KEYCHAIN = /\A\s*"(.+)"\s*\z/

    # What OpenSSL reports when the integrity check of a .p12 file fails, which
    # is what a wrong password does: the check comes before anything is decrypted.
    MAC_FAILURE = /mac verify failure/i

    # What OpenSSL 3 reports when a .p12 file uses an algorithm that no provider
    # loaded so far implements. RC2, in which LibreSSL encrypts the certificate of
    # a file, belongs to the legacy provider, which is not loaded by default.
    UNSUPPORTED = /unsupported/i

    # The message of the ArgumentError that `rewrap_p12` raises for a wrong
    # password, and only for that.
    WRONG_PASSWORD_MESSAGE = "the Developer ID .p12 cannot be opened with DEVELOPER_ID_P12_PASSWORD"

    # The message for a file with an encryption that OpenSSL cannot read, even
    # with the legacy provider.
    UNREADABLE_ENCRYPTION_MESSAGE = "the Developer ID .p12 uses an encryption this Ruby's OpenSSL cannot read — " \
                                    "export it again from Keychain Access"

    # The message for data that is no .p12 file, or a damaged one.
    DAMAGED_MESSAGE = "the Developer ID .p12 in DEVELOPER_ID_P12 is damaged or is not a .p12 file"

    module_function

    # The .p12 file `p12_der` (DER bytes), opened with `password` and encrypted
    # again under `new_password`, as DER bytes. The key, the certificate and any
    # other certificates of the file are kept. The key and the certificate use
    # the encryption `PKCS12_ENCRYPTION` names. The file's integrity check stays
    # HMAC-SHA-256, which Ruby's OpenSSL gives no way to change and which macOS
    # releases before 15 may not read.
    #
    # A file written the old way, as LibreSSL writes it, has its certificate
    # encrypted with RC2, which OpenSSL 3 reads only through its legacy provider.
    # When a file fails for that reason, the legacy provider is loaded into the
    # process, where it stays, and the file is read once more.
    #
    # Raises ArgumentError when the file cannot be opened. No message contains a
    # password, and each says what is wrong: `WRONG_PASSWORD_MESSAGE` for a wrong
    # password, and only for that, `UNREADABLE_ENCRYPTION_MESSAGE` for an
    # encryption that this OpenSSL cannot read even with its legacy provider (or
    # that has no legacy provider), and `DAMAGED_MESSAGE` for data that is no
    # .p12 file at all.
    def rewrap_p12(p12_der, password:, new_password:)
      opened = open_p12(p12_der, password)
      OpenSSL::PKCS12.create(new_password, FRIENDLY_NAME, opened.key, opened.certificate, opened.ca_certs,
                             PKCS12_ENCRYPTION, PKCS12_ENCRYPTION).to_der
    end

    # The `security` commands that make the keychain at `keychain`, protected by
    # `keychain_password`, and import the identity of the .p12 file at
    # `p12_path` into it. They let `codesign` use the key without a prompt and
    # put the keychain first in the user's search list, ahead of `search_list`,
    # the keychains the list holds now, as `parse_search_list` reads them from
    # `security list-keychains -d user`. `p12_password` is the throwaway password
    # of the file `rewrap_p12` made, never the real one: `security import` takes
    # it as an argument. Each command is an array to run without a shell.
    def setup_commands(keychain:, keychain_password:, p12_path:, p12_password:, search_list:)
      [
        ["security", "create-keychain", "-p", keychain_password, keychain],
        ["security", "set-keychain-settings", "-lut", LOCK_TIMEOUT_SECONDS.to_s, keychain],
        ["security", "unlock-keychain", "-p", keychain_password, keychain],
        ["security", "import", p12_path, "-k", keychain, "-f", "pkcs12", "-P", p12_password,
         *TRUSTED_TOOLS.flat_map { |tool| ["-T", tool] }],
        ["security", "set-key-partition-list", "-S", PARTITION_LIST, "-s", "-k", keychain_password, keychain],
        ["security", "list-keychains", "-d", "user", "-s", keychain, *search_list]
      ]
    end

    # The `security` commands that undo `setup_commands`: they put the user's
    # search list back to `search_list`, the keychains it held before, and then
    # delete the keychain at `keychain` with the identity in it. Each command is
    # an array to run without a shell.
    def teardown_commands(keychain:, search_list:)
      [
        ["security", "list-keychains", "-d", "user", "-s", *search_list],
        ["security", "delete-keychain", keychain]
      ]
    end

    # The keychains in the output of `security list-keychains -d user`, in
    # order: each is a path in double quotes on a line of its own. A line that
    # is no quoted path, such as an empty one, is skipped. The listing has to be
    # the one of the user's domain: `setup_commands` and `teardown_commands`
    # write the list back to that domain, and the plain listing also holds the
    # system keychain, which does not belong there.
    def parse_search_list(list_keychains_output)
      list_keychains_output.to_s.each_line.filter_map { |line| line[LISTED_KEYCHAIN, 1] }
    end

    # The .p12 file opened with `password`. A file that fails because OpenSSL has
    # no implementation of an algorithm it uses is read once more after the
    # legacy provider has been loaded, if this OpenSSL has one. Raises
    # ArgumentError, with a message that quotes no password, when it cannot be
    # opened: see `failure_message`.
    def open_p12(p12_der, password)
      legacy_loaded = false
      begin
        OpenSSL::PKCS12.new(p12_der, password)
      rescue OpenSSL::PKCS12::PKCS12Error => error
        if !legacy_loaded && UNSUPPORTED.match?(error.message) && load_legacy_provider
          legacy_loaded = true
          retry
        end
        raise ArgumentError, failure_message(error)
      end
    end
    private_class_method :open_p12

    # Loads the default and the legacy provider of OpenSSL 3 into this process,
    # which makes RC2 and the other old algorithms available to every OpenSSL
    # call after it. The default provider is loaded as well because OpenSSL loads
    # it on its own only while no provider has been loaded by name. Loading a
    # provider that is loaded already does no harm. Gives true when both are
    # loaded, and false when this OpenSSL has no providers (it is older than 3)
    # or has no legacy provider.
    def load_legacy_provider
      return false unless defined?(OpenSSL::Provider)

      OpenSSL::Provider.load("default")
      OpenSSL::Provider.load("legacy")
      true
    rescue OpenSSL::Provider::ProviderError
      false
    end
    private_class_method :load_legacy_provider

    # The message of the ArgumentError for a .p12 file that OpenSSL failed to open
    # with `error`. A failed integrity check, which is what a wrong password
    # causes, gives `WRONG_PASSWORD_MESSAGE`; an algorithm without an
    # implementation gives `UNREADABLE_ENCRYPTION_MESSAGE`; anything else gives
    # `DAMAGED_MESSAGE`.
    def failure_message(error)
      case error.message
      when MAC_FAILURE then WRONG_PASSWORD_MESSAGE
      when UNSUPPORTED then UNREADABLE_ENCRYPTION_MESSAGE
      else DAMAGED_MESSAGE
      end
    end
    private_class_method :failure_message
  end
end
