# frozen_string_literal: true

require "openssl"
require "rexml/document"

module InvoicesTracker
  # What a release needs from Sparkle, the framework that updates the app: where
  # its command-line tools are, the command that writes the update feed (the
  # appcast), the public half of the key the feed is signed with, the newest
  # build a feed offers, and what is wrong with a feed that is about to be
  # published. Pure apart from the key derivation, which OpenSSL does: callers
  # run the commands and pass in the key and the text of the feed.
  module Sparkle
    # The length in bytes of the seed an Ed25519 private key is made from.
    SEED_BYTES = 32

    # The comment `generate_appcast` adds after the closing tag of a feed it
    # signs, as it reads once parsed: `sparkle-signatures:` and then a line
    # `edSignature:` with the signature in base64. A comment that has no
    # signature does not match.
    FEED_SIGNATURE = %r{\A\s*sparkle-signatures:\s*edSignature:[ \t]*[A-Za-z0-9+/=]+}

    module_function

    # The folder with Sparkle's command-line tools, such as `generate_appcast`,
    # inside the DerivedData folder of a build. Swift Package Manager unpacks
    # Sparkle's binary archive under `SourcePackages/artifacts`, with `bin/` next
    # to the framework, so the tools are the version the app is built with.
    def tools_dir(derived_data:)
      File.join(derived_data, "SourcePackages", "artifacts", "sparkle", "Sparkle", "bin")
    end

    # The `generate_appcast` command that writes the update feed for the
    # archives in `archives_dir` to `output`, as an array to run without a shell.
    # The feed offers one update, the newest archive, with no delta updates, and
    # carries the release notes found next to it, in the file named like the
    # archive with `.md` in place of the extension. The archive downloads from
    # `download_url_prefix` followed by its file name, and `link` is the address
    # of the app's page that the feed names. The private key is read from
    # standard input (the `-` after `--ed-key-file`), so it is on no command line
    # and in no file.
    def generate_appcast_command(tools_dir:, archives_dir:, download_url_prefix:, link:, output:)
      [
        File.join(tools_dir, "generate_appcast"),
        "--ed-key-file", "-",
        "--download-url-prefix", download_url_prefix,
        "--embed-release-notes",
        "--maximum-deltas", "0",
        "--maximum-versions", "1",
        "--link", link,
        "-o", output,
        archives_dir
      ]
    end

    # The `SUPublicEDKey` of a private key: the base64 of the 32-byte Ed25519
    # public key. The private key is in the form Sparkle's `generate_keys -x`
    # writes, the base64 of the 32-byte seed, and whitespace around it is
    # ignored. Raises ArgumentError for anything else. The message never
    # contains the key, which is a secret that must stay out of a log.
    def public_key_for(private_key_b64)
      seed = decode_seed(private_key_b64)
      [OpenSSL::PKey.new_raw_private_key("ED25519", seed).raw_public_key].pack("m0")
    end

    # The largest build, as a number, that the updates of a feed offer: the
    # `sparkle:version` of an update, which is what Sparkle compares to tell a
    # newer one. Nil when the feed offers no update with a numeric build, or does
    # not parse as XML.
    def latest_build(appcast_xml)
      document = parse(appcast_xml)
      return unless document

      REXML::XPath.match(document, "//item")
                  .filter_map { |item| Integer(item_field(item, "sparkle:version").to_s.strip, 10, exception: false) }
                  .max
    end

    # Why a feed that `generate_appcast` has just written must not be published,
    # one sentence each, in the order of the checks; empty when it may be. The
    # feed must offer exactly one update, the release being published: its
    # archive at `archive_url`, as `version` and `build`, with an EdDSA signature
    # and release notes. The feed must be signed itself. The archive signature is
    # checked because `generate_appcast` leaves an archive unsigned, with only a
    # warning and a success status, when the app's `SUPublicEDKey` is missing or
    # does not match the key. A feed that does not parse as XML, or that does not
    # list exactly one update, has only that problem: there is nothing further to
    # check.
    def feed_problems(appcast_xml, archive_url:, version:, build:)
      document = parse(appcast_xml)
      return ["it does not parse as XML"] unless document

      items = REXML::XPath.match(document, "//item")
      return ["it lists #{items.size} updates instead of exactly the new one"] unless items.size == 1

      item = items.first
      address = enclosure_attribute(item, "url").to_s
      offered_build = item_field(item, "sparkle:version").to_s.strip
      offered_version = item_field(item, "sparkle:shortVersionString").to_s.strip

      problems = []
      unless address == archive_url
        problems << "its archive downloads from #{shown(address, '(nowhere)')}, not #{archive_url}"
      end
      problems << "it offers build #{shown(offered_build, '(none)')}, not #{build}" unless offered_build == build.to_s
      unless offered_version == version.to_s
        problems << "it offers version #{shown(offered_version, '(none)')}, not #{version}"
      end
      if enclosure_attribute(item, "sparkle:edSignature").to_s.empty?
        problems << "its archive has no EdDSA signature — does the app's SUPublicEDKey match the key?"
      end
      problems << "the feed is not signed, and the app requires a signed feed" unless signed?(document)
      problems << "it has no release notes" if release_notes(item).strip.empty?
      problems
    end

    # The seed inside a base64 private key. Raises ArgumentError, with a message
    # that does not quote the key, when the text is not base64 or does not decode
    # to a seed's length.
    def decode_seed(private_key_b64)
      seed = begin
        private_key_b64.to_s.strip.unpack1("m0")
      rescue ArgumentError
        raise ArgumentError, "the Sparkle private key is not valid base64"
      end
      return seed if seed.bytesize == SEED_BYTES

      raise ArgumentError, "the Sparkle private key decodes to #{seed.bytesize} bytes, not #{SEED_BYTES}"
    end
    private_class_method :decode_seed

    # The feed as an XML document, read as UTF-8 whatever its string is labelled
    # with: a CI runner's locale may not be UTF-8, and release notes are seldom
    # ASCII. Nil when the text does not parse.
    def parse(appcast_xml)
      REXML::Document.new(appcast_xml.to_s.dup.force_encoding(Encoding::UTF_8))
    rescue REXML::ParseException
      nil
    end
    private_class_method :parse

    # The text of a field of an update, such as `sparkle:version`: that of the
    # child element of the update, else the value of the attribute of the same
    # name on its enclosure, where older feeds keep it. Nil when it has neither.
    def item_field(item, name)
      element = item.elements[name]
      element ? element.text : enclosure_attribute(item, name)
    end
    private_class_method :item_field

    # The value of an attribute of the `enclosure` of an update, which describes
    # the archive. Nil when the update has no enclosure or the enclosure lacks
    # the attribute.
    def enclosure_attribute(item, name)
      enclosure = item.elements["enclosure"]
      enclosure.attributes[name] if enclosure
    end
    private_class_method :enclosure_attribute

    # The release notes an update embeds: the text of its own `description`,
    # which is not the description of the channel around it. Empty when it has
    # none.
    def release_notes(item)
      description = item.elements["description"]
      description ? description.texts.map(&:value).join : ""
    end
    private_class_method :release_notes

    # Whether the feed carries the signature comment that `generate_appcast`
    # adds. Only a comment of the document itself counts, not text inside the
    # release notes that looks like one.
    def signed?(document)
      document.children.grep(REXML::Comment).any? { |comment| comment.string.match?(FEED_SIGNATURE) }
    end
    private_class_method :signed?

    # `value` as it reads in a message, or `placeholder` when it is empty.
    def shown(value, placeholder)
      value.empty? ? placeholder : value
    end
    private_class_method :shown
  end
end
