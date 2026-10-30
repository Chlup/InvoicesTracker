# frozen_string_literal: true

require "minitest/autorun"
require "invoices_tracker/sparkle"

class InvoicesTrackerSparkleTest < Minitest::Test
  # A feed as `generate_appcast` writes it: one update, build 10 of version
  # 1.7.0, with an archive signature and release notes, and the signature of the
  # feed after the closing tag. Its channel has a description of its own, like a
  # real feed. The tests make their variants by replacing parts of its text.
  FIXTURE = File.read(File.join(__dir__, "fixtures", "appcast.xml"), encoding: Encoding::UTF_8)

  ITEM = FIXTURE[%r{<item>.*?</item>}m]
  ARCHIVE = "https://github.com/Chlup/InvoicesTracker/releases/download/v1.7.0-10/InvoicesTracker-1.7.0-10.dmg"
  BUILD = "<sparkle:version>10</sparkle:version>"
  VERSION = "<sparkle:shortVersionString>1.7.0</sparkle:shortVersionString>"
  NOTES = '<description sparkle:format="markdown"><![CDATA[- Oprava]]></description>'
  ARCHIVE_SIGNATURE = 'sparkle:edSignature="c2ln"'
  SIGNATURE_COMMENT = "<!-- sparkle-signatures:\nedSignature: c2ln\nlength: 1\n-->"

  # RFC 8032, section 7.1, test 1: a seed and the public key that belongs to it.
  SEED = ["9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"].pack("H*")
  PUBLIC_KEY = ["d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"].pack("H*")

  def test_tools_dir_is_the_bin_folder_of_the_sparkle_package_in_derived_data
    assert_equal "/r/build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin",
                 InvoicesTracker::Sparkle.tools_dir(derived_data: "/r/build/DerivedData")
  end

  def test_generate_appcast_command_takes_the_key_on_stdin_and_offers_one_update_without_deltas
    assert_equal ["/t/generate_appcast", "--ed-key-file", "-", "--download-url-prefix", "https://p/",
                  "--embed-release-notes", "--maximum-deltas", "0", "--maximum-versions", "1",
                  "--link", "https://l", "-o", "/o/appcast.xml", "/a"],
                 InvoicesTracker::Sparkle.generate_appcast_command(
                   tools_dir: "/t", archives_dir: "/a", download_url_prefix: "https://p/", link: "https://l",
                   output: "/o/appcast.xml"
                 )
  end

  def test_public_key_for_derives_the_public_key_of_a_seed
    assert_equal [PUBLIC_KEY].pack("m0"), InvoicesTracker::Sparkle.public_key_for([SEED].pack("m0"))
  end

  def test_public_key_for_ignores_whitespace_around_the_key
    assert_equal [PUBLIC_KEY].pack("m0"), InvoicesTracker::Sparkle.public_key_for(" #{[SEED].pack('m0')}\n")
  end

  def test_public_key_for_rejects_a_key_of_the_wrong_length_without_quoting_it
    error = assert_raises(ArgumentError) { InvoicesTracker::Sparkle.public_key_for("c2hvcnQ=") }

    refute_includes error.message, "c2hvcnQ="
  end

  def test_public_key_for_rejects_text_that_is_not_base64_without_quoting_it
    key = "hunter2 is not base64!"
    error = assert_raises(ArgumentError) { InvoicesTracker::Sparkle.public_key_for(key) }

    refute_includes error.message, "hunter2"
    refute_includes error.message, key
  end

  def test_public_key_for_rejects_a_key_that_is_missing
    assert_raises(ArgumentError) { InvoicesTracker::Sparkle.public_key_for(nil) }
    assert_raises(ArgumentError) { InvoicesTracker::Sparkle.public_key_for(" \n") }
  end

  def test_latest_build_is_the_build_of_the_update
    assert_equal 10, InvoicesTracker::Sparkle.latest_build(FIXTURE)
  end

  def test_latest_build_is_the_largest_build_compared_as_a_number
    older = ITEM.sub(BUILD, "<sparkle:version>9</sparkle:version>")
    oldest = ITEM.sub(BUILD, "<sparkle:version>2</sparkle:version>")

    assert_equal 10, InvoicesTracker::Sparkle.latest_build(fixture_with(ITEM => ITEM + older + oldest))
  end

  def test_latest_build_reads_the_legacy_attribute_of_the_enclosure
    feed = fixture_with(BUILD => "", 'length="1"' => 'length="1" sparkle:version="12"')

    assert_equal 12, InvoicesTracker::Sparkle.latest_build(feed)
  end

  def test_latest_build_reads_a_build_with_a_leading_zero_as_a_decimal_number
    feed = fixture_with(BUILD => "<sparkle:version>010</sparkle:version>")

    assert_equal 10, InvoicesTracker::Sparkle.latest_build(feed)
  end

  def test_latest_build_is_nil_when_the_feed_offers_no_update
    assert_nil InvoicesTracker::Sparkle.latest_build("<rss/>")
    assert_nil InvoicesTracker::Sparkle.latest_build("")
  end

  def test_latest_build_is_nil_when_the_update_has_no_numeric_build
    assert_nil InvoicesTracker::Sparkle.latest_build(fixture_with(BUILD => ""))
    assert_nil InvoicesTracker::Sparkle.latest_build(fixture_with(BUILD => "<sparkle:version>ten</sparkle:version>"))
  end

  def test_latest_build_is_nil_when_the_feed_does_not_parse
    assert_nil InvoicesTracker::Sparkle.latest_build("<rss")
  end

  def test_a_feed_that_offers_exactly_the_new_release_has_no_problems
    assert_equal [], problems(FIXTURE)
  end

  def test_the_build_may_be_given_as_a_number
    assert_equal [], problems(FIXTURE, build: 10)
  end

  def test_the_build_may_be_the_legacy_attribute_of_the_enclosure
    feed = fixture_with(BUILD => "", 'length="1"' => 'length="1" sparkle:version="10"')

    assert_equal [], problems(feed)
  end

  def test_two_updates_are_a_problem
    assert_equal ["it lists 2 updates instead of exactly the new one"], problems(fixture_with(ITEM => ITEM * 2))
  end

  def test_no_update_is_a_problem
    assert_equal ["it lists 0 updates instead of exactly the new one"], problems("<rss/>")
  end

  def test_another_archive_address_is_a_problem
    other = "https://example.com/InvoicesTracker-1.6.0-9.dmg"

    assert_equal ["its archive downloads from #{other}, not #{ARCHIVE}"], problems(fixture_with(ARCHIVE => other))
  end

  def test_another_build_is_a_problem
    feed = fixture_with(BUILD => "<sparkle:version>9</sparkle:version>")

    assert_equal ["it offers build 9, not 10"], problems(feed)
  end

  def test_a_missing_build_is_a_problem
    assert_equal ["it offers build (none), not 10"], problems(fixture_with(BUILD => ""))
  end

  def test_another_version_is_a_problem
    feed = fixture_with(VERSION => "<sparkle:shortVersionString>1.6.0</sparkle:shortVersionString>")

    assert_equal ["it offers version 1.6.0, not 1.7.0"], problems(feed)
  end

  def test_an_archive_without_an_eddsa_signature_is_a_problem
    feed = fixture_with(ARCHIVE_SIGNATURE => 'sparkle:edSignature=""')

    assert_equal ["its archive has no EdDSA signature — does the app's SUPublicEDKey match the key?"], problems(feed)
  end

  def test_an_update_without_an_archive_is_a_problem_of_address_and_signature
    feed = fixture_with(FIXTURE[%r{<enclosure .*?/>}] => "")

    assert_equal ["its archive downloads from (nowhere), not #{ARCHIVE}",
                  "its archive has no EdDSA signature — does the app's SUPublicEDKey match the key?"],
                 problems(feed)
  end

  def test_a_feed_without_the_signature_comment_is_a_problem
    assert_equal ["the feed is not signed, and the app requires a signed feed"],
                 problems(fixture_with(SIGNATURE_COMMENT => ""))
  end

  def test_a_signature_comment_without_a_signature_does_not_sign_the_feed
    feed = fixture_with("edSignature: c2ln\nlength" => "edSignature: \nlength")

    assert_equal ["the feed is not signed, and the app requires a signed feed"], problems(feed)
  end

  def test_a_signature_comment_in_the_release_notes_does_not_sign_the_feed
    feed = fixture_with(SIGNATURE_COMMENT => "", "- Oprava" => "- Oprava\n#{SIGNATURE_COMMENT}")

    assert_equal ["the feed is not signed, and the app requires a signed feed"], problems(feed)
  end

  def test_a_missing_description_is_a_problem_although_the_channel_has_one
    assert_equal ["it has no release notes"], problems(fixture_with(NOTES => ""))
  end

  def test_an_empty_description_is_a_problem
    feed = fixture_with(NOTES => '<description sparkle:format="markdown"><![CDATA[]]></description>')

    assert_equal ["it has no release notes"], problems(feed)
  end

  def test_a_blank_description_is_a_problem
    feed = fixture_with(NOTES => "<description sparkle:format=\"markdown\"><![CDATA[ \n ]]></description>")

    assert_equal ["it has no release notes"], problems(feed)
  end

  def test_a_feed_that_does_not_parse_is_a_problem
    assert_equal ["it does not parse as XML"], problems("<rss")
  end

  def test_every_problem_is_listed_in_the_order_of_the_checks
    other = "https://example.com/InvoicesTracker-1.6.0-9.dmg"
    feed = fixture_with(ARCHIVE => other, BUILD => "<sparkle:version>9</sparkle:version>", NOTES => "")

    assert_equal ["its archive downloads from #{other}, not #{ARCHIVE}",
                  "it offers build 9, not 10",
                  "it has no release notes"],
                 problems(feed)
  end

  def test_a_feed_is_read_as_utf8_whatever_encoding_it_is_labelled_with
    czech = fixture_with("- Oprava" => "- Příliš žluťoučký kůň")

    [Encoding::US_ASCII, Encoding::BINARY].each do |encoding|
      feed = czech.dup.force_encoding(encoding)

      assert_equal [], problems(feed), encoding.to_s
      assert_equal 10, InvoicesTracker::Sparkle.latest_build(feed), encoding.to_s
    end
  end

  private

  # The fixture with each text that is a key of `replacements` replaced by its
  # value. A text that is not in the feed fails the test, so a variant is never
  # silently the fixture itself.
  def fixture_with(replacements)
    replacements.reduce(FIXTURE) do |feed, (old_text, new_text)|
      assert_includes feed, old_text
      feed.sub(old_text) { new_text }
    end
  end

  # What is wrong with `feed` as the feed of release 1.7.0, build 10, whose
  # archive is the fixture's.
  def problems(feed, build: "10")
    InvoicesTracker::Sparkle.feed_problems(feed, archive_url: ARCHIVE, version: "1.7.0", build: build)
  end
end
