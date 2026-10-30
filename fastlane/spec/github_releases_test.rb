# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "invoices_tracker/github_releases"

class InvoicesTrackerGitHubReleasesTest < Minitest::Test
  REPOSITORY = "Chlup/InvoicesTracker"

  # The calls the module has to make, spelled out so that a change to one of
  # them shows here: the ref of the tag v1.7.0-10, the Latest release, and the
  # asset appcast.xml of that release, whose id is 7.
  TAG_CALL = ["api", "repos/Chlup/InvoicesTracker/git/ref/tags/v1.7.0-10"].freeze
  LATEST_CALL = ["api", "repos/Chlup/InvoicesTracker/releases/latest"].freeze
  APPCAST_CALL = [
    "api", "-H", "Accept: application/octet-stream", "repos/Chlup/InvoicesTracker/releases/assets/7"
  ].freeze

  # What a failing gh may print, neither of which belongs in an error message:
  # a token, as the debug trace of a request could show it, and the body of the
  # response.
  TOKEN = "ghp_0123456789abcdefghijklmnopqrstuvwxyz"
  BODY = '{"message":"Bad credentials","documentation_url":"https://docs.github.com/rest"}'

  # What gh prints when GitHub answers 404 Not Found: the body on stdout and
  # the status line on stderr.
  NOT_FOUND = [
    '{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}',
    "gh: Not Found (HTTP 404)\n",
    false
  ].freeze

  # A feed as `generate_appcast` writes it, the file an appcast.xml asset holds.
  APPCAST = File.read(File.join(__dir__, "fixtures", "appcast.xml"), encoding: Encoding::UTF_8)

  # A call that the fake gh has no answer for.
  UnexpectedCall = Class.new(StandardError)

  # A stand-in for gh that never reaches the network. It answers each call from
  # `answers`, a Hash from the arguments of the call to what gh prints,
  # `[stdout, stderr, success]`, and records the calls in `gh_calls`. A call
  # without an answer raises UnexpectedCall: the module may ask GitHub nothing
  # else.
  def fake_gh(answers)
    @gh_calls = []
    lambda do |args|
      @gh_calls << args
      answers.fetch(args) { raise UnexpectedCall, "gh was called with #{args.inspect}" }
    end
  end

  attr_reader :gh_calls

  # What gh prints for a call that works.
  def printed(stdout)
    [stdout, "", true]
  end

  # What gh prints when GitHub refuses a request with `status`: the body on
  # stdout, the status line on stderr, and after it, in this made-up trace, the
  # token.
  def refused(status)
    [BODY, "gh: Bad credentials (HTTP #{status})\nAuthorization: token #{TOKEN}\n", false]
  end

  # A release as GitHub describes it. Only its `tag_name` and the `id` and
  # `name` of its assets are read, and the fields around them are there to be
  # told apart from those: the `id` of the release is not the id of any asset,
  # and its `name` is its title, not its tag.
  def release_json(tag: "v1.6.0-9", assets: [asset(7, "appcast.xml")], notes: "- Fixes\n")
    JSON.generate(
      "url" => "https://api.github.com/repos/Chlup/InvoicesTracker/releases/99",
      "assets_url" => "https://api.github.com/repos/Chlup/InvoicesTracker/releases/99/assets",
      "html_url" => "https://github.com/Chlup/InvoicesTracker/releases/tag/#{tag}",
      "id" => 99,
      "node_id" => "RE_kwDOExample",
      "author" => { "login" => "Chlup", "id" => 1, "type" => "User" },
      "tag_name" => tag,
      "target_commitish" => "main",
      "name" => "InvoicesTracker 1.6.0 (9)",
      "draft" => false,
      "prerelease" => false,
      "created_at" => "2026-10-01T09:00:00Z",
      "published_at" => "2026-10-01T09:05:00Z",
      "assets" => assets,
      "body" => notes
    )
  end

  # An asset of a release as GitHub lists it.
  def asset(id, name)
    {
      "url" => "https://api.github.com/repos/Chlup/InvoicesTracker/releases/assets/#{id}",
      "id" => id,
      "node_id" => "RA_kwDOExample#{id}",
      "name" => name,
      "label" => nil,
      "content_type" => "application/octet-stream",
      "state" => "uploaded",
      "size" => 1_024,
      "download_count" => 3,
      "created_at" => "2026-10-01T09:01:00Z",
      "updated_at" => "2026-10-01T09:02:00Z",
      "browser_download_url" => "https://github.com/Chlup/InvoicesTracker/releases/download/v1.6.0-9/#{name}"
    }
  end

  def tag_exists?(gh)
    InvoicesTracker::GitHubReleases.tag_exists?(repository: REPOSITORY, tag: "v1.7.0-10", gh: gh)
  end

  def latest(gh)
    InvoicesTracker::GitHubReleases.latest(repository: REPOSITORY, gh: gh)
  end

  def latest_release(tag, appcast_xml)
    InvoicesTracker::DeployPreflight::LatestRelease.new(tag: tag, appcast_xml: appcast_xml)
  end

  # The error says which call failed, with every argument of it, and gives away
  # nothing of what gh printed: not the token and not the body of the response.
  def assert_names_call_without_output(call, error)
    call.each { |argument| assert_includes error.message, argument }
    refute_includes error.message, TOKEN
    refute_includes error.message, BODY
  end

  # Answers that gh can print with success and that are no release: text that is
  # not JSON, JSON that is not an object, and objects without what a release has.
  def answers_that_are_not_a_release
    [
      "", "<!DOCTYPE html>", '{"tag_name": "v1.6.0-9", "assets": [',
      "null", "[]", "7", "true", '"v1.6.0-9"',
      "{}",
      JSON.generate("assets" => []),
      JSON.generate("tag_name" => nil, "assets" => []),
      JSON.generate("tag_name" => 6, "assets" => []),
      JSON.generate("tag_name" => " ", "assets" => []),
      JSON.generate("tag_name" => "v1.6.0-9"),
      JSON.generate("tag_name" => "v1.6.0-9", "assets" => nil),
      JSON.generate("tag_name" => "v1.6.0-9", "assets" => { "appcast.xml" => 7 }),
      JSON.generate("tag_name" => "v1.6.0-9", "assets" => ["appcast.xml"])
    ]
  end

  def test_a_tag_that_exists_is_found_by_asking_for_its_ref
    gh = fake_gh(TAG_CALL => printed('{"ref":"refs/tags/v1.7.0-10","object":{"type":"commit"}}'))

    assert_equal true, tag_exists?(gh)
    assert_equal [TAG_CALL], gh_calls
  end

  def test_a_tag_that_does_not_exist_is_not_found
    gh = fake_gh(TAG_CALL => NOT_FOUND)

    assert_equal false, tag_exists?(gh)
    assert_equal [TAG_CALL], gh_calls
  end

  def test_the_repository_and_the_tag_make_the_address_of_the_ref
    call = ["api", "repos/someone/else/git/ref/tags/v2.0-11"]
    gh = fake_gh(call => printed("{}"))

    assert_equal true, InvoicesTracker::GitHubReleases.tag_exists?(repository: "someone/else", tag: "v2.0-11", gh: gh)
    assert_equal [call], gh_calls
  end

  def test_a_failure_other_than_a_404_raises_an_error_that_names_the_call
    error = assert_raises(RuntimeError) { tag_exists?(fake_gh(TAG_CALL => refused(401))) }

    assert_names_call_without_output TAG_CALL, error
    assert_includes error.message, "HTTP 401"
    assert_equal [TAG_CALL], gh_calls
  end

  def test_no_status_other_than_404_is_taken_for_a_missing_tag
    [400, 401, 403, 409, 422, 500, 502, 503].each do |status|
      error = assert_raises(RuntimeError, "HTTP #{status}") { tag_exists?(fake_gh(TAG_CALL => refused(status))) }

      assert_includes error.message, "HTTP #{status}"
    end
  end

  def test_a_failure_without_an_http_status_raises_an_error_too
    [["", "error connecting to api.github.com\n", false], ["", "", nil], [nil, nil, false]].each do |answer|
      error = assert_raises(RuntimeError, answer.inspect) { tag_exists?(fake_gh(TAG_CALL => answer)) }

      assert_names_call_without_output TAG_CALL, error
    end
  end

  # Open3 labels what gh prints with the locale of the process, so a letter that
  # is not ASCII in the message of a failure arrives in a string that is broken
  # for its label, and a pattern refuses to match it. The message is read for
  # its status all the same, and the error is the one for any other failure.
  def test_a_failure_whose_message_has_a_letter_that_is_not_ascii_is_read_all_the_same
    message = ->(status) { "gh: chyba spojení (HTTP #{status})\n".dup.force_encoding(Encoding::US_ASCII) }

    assert_equal false, tag_exists?(fake_gh(TAG_CALL => ["", message.call(404), false]))

    error = assert_raises(RuntimeError) { tag_exists?(fake_gh(TAG_CALL => ["", message.call(502), false])) }

    assert_names_call_without_output TAG_CALL, error
    assert_includes error.message, "HTTP 502"
  end

  def test_no_latest_release_gives_nil
    gh = fake_gh(LATEST_CALL => NOT_FOUND)

    assert_nil latest(gh)
    assert_equal [LATEST_CALL], gh_calls
  end

  def test_the_latest_release_has_its_tag_and_the_text_of_its_appcast
    gh = fake_gh(LATEST_CALL => printed(release_json), APPCAST_CALL => printed(APPCAST))

    assert_equal latest_release("v1.6.0-9", APPCAST), latest(gh)
    assert_equal [LATEST_CALL, APPCAST_CALL], gh_calls
  end

  def test_the_appcast_is_found_by_its_name_wherever_it_is_listed_among_the_assets
    assets = [asset(5, "InvoicesTracker-1.6.0-9.dmg"), asset(7, "appcast.xml"), asset(6, "InvoicesTracker-1.6.0-9.md")]
    gh = fake_gh(LATEST_CALL => printed(release_json(assets: assets)), APPCAST_CALL => printed(APPCAST))

    assert_equal APPCAST, latest(gh).appcast_xml
    assert_equal [LATEST_CALL, APPCAST_CALL], gh_calls
  end

  def test_the_text_of_the_appcast_is_kept_exactly_as_gh_printed_it
    ["", "\n", "  #{APPCAST}\n\n", "<rss><title>Příliš žluťoučký kůň</title></rss>"].each do |text|
      gh = fake_gh(LATEST_CALL => printed(release_json), APPCAST_CALL => printed(text))

      assert_equal text, latest(gh).appcast_xml
    end
  end

  # Open3 labels what a command prints with the locale of the process, and a CI
  # step may have none: the label is US-ASCII, and the JSON parser refuses such
  # text once the notes of the release have a letter that is not ASCII. What gh
  # prints is UTF-8 whatever the label says.
  def test_the_answers_of_gh_are_read_as_utf_8_whatever_they_are_labelled_with
    feed = "<rss><title>Příliš žluťoučký kůň</title></rss>"
    release = release_json(notes: "Opraveno: příliš žluťoučký kůň\n")

    %w[US-ASCII ASCII-8BIT ISO-8859-2 UTF-8].each do |label|
      gh = fake_gh(
        LATEST_CALL => printed(release.dup.force_encoding(label)),
        APPCAST_CALL => printed(feed.dup.force_encoding(label))
      )

      found = latest(gh)

      assert_equal latest_release("v1.6.0-9", feed), found, label
      assert_equal Encoding::UTF_8, found.appcast_xml.encoding, label
    end
  end

  def test_a_release_without_an_appcast_has_none_and_nothing_is_downloaded
    [[], [asset(5, "InvoicesTracker-1.6.0-9.dmg"), asset(6, "InvoicesTracker-1.6.0-9.md")]].each do |assets|
      gh = fake_gh(LATEST_CALL => printed(release_json(assets: assets)))

      assert_equal latest_release("v1.6.0-9", nil), latest(gh)
      assert_equal [LATEST_CALL], gh_calls
    end
  end

  def test_only_an_asset_named_exactly_appcast_xml_is_the_appcast
    names = ["appcast.xml.sig", "Appcast.xml", "old-appcast.xml", " appcast.xml", "appcast.xml ", "appcast.rss"]
    assets = names.each_with_index.map { |name, index| asset(index + 1, name) }
    gh = fake_gh(LATEST_CALL => printed(release_json(assets: assets)))

    assert_equal latest_release("v1.6.0-9", nil), latest(gh)
    assert_equal [LATEST_CALL], gh_calls
  end

  def test_the_repository_makes_the_addresses_of_the_latest_release_and_its_appcast
    latest_call = ["api", "repos/someone/else/releases/latest"]
    appcast_call = ["api", "-H", "Accept: application/octet-stream", "repos/someone/else/releases/assets/42"]
    gh = fake_gh(
      latest_call => printed(release_json(assets: [asset(42, "appcast.xml")])), appcast_call => printed(APPCAST)
    )

    assert_equal APPCAST, InvoicesTracker::GitHubReleases.latest(repository: "someone/else", gh: gh).appcast_xml
    assert_equal [latest_call, appcast_call], gh_calls
  end

  def test_a_failure_to_read_the_latest_release_other_than_a_404_raises_an_error_that_names_the_call
    error = assert_raises(RuntimeError) { latest(fake_gh(LATEST_CALL => refused(403))) }

    assert_names_call_without_output LATEST_CALL, error
    assert_includes error.message, "HTTP 403"
    assert_equal [LATEST_CALL], gh_calls
  end

  def test_malformed_json_raises_an_error_that_quotes_none_of_it
    gh = fake_gh(LATEST_CALL => printed("<!DOCTYPE html><title>Unicorn!</title>#{TOKEN}"))

    error = assert_raises(RuntimeError) { latest(gh) }

    assert_names_call_without_output LATEST_CALL, error
    assert_nil error.cause, "the parser's message quotes the text it could not read"
    assert_equal [LATEST_CALL], gh_calls
  end

  def test_an_answer_that_is_no_release_raises_an_error_and_nothing_is_downloaded
    answers_that_are_not_a_release.each do |answer|
      gh = fake_gh(LATEST_CALL => printed(answer))

      error = assert_raises(RuntimeError, answer) { latest(gh) }

      assert_names_call_without_output LATEST_CALL, error
      assert_equal [LATEST_CALL], gh_calls
    end
  end

  def test_an_appcast_without_a_whole_number_for_an_id_raises_an_error_and_nothing_is_downloaded
    appcasts = [nil, "7", "7/../../x", 7.5, [7], true].map { |id| asset(7, "appcast.xml").merge("id" => id) }
    appcasts << asset(7, "appcast.xml").except("id")

    appcasts.each do |appcast|
      gh = fake_gh(LATEST_CALL => printed(release_json(assets: [appcast])))

      error = assert_raises(RuntimeError, appcast["id"].inspect) { latest(gh) }

      assert_names_call_without_output LATEST_CALL, error
      assert_equal [LATEST_CALL], gh_calls
    end
  end

  def test_an_appcast_that_cannot_be_downloaded_raises_an_error_that_names_the_download
    gh = fake_gh(LATEST_CALL => printed(release_json), APPCAST_CALL => refused(403))

    error = assert_raises(RuntimeError) { latest(gh) }

    assert_names_call_without_output APPCAST_CALL, error
    assert_includes error.message, "HTTP 403"
    assert_equal [LATEST_CALL, APPCAST_CALL], gh_calls
  end

  # The release lists the appcast, so a 404 for it is a problem with the
  # download, not a release that has no appcast.
  def test_an_appcast_that_is_listed_and_gone_raises_an_error_instead_of_giving_none
    gh = fake_gh(LATEST_CALL => printed(release_json), APPCAST_CALL => NOT_FOUND)

    error = assert_raises(RuntimeError) { latest(gh) }

    assert_names_call_without_output APPCAST_CALL, error
  end
end
