# frozen_string_literal: true

require "minitest/autorun"
require "pp"
require "invoices_tracker/deploy_preflight"

class InvoicesTrackerDeployPreflightTest < Minitest::Test
  FEED_URL = InvoicesTracker::Release::FEED_URL

  # RFC 8032, section 7.1, test 1: a seed and the public key that belongs to it.
  # Test 2's public key is one that seed does not belong to.
  SEED = ["9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"].pack("H*")
  PUBLIC = ["d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"].pack("H*")
  OTHER_PUBLIC = ["3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"].pack("H*")

  # The secret SPARKLE_PRIVATE_KEY and the app's SUPublicEDKey, as they are
  # written there: in base64.
  PRIVATE_KEY = [SEED].pack("m0")
  PUBLIC_KEY = [PUBLIC].pack("m0")
  OTHER_PUBLIC_KEY = [OTHER_PUBLIC].pack("m0")

  # A feed as `generate_appcast` writes it, whose one update is build 10.
  APPCAST = File.read(File.join(__dir__, "fixtures", "appcast.xml"), encoding: Encoding::UTF_8)
  BUILD = "<sparkle:version>10</sparkle:version>"

  # The problem of a branch that adds or changes workflow files, with `paths`,
  # a text, where it names them.
  WORKFLOW_PROBLEM = lambda do |paths|
    "the branch adds or changes #{paths} compared with the default branch — GitHub would refuse to publish the " \
      "release; merge the default branch into it, or land the workflow change there first"
  end

  # Facts in which every check passes: a release nothing else has the tag of,
  # nothing published yet to be newer than, and a branch that changes no
  # workflow file. Each test breaks what it examines.
  def facts(**overrides)
    InvoicesTracker::DeployPreflight::Facts.new(
      **{
        version: "1.7.0", build: "10", changelog: "- x", tag_exists: false, latest_release: nil,
        workflow_changes: [], info_plist: plist, sparkle_private_key: PRIVATE_KEY
      }.merge(overrides)
    )
  end

  def errors(**overrides)
    InvoicesTracker::DeployPreflight.errors(facts(**overrides))
  end

  # The settings of the app's Info.plist that Sparkle reads, as the app should
  # have them, with `overrides` changed.
  def plist(overrides = {})
    { "SUFeedURL" => FEED_URL, "SUPublicEDKey" => PUBLIC_KEY }.merge(overrides)
  end

  def plist_without(name)
    plist.except(name)
  end

  # The Latest release `v1.0`, whose appcast.xml is `appcast_xml`.
  def latest(appcast_xml)
    InvoicesTracker::DeployPreflight::LatestRelease.new(tag: "v1.0", appcast_xml: appcast_xml)
  end

  # The fixture feed with its update offering `build`. A variant that is the
  # fixture itself fails the test, so it never passes for the wrong reason.
  def feed_of_build(build)
    assert_includes APPCAST, BUILD
    APPCAST.sub(BUILD, "<sparkle:version>#{build}</sparkle:version>")
  end

  def test_valid_facts_have_no_errors
    assert_equal [], errors
  end

  def test_an_empty_changelog_stops_a_deploy
    ["", " ", nil, "  \\n  "].each do |changelog|
      assert_equal ["the changelog is empty — a deploy needs release notes"],
                   errors(changelog: changelog), changelog.inspect
    end
  end

  def test_an_existing_tag_stops_a_deploy
    assert_equal ["the release v1.7.0-10 already exists — choose a new build number"], errors(tag_exists: true)
  end

  def test_the_existing_tag_is_named_after_the_version_and_the_build
    assert_equal ["the release v2.0-11 already exists — choose a new build number"],
                 errors(version: "2.0", build: "11", tag_exists: true)
  end

  def test_a_latest_release_without_a_feed_stops_a_deploy
    assert_equal ["the Latest release v1.0 has no appcast.xml — only the release workflow may publish releases"],
                 errors(latest_release: latest(nil))
  end

  def test_a_build_that_is_not_higher_than_the_newest_published_one_stops_a_deploy
    assert_equal ["build 10 is not higher than 12, the newest published build"],
                 errors(latest_release: latest(feed_of_build(12)))
    assert_equal ["build 10 is not higher than 10, the newest published build"],
                 errors(latest_release: latest(feed_of_build(10)))
  end

  def test_a_build_higher_than_the_newest_published_one_is_fine
    assert_equal [], errors(latest_release: latest(feed_of_build(9)))
  end

  def test_builds_are_compared_as_numbers
    assert_equal [], errors(build: "100", latest_release: latest(feed_of_build(99)))
    assert_equal ["build 9 is not higher than 10, the newest published build"],
                 errors(build: "9", latest_release: latest(feed_of_build(10)))
  end

  def test_a_latest_feed_without_a_build_stops_a_deploy
    message = "the Latest release v1.0 has an appcast.xml without a build"

    assert_equal [message], errors(latest_release: latest(APPCAST.sub(BUILD, "")))
    assert_equal [message], errors(latest_release: latest(""))
    assert_equal [message], errors(latest_release: latest("<rss"))
  end

  # A typed build that is not a number is reported by
  # BuildSettings.mismatch_errors, which runs before this check. Here there is
  # nothing to compare, and the check must not fail on it.
  def test_a_typed_build_that_is_not_a_number_is_not_compared
    assert_equal [], errors(build: "10a", latest_release: latest(feed_of_build(12)))
  end

  def test_a_branch_that_changes_a_workflow_file_stops_a_deploy
    assert_equal [WORKFLOW_PROBLEM.call(".github/workflows/release.yml")],
                 errors(workflow_changes: [".github/workflows/release.yml"])
  end

  def test_every_changed_workflow_file_is_named_in_order
    assert_equal [WORKFLOW_PROBLEM.call(".github/workflows/a.yml, .github/workflows/z.yml")],
                 errors(workflow_changes: [".github/workflows/z.yml", ".github/workflows/a.yml"])
  end

  def test_no_workflow_changes_are_fine
    [[], nil].each do |changes|
      assert_equal [], errors(workflow_changes: changes), changes.inspect
    end
  end

  def test_an_unreadable_info_plist_stops_a_deploy
    assert_equal ["the app's Info.plist cannot be read — does the branch have Sparkle?"], errors(info_plist: nil)
  end

  def test_another_feed_url_stops_a_deploy
    assert_equal ["SUFeedURL is https://x, not #{FEED_URL}"],
                 errors(info_plist: plist("SUFeedURL" => "https://x"))
  end

  def test_a_missing_feed_url_stops_a_deploy
    message = "SUFeedURL is missing, not #{FEED_URL}"

    assert_equal [message], errors(info_plist: plist_without("SUFeedURL"))
    assert_equal [message], errors(info_plist: plist("SUFeedURL" => ""))
  end

  def test_a_missing_private_key_stops_a_deploy
    [nil, "", " \n"].each do |key|
      assert_equal ["SPARKLE_PRIVATE_KEY is not set"], errors(sparkle_private_key: key), key.inspect
    end
  end

  def test_a_private_key_that_cannot_be_read_stops_a_deploy_without_being_quoted
    ["hunter2 is not base64!", "c2hvcnQ="].each do |key|
      found = errors(sparkle_private_key: key)

      assert_equal ["SPARKLE_PRIVATE_KEY is not a Sparkle private key"], found, key
      refute_includes found.join, key
    end
  end

  def test_whitespace_around_the_private_key_is_ignored
    assert_equal [], errors(sparkle_private_key: " #{PRIVATE_KEY}\n")
  end

  def test_a_missing_public_key_stops_a_deploy
    message = "the app has no SUPublicEDKey — does the branch have Sparkle?"

    assert_equal [message], errors(info_plist: plist_without("SUPublicEDKey"))
    assert_equal [message], errors(info_plist: plist("SUPublicEDKey" => ""))
  end

  def test_a_public_key_that_is_not_the_private_keys_stops_a_deploy
    assert_equal ["SUPublicEDKey does not match SPARKLE_PRIVATE_KEY — installed apps would reject this update"],
                 errors(info_plist: plist("SUPublicEDKey" => OTHER_PUBLIC_KEY))
  end

  # Without a private key that can be read there is no pair to compare, and
  # the key itself is the problem to report.
  def test_a_public_key_is_not_compared_with_a_private_key_that_cannot_be_used
    assert_equal ["SPARKLE_PRIVATE_KEY is not set"],
                 errors(sparkle_private_key: nil, info_plist: plist("SUPublicEDKey" => OTHER_PUBLIC_KEY))
    assert_equal ["SPARKLE_PRIVATE_KEY is not a Sparkle private key"],
                 errors(sparkle_private_key: "nope", info_plist: plist("SUPublicEDKey" => OTHER_PUBLIC_KEY))
  end

  # An Info.plist that cannot be read says nothing about the app's feed or key,
  # so neither is reported as missing; the secret is still checked.
  def test_an_unreadable_info_plist_does_not_hide_a_missing_private_key
    assert_equal ["the app's Info.plist cannot be read — does the branch have Sparkle?",
                  "SPARKLE_PRIVATE_KEY is not set"],
                 errors(info_plist: nil, sparkle_private_key: nil)
  end

  def test_every_problem_is_listed_in_the_order_of_the_checks
    found = errors(
      changelog: "", tag_exists: true, latest_release: latest(feed_of_build(12)),
      workflow_changes: [".github/workflows/release.yml"],
      info_plist: { "SUFeedURL" => "https://x" }, sparkle_private_key: "nope"
    )

    assert_equal [
      "the changelog is empty — a deploy needs release notes",
      "the release v1.7.0-10 already exists — choose a new build number",
      "build 10 is not higher than 12, the newest published build",
      WORKFLOW_PROBLEM.call(".github/workflows/release.yml"),
      "SUFeedURL is https://x, not #{FEED_URL}",
      "SPARKLE_PRIVATE_KEY is not a Sparkle private key",
      "the app has no SUPublicEDKey — does the branch have Sparkle?"
    ], found
  end

  def test_the_other_problems_keep_the_same_order
    found = errors(
      changelog: nil, latest_release: latest(nil),
      info_plist: plist("SUFeedURL" => "https://x", "SUPublicEDKey" => OTHER_PUBLIC_KEY)
    )

    assert_equal [
      "the changelog is empty — a deploy needs release notes",
      "the Latest release v1.0 has no appcast.xml — only the release workflow may publish releases",
      "SUFeedURL is https://x, not #{FEED_URL}",
      "SUPublicEDKey does not match SPARKLE_PRIVATE_KEY — installed apps would reject this update"
    ], found
  end

  def test_a_feed_without_a_build_and_an_unreadable_plist_and_key_come_in_order
    found = errors(latest_release: latest("<rss/>"), info_plist: nil, sparkle_private_key: nil)

    assert_equal [
      "the Latest release v1.0 has an appcast.xml without a build",
      "the app's Info.plist cannot be read — does the branch have Sparkle?",
      "SPARKLE_PRIVATE_KEY is not set"
    ], found
  end

  # The facts hold the private key, and a log must never show it, whether the
  # facts are printed on purpose or end up in a failed assertion.
  def test_the_facts_print_without_the_private_key
    shown = facts

    [shown.inspect, shown.to_s, "#{shown}", PP.pp(shown, +"")].each do |text|
      refute_includes text, PRIVATE_KEY
      assert_includes text, "version=\"1.7.0\""
      assert_includes text, "sparkle_private_key=[redacted]"
    end
  end

  def test_the_facts_print_a_private_key_that_is_not_set_as_such
    assert_includes facts(sparkle_private_key: nil).inspect, "sparkle_private_key=nil"
  end
end
