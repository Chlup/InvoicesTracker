# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"
require "invoices_tracker/release_manifest"

# Drives Scripts/ci/publish-release.sh with a fake gh, so that no test reaches GitHub. The fake appends the
# arguments of every call it gets to a log, one line per call, and the tests read the log to see what the script
# asked GitHub to do and in which order.
class InvoicesTrackerPublishReleaseScriptTest < Minitest::Test
  Manifest = InvoicesTracker::ReleaseManifest

  # The folders of one test: the feed folder the script is given, a working directory to run it in, a TMPDIR for
  # it, the fake gh with its call log, and the file the job summary is appended to.
  Scratch = Struct.new(:root, :feed, :work, :tmp, :gh, :log, :summary, keyword_init: true)

  REPO_ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(REPO_ROOT, "Scripts/ci/publish-release.sh")

  REPOSITORY = "Chlup/InvoicesTracker"
  TOKEN = "ghs_not_a_real_token_0123456789"
  COMMIT = "0123456789abcdef0123456789abcdef01234567"
  DMG_NAME = "InvoicesTracker-1.7.0-10.dmg"
  RELEASE_URL = "https://github.com/Chlup/InvoicesTracker/releases/tag/v1.7.0-10"

  # The ID that the fake answers when a draft is created. It is the only release the fake knows, and every call after
  # the create has to name the release by it.
  RELEASE_ID = 1001

  # The calls of a run that goes through, as the fake logs them (`create_call` and `upload_calls` are the ones that
  # depend on the folder): the checks before anything is created, the call that makes the git tag, and the publish.
  VIEW_CALL = "release view v1.7.0-10 --repo Chlup/InvoicesTracker"
  TAG_REF_CALL = "api repos/Chlup/InvoicesTracker/git/ref/tags/v1.7.0-10"
  LATEST_CALL = "api repos/Chlup/InvoicesTracker/releases/latest --jq .tag_name"
  CHECKS = [VIEW_CALL, TAG_REF_CALL, LATEST_CALL].freeze
  TAG_CREATE_CALL = "api --method POST repos/Chlup/InvoicesTracker/git/refs -f ref=refs/tags/v1.7.0-10 " \
                    "-f sha=#{COMMIT} --silent"
  PUBLISH_CALL = "api --method PATCH repos/Chlup/InvoicesTracker/releases/#{RELEASE_ID} -F draft=false " \
                 "-f make_latest=true --silent"

  # The calls that only a run makes which ends without having seen its publish succeed, as it cleans up after itself.
  # The release is asked whether it is a draft and, if it is, deleted. Then the git tag the run made is asked where it
  # points and whether a published release uses it, and, if all is well, deleted (TAG_CLEANUP_CALLS in that order).
  IS_DRAFT_CALL = "api repos/Chlup/InvoicesTracker/releases/#{RELEASE_ID} --jq .draft"
  DELETE_CALL = "api --method DELETE repos/Chlup/InvoicesTracker/releases/#{RELEASE_ID} --silent"
  TAG_POINTS_CALL = 'api repos/Chlup/InvoicesTracker/git/ref/tags/v1.7.0-10 --jq .object.type + ":" + .object.sha'
  RELEASE_ON_TAG_CALL = "api repos/Chlup/InvoicesTracker/releases/tags/v1.7.0-10 --silent"
  TAG_DELETE_CALL = "api --method DELETE repos/Chlup/InvoicesTracker/git/refs/tags/v1.7.0-10 --silent"
  TAG_CLEANUP_CALLS = [TAG_POINTS_CALL, RELEASE_ON_TAG_CALL, TAG_DELETE_CALL].freeze

  # What the fake answers unless a test says otherwise: no release and no tag yet, the Latest release is the one
  # the feed was made against, every write works, a release that is asked about is a draft, and the git tag the run
  # made points at the built commit and has no published release.
  DEFAULT_ANSWERS = {
    "FAKE_GH_RELEASE_VIEW" => "missing",
    "FAKE_GH_TAG_REF" => "404",
    "FAKE_GH_LATEST" => "v1.6.0-9",
    "FAKE_GH_CREATE" => "ok",
    "FAKE_GH_UPLOAD" => "ok",
    "FAKE_GH_TAG_CREATE" => "ok",
    "FAKE_GH_PUBLISH" => "ok",
    "FAKE_GH_IS_DRAFT" => "true",
    "FAKE_GH_DELETE" => "ok",
    "FAKE_GH_TAG_POINTS" => "commit",
    "FAKE_GH_RELEASE_ON_TAG" => "missing",
    "FAKE_GH_TAG_DELETE" => "ok"
  }.freeze

  # A stand-in for gh that answers the way the real tool does: `release view` says "release not found" for a release
  # that is not there, and a failed `gh api` call prints the body of the error on standard output and its status on
  # standard error. The fake knows one release, number 1001 (RELEASE_ID), which the create answers with. The
  # create is answered from FAKE_GH_CREATE: ok, refused (HTTP 422), error (HTTP 502), answer:<text>, which prints the
  # text although it is no release ID, or signal:<SIG>, which kills the script that called it, as a cancelled job does
  # while gh runs, and then answers the ID. The uploads, the publish and the delete are answered from FAKE_GH_UPLOAD,
  # FAKE_GH_PUBLISH and FAKE_GH_DELETE: ok or fail, and for the uploads and the publish signal:<SIG> too, which kills
  # the script and then succeeds. The question whether the release is a draft is answered from FAKE_GH_IS_DRAFT: true,
  # false, null (an answer that is none of the two), missing (HTTP 404), error, which prints true on standard output
  # although the call fails, as a failed gh call may, or signal:<SIG>, which kills the script and then answers true.
  # The calls about the git tag are answered from four variables. FAKE_GH_TAG_CREATE, the call that makes the tag: ok,
  # exists (HTTP 422 with "Reference already exists"), refused (HTTP 422 with another message), error (HTTP 502) or
  # signal:<SIG>, which kills the script and then succeeds. FAKE_GH_TAG_POINTS, the question where the tag points:
  # commit (at the built commit, which the fake gets as FAKE_GH_COMMIT), moved (at another commit), annotated (at a tag
  # object), missing (HTTP 404) or error (HTTP 502). FAKE_GH_RELEASE_ON_TAG, the question whether a published release
  # has the tag: missing (HTTP 404), found or error (HTTP 502). FAKE_GH_TAG_DELETE: ok or fail (HTTP 500). A call or an
  # answer it does not know ends with status 99, so a typo in a test cannot pass quietly.
  FAKE_GH = <<~'SH'
    #!/bin/sh
    printf '%s\n' "$*" >> "$FAKE_GH_LOG"

    http_error() {
      printf '{"message":"%s"}\n' "$1"
      echo "gh: $1 (HTTP $2)" >&2
      exit 1
    }
    unknown() {
      echo "fake gh: no answer for $1=$2" >&2
      exit 99
    }
    api=https://api.github.com/repos/Chlup/InvoicesTracker

    release_view() {
      case "$FAKE_GH_RELEASE_VIEW" in
        found) echo "title: InvoicesTracker 1.7.0 (10)" ;;
        missing) echo "release not found" >&2 ; exit 1 ;;
        error) echo "HTTP 502: Bad Gateway ($api/releases/tags/v1.7.0-10)" >&2 ; exit 1 ;;
        *) unknown FAKE_GH_RELEASE_VIEW "$FAKE_GH_RELEASE_VIEW" ;;
      esac
    }
    create_release() {
      case "$FAKE_GH_CREATE" in
        ok) echo 1001 ;;
        refused) http_error "Validation Failed" 422 ;;
        error) http_error "Bad Gateway" 502 ;;
        answer:*) printf '%s\n' "${FAKE_GH_CREATE#answer:}" ;;
        signal:*) kill -"${FAKE_GH_CREATE#signal:}" "$PPID" ; echo 1001 ;;
        *) unknown FAKE_GH_CREATE "$FAKE_GH_CREATE" ;;
      esac
    }
    upload_asset() {
      case "$FAKE_GH_UPLOAD" in
        ok) ;;
        fail) http_error "Bad Gateway" 502 ;;
        signal:*) kill -"${FAKE_GH_UPLOAD#signal:}" "$PPID" ;;
        *) unknown FAKE_GH_UPLOAD "$FAKE_GH_UPLOAD" ;;
      esac
    }
    publish_release() {
      case "$FAKE_GH_PUBLISH" in
        ok) ;;
        fail) http_error "Server Error" 500 ;;
        signal:*) kill -"${FAKE_GH_PUBLISH#signal:}" "$PPID" ;;
        *) unknown FAKE_GH_PUBLISH "$FAKE_GH_PUBLISH" ;;
      esac
    }
    release_is_draft() {
      case "$FAKE_GH_IS_DRAFT" in
        true|false|null) echo "$FAKE_GH_IS_DRAFT" ;;
        missing) http_error "Not Found" 404 ;;
        error) echo true ; echo "gh: Bad Gateway (HTTP 502)" >&2 ; exit 1 ;;
        signal:*) kill -"${FAKE_GH_IS_DRAFT#signal:}" "$PPID" ; echo true ;;
        *) unknown FAKE_GH_IS_DRAFT "$FAKE_GH_IS_DRAFT" ;;
      esac
    }
    delete_release() {
      case "$FAKE_GH_DELETE" in
        ok) ;;
        fail) http_error "Server Error" 500 ;;
        *) unknown FAKE_GH_DELETE "$FAKE_GH_DELETE" ;;
      esac
    }
    make_tag() {
      case "$FAKE_GH_TAG_CREATE" in
        ok) ;;
        exists) http_error "Reference already exists" 422 ;;
        refused) http_error "Object does not exist" 422 ;;
        error) http_error "Bad Gateway" 502 ;;
        signal:*) kill -"${FAKE_GH_TAG_CREATE#signal:}" "$PPID" ;;
        *) unknown FAKE_GH_TAG_CREATE "$FAKE_GH_TAG_CREATE" ;;
      esac
    }
    tag_points() {
      case "$FAKE_GH_TAG_POINTS" in
        commit) echo "commit:$FAKE_GH_COMMIT" ;;
        moved) echo commit:ffffffffffffffffffffffffffffffffffffffff ;;
        annotated) echo "tag:$FAKE_GH_COMMIT" ;;
        missing) http_error "Not Found" 404 ;;
        error) http_error "Bad Gateway" 502 ;;
        *) unknown FAKE_GH_TAG_POINTS "$FAKE_GH_TAG_POINTS" ;;
      esac
    }
    release_on_tag() {
      case "$FAKE_GH_RELEASE_ON_TAG" in
        found) ;;
        missing) http_error "Not Found" 404 ;;
        error) http_error "Bad Gateway" 502 ;;
        *) unknown FAKE_GH_RELEASE_ON_TAG "$FAKE_GH_RELEASE_ON_TAG" ;;
      esac
    }
    delete_tag() {
      case "$FAKE_GH_TAG_DELETE" in
        ok) ;;
        fail) http_error "Server Error" 500 ;;
        *) unknown FAKE_GH_TAG_DELETE "$FAKE_GH_TAG_DELETE" ;;
      esac
    }

    case "$*" in
      "release view "*) release_view ;;
      # The question where the tag points comes first: the pattern of the check below would take it too.
      "api repos/"*"/git/ref/tags/"*' --jq .object.type + ":" + .object.sha') tag_points ;;
      "api repos/"*"/git/ref/tags/"*)
        case "$FAKE_GH_TAG_REF" in
          found) echo '{"ref":"refs/tags/v1.7.0-10"}' ;;
          404) http_error "Not Found" 404 ;;
          error) http_error "Server Error" 500 ;;
          *) unknown FAKE_GH_TAG_REF "$FAKE_GH_TAG_REF" ;;
        esac ;;
      "api repos/"*"/releases/latest "*)
        case "$FAKE_GH_LATEST" in
          404) http_error "Not Found" 404 ;;
          error) http_error "Server Error" 500 ;;
          v*) echo "$FAKE_GH_LATEST" ;;
          *) unknown FAKE_GH_LATEST "$FAKE_GH_LATEST" ;;
        esac ;;
      "api --method POST repos/"*"/releases -f "*) create_release ;;
      "api --method POST https://uploads.github.com/repos/"*"/releases/1001/assets?name="*) upload_asset ;;
      "api --method POST repos/"*"/git/refs -f ref=refs/tags/"*) make_tag ;;
      "api --method PATCH repos/"*"/releases/1001 "*) publish_release ;;
      "api repos/"*"/releases/1001 --jq .draft") release_is_draft ;;
      "api --method DELETE repos/"*"/releases/1001 "*) delete_release ;;
      "api repos/"*"/releases/tags/"*" --silent") release_on_tag ;;
      "api --method DELETE repos/"*"/git/refs/tags/"*" --silent") delete_tag ;;
      *)
        echo "fake gh: no answer for: $*" >&2
        exit 99 ;;
    esac
  SH

  def test_publishes_a_draft_then_makes_it_latest
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch)

      assert_equal 0, status.exitstatus, stderr
      assert_equal [*CHECKS, *publish_calls(scratch)], calls(scratch)
      assert_includes stdout, RELEASE_URL
      assert_includes File.read(scratch.summary), RELEASE_URL
      assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
      [stdout, stderr, File.read(scratch.summary), File.read(scratch.log)].each do |text|
        refute_includes text, TOKEN
      end
    end
  end

  # A tag is no name for a draft: someone else can make a draft of the same tag after the checks. The only name the
  # script uses for the release it made is the ID that the create answered, and the `gh release` commands, which go by
  # the tag, are not used at all after the checks.
  def test_every_call_that_changes_the_release_names_its_id
    with_scratch do |scratch|
      write_feed(scratch)

      _stdout, stderr, status = publish(scratch)

      assert_equal 0, status.exitstatus, stderr
      changes = calls(scratch).select { |call| call.match?(/--method (PATCH|DELETE)|uploads\.github\.com/) }
      refute_empty changes, "no call that changes the release was found"
      changes.each { |call| assert_includes call, "/releases/#{RELEASE_ID}" }
      calls(scratch).each { |call| refute_match(/\Arelease (create|edit|upload|delete)/, call) }
    end
  end

  def test_the_first_release_is_published_when_none_exists_yet
    with_scratch do |scratch|
      write_feed(scratch, latest_tag: nil)

      _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_LATEST" => "404" })

      assert_equal 0, status.exitstatus, stderr
      assert_equal [*CHECKS, *publish_calls(scratch)], calls(scratch)
    end
  end

  def test_the_repository_comes_from_the_environment
    with_scratch do |scratch|
      write_feed(scratch)

      _stdout, stderr, status = publish(scratch, env: { "GITHUB_REPOSITORY" => "Someone/Fork" })

      assert_equal 0, status.exitstatus, stderr
      assert_equal ["release view v1.7.0-10 --repo Someone/Fork",
                    "api repos/Someone/Fork/git/ref/tags/v1.7.0-10",
                    "api repos/Someone/Fork/releases/latest --jq .tag_name"],
                   calls(scratch).first(3)
      assert_includes File.read(scratch.summary), "https://github.com/Someone/Fork/releases/tag/v1.7.0-10"
    end
  end

  def test_the_notes_file_name_comes_from_release_json
    with_scratch do |scratch|
      write_feed(scratch, changes: { "notes" => "changelog.md" })

      _stdout, stderr, status = publish(scratch)

      assert_equal 0, status.exitstatus, stderr
      assert_equal create_call(scratch, notes: "changelog.md"), calls(scratch)[3]
    end
  end

  def test_the_job_summary_is_optional
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, env: { "GITHUB_STEP_SUMMARY" => nil })

      assert_equal 0, status.exitstatus, stderr
      assert_includes stdout, RELEASE_URL
      refute_path_exists scratch.summary
    end
  end

  def test_a_checksum_mismatch_stops_before_any_gh_call
    [DMG_NAME, "appcast.xml"].each do |name|
      with_scratch do |scratch|
        write_feed(scratch)
        File.write(File.join(scratch.feed, name), "not the file the build made\n")

        _stdout, stderr, status = publish(scratch)

        refute_equal 0, status.exitstatus, name
        assert_includes stderr, "#{name} does not match its SHA-256 in release.json"
        assert_empty calls(scratch), "gh was called although #{name} was changed"
      end
    end
  end

  def test_a_missing_file_stops_before_any_gh_call
    [DMG_NAME, "appcast.xml", "release-notes.md", "release.json"].each do |name|
      with_scratch do |scratch|
        write_feed(scratch)
        File.delete(File.join(scratch.feed, name))

        _stdout, stderr, status = publish(scratch)

        refute_equal 0, status.exitstatus, name
        assert_includes stderr, "there is no #{name} in #{scratch.feed}"
        assert_empty calls(scratch), "gh was called although #{name} is missing"
      end
    end
  end

  def test_a_missing_feed_folder_stops_before_any_gh_call
    with_scratch do |scratch|
      _stdout, stderr, status = publish(scratch, args: [File.join(scratch.root, "no-such-folder")])

      refute_equal 0, status.exitstatus
      assert_includes stderr, "there is no feed folder at #{File.join(scratch.root, 'no-such-folder')}"
      assert_empty calls(scratch)
    end
  end

  # What the script uses from release.json goes to gh and into paths, so each value has to have its shape.
  def test_a_release_json_with_odd_values_stops_before_any_gh_call
    {
      "a version that is not a number" => [{ "version" => "latest" }, '"version"'],
      "a build that is not a positive number" => [{ "build" => "0" }, '"build"'],
      "a build that is no text" => [{ "build" => 10 }, '"build"'],
      "a missing build" => [{ "build" => :omit }, 'no text value for "build"'],
      "a tag that is not the version and the build" => [{ "tag" => "v1.7.0-11" }, '"tag"'],
      "a tag that is an option" => [{ "tag" => "--latest" }, '"tag"'],
      "an empty title" => [{ "title" => "" }, '"title"'],
      "a commit that is not a full hash" => [{ "commit" => "0123abc" }, '"commit"'],
      "a disk image name with a folder" => [{ "dmg" => "../#{DMG_NAME}" }, '"dmg"'],
      "a disk image name that is an option" => [{ "dmg" => "-#{DMG_NAME}" }, '"dmg"'],
      "a disk image that is no disk image" => [{ "dmg" => "InvoicesTracker-1.7.0-10.zip" }, '"dmg"'],
      "a disk image checksum that is not one" => [{ "dmg_sha256" => "abc" }, '"dmg_sha256"'],
      "an appcast checksum in capitals" => [{ "appcast_sha256" => "B" * 64 }, '"appcast_sha256"'],
      "a notes name with a folder" => [{ "notes" => "../release-notes.md" }, '"notes"'],
      "a notes name that is an option" => [{ "notes" => "-release-notes.md" }, '"notes"'],
      "no Latest tag at all" => [{ "latest_tag_seen" => nil }, '"latest_tag_seen"']
    }.each do |label, (changes, reason)|
      with_scratch do |scratch|
        write_feed(scratch, changes: changes)

        _stdout, stderr, status = publish(scratch)

        refute_equal 0, status.exitstatus, label
        assert_includes stderr, reason, label
        assert_empty calls(scratch), "gh was called with #{label}"
      end
    end
  end

  def test_a_release_json_that_is_no_json_object_stops_before_any_gh_call
    ["{ this is not json", "[]", "\"text\"", ""].each do |text|
      with_scratch do |scratch|
        write_feed(scratch)
        File.write(File.join(scratch.feed, "release.json"), text)

        _stdout, stderr, status = publish(scratch)

        refute_equal 0, status.exitstatus, text
        assert_includes stderr, "release.json is not a JSON object", text
        assert_empty calls(scratch)
      end
    end
  end

  def test_an_existing_release_stops_before_anything_is_created
    with_scratch do |scratch|
      write_feed(scratch)

      _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_RELEASE_VIEW" => "found" })

      refute_equal 0, status.exitstatus
      assert_includes stderr, "the release v1.7.0-10 exists already"
      assert_equal [VIEW_CALL], calls(scratch)
    end
  end

  def test_an_existing_tag_stops_before_anything_is_created
    with_scratch do |scratch|
      write_feed(scratch)

      _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_TAG_REF" => "found" })

      refute_equal 0, status.exitstatus
      assert_includes stderr, "the git tag v1.7.0-10 exists already"
      assert_equal [VIEW_CALL, TAG_REF_CALL], calls(scratch)
    end
  end

  # gh says "release not found" for a release that is not there. Any other failure of the question leaves the
  # script not knowing whether there is one, so it stops, and it names the call and the HTTP status but nothing else
  # of what gh printed.
  def test_a_failing_release_question_stops_before_anything_is_created
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_RELEASE_VIEW" => "error" })

      refute_equal 0, status.exitstatus
      assert_includes stderr, "gh #{VIEW_CALL} failed (HTTP 502)"
      refute_includes stdout + stderr, "Bad Gateway"
      assert_equal [VIEW_CALL], calls(scratch)
    end
  end

  def test_a_tag_question_that_fails_without_a_404_stops_before_anything_is_created
    with_scratch do |scratch|
      write_feed(scratch)

      _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_TAG_REF" => "error" })

      refute_equal 0, status.exitstatus
      assert_includes stderr, "gh #{TAG_REF_CALL} failed (HTTP 500)"
      assert_equal [VIEW_CALL, TAG_REF_CALL], calls(scratch)
    end
  end

  def test_a_release_published_meanwhile_stops_the_publish
    with_scratch do |scratch|
      write_feed(scratch, latest_tag: "v1.6.0-9")

      _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_LATEST" => "v1.6.1-10" })

      refute_equal 0, status.exitstatus
      assert_includes stderr, "the Latest release changed after the build checked it (then v1.6.0-9, now v1.6.1-10)"
      assert_equal CHECKS, calls(scratch)
    end
  end

  def test_a_first_release_published_meanwhile_stops_the_publish
    with_scratch do |scratch|
      write_feed(scratch, latest_tag: nil)

      _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_LATEST" => "v1.6.0-9" })

      refute_equal 0, status.exitstatus
      assert_includes stderr, "(then none, now v1.6.0-9)"
      assert_equal CHECKS, calls(scratch)
    end
  end

  def test_a_latest_release_that_vanished_meanwhile_stops_the_publish
    with_scratch do |scratch|
      write_feed(scratch, latest_tag: "v1.6.0-9")

      _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_LATEST" => "404" })

      refute_equal 0, status.exitstatus
      assert_includes stderr, "(then v1.6.0-9, now none)"
      assert_equal CHECKS, calls(scratch)
    end
  end

  def test_a_latest_question_that_fails_without_a_404_stops_before_anything_is_created
    with_scratch do |scratch|
      write_feed(scratch)

      _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_LATEST" => "error" })

      refute_equal 0, status.exitstatus
      assert_includes stderr, "gh #{LATEST_CALL.sub(' --jq .tag_name', '')} failed (HTTP 500)"
      assert_equal CHECKS, calls(scratch)
    end
  end

  def test_a_latest_tag_in_release_json_never_reaches_the_log_as_it_is
    with_scratch do |scratch|
      write_feed(scratch, changes: { "latest_tag_seen" => "v1.6.0-9\n::error::forged" })

      _stdout, stderr, status = publish(scratch)

      refute_equal 0, status.exitstatus
      assert_includes stderr, "(then v1.6.0-9???error??forged, now v1.6.0-9)"
      refute_includes stderr, "\n::error::"
    end
  end

  # Someone else can make a draft of this tag between the checks and the create. If the create then fails, or its
  # answer is lost, the script cannot tell whether GitHub made a draft of its own, and a draft of that tag may be the
  # other person's. So the script neither asks about it nor deletes it: it says where to look.
  def test_a_draft_of_the_same_tag_that_someone_else_made_is_never_touched
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_CREATE" => "error" })

      assert_equal 1, status.exitstatus
      assert_equal [*CHECKS, create_call(scratch)], calls(scratch)
      assert_includes stderr, "creating the draft release v1.7.0-10 failed (HTTP 502)"
      assert_includes stderr, "GitHub may have made the draft release v1.7.0-10 all the same, so nothing was deleted"
      assert_includes stderr, "https://github.com/Chlup/InvoicesTracker/releases"
      refute_includes stdout, "Deleting"
      assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
    end
  end

  # A create that GitHub refused with an HTTP 4xx status made nothing, so there is no draft to look for.
  def test_a_refused_create_made_nothing
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_CREATE" => "refused" })

      assert_equal 1, status.exitstatus
      assert_equal [*CHECKS, create_call(scratch)], calls(scratch)
      assert_includes stderr, "creating the draft release v1.7.0-10 failed (HTTP 422)"
      assert_includes stdout, "GitHub refused to create the release v1.7.0-10, so no draft was made."
      refute_includes stderr, "may have made"
    end
  end

  # Only an answer that is exactly a release ID counts. With any other, GitHub may have made the draft all the same,
  # and the script has no ID to name it by.
  def test_a_create_whose_answer_is_no_release_id_deletes_nothing
    ["null", "0", "-1", "12abc", "", "1001\n1002"].each do |answer|
      with_scratch do |scratch|
        write_feed(scratch)

        stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_CREATE" => "answer:#{answer}" })

        assert_equal 1, status.exitstatus, answer.inspect
        assert_equal [*CHECKS, create_call(scratch)], calls(scratch), answer.inspect
        assert_includes stderr, "has no release ID", answer.inspect
        assert_includes stderr, "may have made the draft release v1.7.0-10", answer.inspect
        refute_includes stdout, "Deleting", answer.inspect
      end
    end
  end

  # The draft that an upload failed to fill is the run's own, and it is found by its ID and deleted.
  def test_a_failed_upload_deletes_the_draft_by_its_id
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_UPLOAD" => "fail" })

      assert_equal 1, status.exitstatus
      assert_equal [*CHECKS, create_call(scratch), upload_calls(scratch).first, IS_DRAFT_CALL, DELETE_CALL],
                   calls(scratch)
      assert_includes stderr, "uploading #{DMG_NAME} to the draft release v1.7.0-10 failed (HTTP 502)"
      assert_includes stdout, "Deleted the draft release v1.7.0-10."
      assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
    end
  end

  # When a draft is published, GitHub makes the tag that it lacks, and uses the commit of a tag of that name that is
  # there already, whatever commit that is. So the script makes the tag itself, at the built commit, before the
  # publish. GitHub refuses that when someone pushed a tag of the name after the checks: the run stops, the draft is
  # deleted, and the tag, which is not the run's, is left alone and reported.
  def test_a_tag_that_appeared_after_the_checks_stops_the_run_and_its_draft_is_deleted
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_TAG_CREATE" => "exists" })

      assert_equal 1, status.exitstatus
      assert_equal [*CHECKS, *calls_to_make_the_tag(scratch), IS_DRAFT_CALL, DELETE_CALL], calls(scratch)
      assert_includes stderr, "the git tag v1.7.0-10 appeared after the checks, so the release was not published"
      assert_includes stderr, "Check https://github.com/Chlup/InvoicesTracker/tags"
      assert_includes stdout, "Deleted the draft release v1.7.0-10."
      refute_includes stdout, "Deleted the git tag"
      refute_includes stderr, "may have made the git tag"
      assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
    end
  end

  # A call that GitHub refused with an HTTP 4xx status made no tag, so there is none to look for.
  def test_a_refused_tag_made_nothing
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_TAG_CREATE" => "refused" })

      assert_equal 1, status.exitstatus
      assert_equal [*CHECKS, *calls_to_make_the_tag(scratch), IS_DRAFT_CALL, DELETE_CALL], calls(scratch)
      assert_includes stderr, "creating the git tag v1.7.0-10 failed (HTTP 422)"
      assert_includes stdout, "GitHub refused to create the git tag v1.7.0-10, so this run made no tag."
      refute_includes stderr, "may have made the git tag"
    end
  end

  # After any other failure GitHub may have made the tag all the same, and a tag of that name may be one that someone
  # else pushed, so the script deletes nothing and says where to look.
  def test_a_tag_that_may_have_been_made_is_left_and_reported
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_TAG_CREATE" => "error" })

      assert_equal 1, status.exitstatus
      assert_equal [*CHECKS, *calls_to_make_the_tag(scratch), IS_DRAFT_CALL, DELETE_CALL], calls(scratch)
      assert_includes stderr, "creating the git tag v1.7.0-10 failed (HTTP 502)"
      assert_includes stderr, "GitHub may have made the git tag v1.7.0-10 all the same, so it was not deleted"
      assert_includes stderr, "Check https://github.com/Chlup/InvoicesTracker/tags"
      refute_includes stdout, "Deleted the git tag"
      assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
    end
  end

  # The release is asked whether it is a draft, and only an answer of true lets the delete follow. The git tag that the
  # run made goes after the draft, once it is asked where it points and whether a published release uses it, because
  # the next run would stop at it.
  def test_a_failed_publish_deletes_the_draft_and_the_tag_it_made
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_PUBLISH" => "fail", "FAKE_GH_IS_DRAFT" => "true" })

      refute_equal 0, status.exitstatus
      assert_equal [*CHECKS, *publish_calls(scratch), IS_DRAFT_CALL, DELETE_CALL, *TAG_CLEANUP_CALLS], calls(scratch)
      assert_includes stderr, "publishing the release v1.7.0-10 failed (HTTP 500)"
      assert_includes stdout, "Deleted the draft release v1.7.0-10."
      assert_includes stdout, "Deleted the git tag v1.7.0-10, which this run made."
      assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
    end
  end

  def test_a_draft_that_cannot_be_deleted_is_reported_and_the_run_still_fails
    with_scratch do |scratch|
      write_feed(scratch)

      _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_PUBLISH" => "fail", "FAKE_GH_DELETE" => "fail" })

      refute_equal 0, status.exitstatus
      assert_equal [*CHECKS, *publish_calls(scratch), IS_DRAFT_CALL, DELETE_CALL, *TAG_CLEANUP_CALLS], calls(scratch)
      assert_includes stderr, "could not delete the draft release v1.7.0-10 (HTTP 500)"
      assert_includes stderr, "https://github.com/Chlup/InvoicesTracker/releases"
    end
  end

  # gh can fail to publish a release that GitHub did publish (a timeout, a server error after the change was made),
  # and then the release is published and Latest. It must be left alone: deleting it would withdraw the update from
  # every app and leave the git tag behind.
  def test_a_release_that_is_no_longer_a_draft_is_never_deleted
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_PUBLISH" => "fail", "FAKE_GH_IS_DRAFT" => "false" })

      assert_equal 1, status.exitstatus
      assert_equal [*CHECKS, *publish_calls(scratch), IS_DRAFT_CALL], calls(scratch)
      assert_includes stderr, "publishing the release v1.7.0-10 failed (HTTP 500)"
      assert_includes stderr, "the release v1.7.0-10 is not a draft any more, so it was not deleted"
      assert_includes stderr, "Check https://github.com/Chlup/InvoicesTracker/releases"
      refute_includes stdout, "Deleting"
      assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
    end
  end

  # A draft that is gone by the time it is asked about (someone deleted it) left nothing behind, which is no failure of
  # the cleanup.
  def test_a_release_that_is_gone_left_nothing_behind
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_PUBLISH" => "fail",
                                                           "FAKE_GH_IS_DRAFT" => "missing" })

      assert_equal 1, status.exitstatus
      assert_equal [*CHECKS, *publish_calls(scratch), IS_DRAFT_CALL, *TAG_CLEANUP_CALLS], calls(scratch)
      assert_includes stdout, "There is no release v1.7.0-10 on GitHub any more"
      refute_includes stderr, "could not"
    end
  end

  # The git tag that a run made is deleted only while it is still the run's: a lightweight tag at the built commit. One
  # that was moved to another commit, or replaced by an annotated tag (which answers a tag object, not a commit), is
  # someone else's now.
  def test_a_tag_that_is_not_the_runs_any_more_is_not_deleted
    %w[moved annotated].each do |answer|
      with_scratch do |scratch|
        write_feed(scratch)

        _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_PUBLISH" => "fail",
                                                              "FAKE_GH_TAG_POINTS" => answer })

        assert_equal 1, status.exitstatus, answer
        assert_equal [*CHECKS, *publish_calls(scratch), IS_DRAFT_CALL, DELETE_CALL, TAG_POINTS_CALL],
                     calls(scratch), answer
        assert_includes stderr, "the git tag v1.7.0-10 does not point at the built commit any more, so it was not " \
                                "deleted. Check https://github.com/Chlup/InvoicesTracker/tags", answer
      end
    end
  end

  # A published release on the tag would be left without it, so the tag stays.
  def test_a_tag_that_a_published_release_uses_is_not_deleted
    with_scratch do |scratch|
      write_feed(scratch)

      _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_PUBLISH" => "fail",
                                                            "FAKE_GH_RELEASE_ON_TAG" => "found" })

      assert_equal 1, status.exitstatus
      assert_equal [*CHECKS, *publish_calls(scratch), IS_DRAFT_CALL, DELETE_CALL, TAG_POINTS_CALL, RELEASE_ON_TAG_CALL],
                   calls(scratch)
      assert_includes stderr, "a published release uses the git tag v1.7.0-10, so it was not deleted. " \
                              "Check https://github.com/Chlup/InvoicesTracker/releases"
    end
  end

  # A tag that someone deleted meanwhile is nothing to delete, which is no failure of the cleanup.
  def test_a_tag_that_is_gone_is_not_deleted_again
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_PUBLISH" => "fail",
                                                           "FAKE_GH_TAG_POINTS" => "missing" })

      assert_equal 1, status.exitstatus
      assert_equal [*CHECKS, *publish_calls(scratch), IS_DRAFT_CALL, DELETE_CALL, TAG_POINTS_CALL], calls(scratch)
      assert_includes stdout, "There is no git tag v1.7.0-10 any more, so none was left behind."
      refute_includes stderr, "could not"
    end
  end

  # A question about the tag that fails leaves the tag where it is, and says which question it was. What a failed call
  # printed is not an answer.
  def test_tag_questions_that_fail_leave_the_tag
    {
      "the question where the tag points" => [
        { "FAKE_GH_TAG_POINTS" => "error" }, [TAG_POINTS_CALL],
        "could not tell where the git tag v1.7.0-10 points (HTTP 502), so it was not deleted. " \
        "Check https://github.com/Chlup/InvoicesTracker/tags"
      ],
      "the question whether a published release uses the tag" => [
        { "FAKE_GH_RELEASE_ON_TAG" => "error" }, [TAG_POINTS_CALL, RELEASE_ON_TAG_CALL],
        "could not tell whether a published release uses the git tag v1.7.0-10 (HTTP 502), so it was not deleted. " \
        "Check https://github.com/Chlup/InvoicesTracker/tags"
      ]
    }.each do |label, (answers, asked, message)|
      with_scratch do |scratch|
        write_feed(scratch)

        _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_PUBLISH" => "fail" }.merge(answers))

        assert_equal 1, status.exitstatus, label
        assert_equal [*CHECKS, *publish_calls(scratch), IS_DRAFT_CALL, DELETE_CALL, *asked], calls(scratch), label
        assert_includes stderr, message, label
      end
    end
  end

  # A tag that cannot be deleted is reported with where to delete it by hand, because the next run stops at it.
  def test_a_tag_that_cannot_be_deleted_is_reported
    with_scratch do |scratch|
      write_feed(scratch)

      _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_PUBLISH" => "fail",
                                                            "FAKE_GH_TAG_DELETE" => "fail" })

      assert_equal 1, status.exitstatus
      assert_equal [*CHECKS, *publish_calls(scratch), IS_DRAFT_CALL, DELETE_CALL, *TAG_CLEANUP_CALLS], calls(scratch)
      assert_includes stderr, "could not delete the git tag v1.7.0-10 (HTTP 500). " \
                              "Delete it at https://github.com/Chlup/InvoicesTracker/tags before the next run."
    end
  end

  # A draft that could not be deleted is a draft all the same, so no published release has the tag, and the tag goes.
  def test_the_tag_cleanup_follows_a_draft_whose_delete_failed
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_PUBLISH" => "fail", "FAKE_GH_DELETE" => "fail" })

      assert_equal 1, status.exitstatus
      assert_equal [*CHECKS, *publish_calls(scratch), IS_DRAFT_CALL, DELETE_CALL, *TAG_CLEANUP_CALLS], calls(scratch)
      assert_includes stderr, "could not delete the draft release v1.7.0-10 (HTTP 500)"
      assert_includes stdout, "Deleted the git tag v1.7.0-10, which this run made."
    end
  end

  # A release that is gone has no draft and no published release, and the tag goes.
  def test_the_tag_cleanup_follows_a_release_that_is_gone
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, _stderr, status = publish(scratch, answers: { "FAKE_GH_PUBLISH" => "fail",
                                                            "FAKE_GH_IS_DRAFT" => "missing" })

      assert_equal 1, status.exitstatus
      assert_equal [*CHECKS, *publish_calls(scratch), IS_DRAFT_CALL, *TAG_CLEANUP_CALLS], calls(scratch)
      assert_includes stdout, "Deleted the git tag v1.7.0-10, which this run made."
    end
  end

  # A release that is published, or that cannot be asked about and so may be published, has the tag: deleting it would
  # leave that release without its tag. So the tag is not asked about, let alone deleted, and not a word is said about
  # it.
  def test_the_tag_of_a_published_or_unknown_release_is_never_touched
    %w[false null error].each do |answer|
      with_scratch do |scratch|
        write_feed(scratch)

        stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_PUBLISH" => "fail",
                                                             "FAKE_GH_IS_DRAFT" => answer })

        assert_equal 1, status.exitstatus, answer
        assert_equal [*CHECKS, *publish_calls(scratch), IS_DRAFT_CALL], calls(scratch), answer
        refute_includes stdout, "Deleted the git tag", answer
        refute_includes stderr, "git tag", answer
      end
    end
  end

  # A cancelled job can end the script while the publish runs and goes through: the signal is dealt with when gh is
  # done, and by then the release is published.
  %w[HUP INT TERM].each do |signal|
    define_method("test_a_run_stopped_by_#{signal}_while_the_release_is_published_leaves_it_alone") do
      skip "#{signal} is ignored in this environment, so no shell can trap it" if signal_ignored?(signal)

      with_scratch do |scratch|
        write_feed(scratch)

        stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_PUBLISH" => "signal:#{signal}",
                                                             "FAKE_GH_IS_DRAFT" => "false" })

        assert_equal 128 + Signal.list.fetch(signal), status.exitstatus
        assert_equal [*CHECKS, *publish_calls(scratch), IS_DRAFT_CALL], calls(scratch)
        assert_includes stderr, "the release v1.7.0-10 is not a draft any more, so it was not deleted"
        refute_includes stdout, "Deleting"
        assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
      end
    end
  end

  # Only an answer of exactly true from a call that succeeded counts. gh prints the body of an error on standard
  # output for some calls that fail, so what a failed call printed is not read at all.
  def test_a_release_that_is_not_known_to_be_a_draft_is_never_deleted
    {
      "a question that failed after printing true" => ["error", "could not tell whether the release v1.7.0-10 is a " \
                                                                 "draft (HTTP 502), so it was not deleted"],
      "an answer that is neither true nor false" => ["null", "could not tell whether the release v1.7.0-10 is a " \
                                                             "draft, so it was not deleted"]
    }.each do |label, (answer, message)|
      with_scratch do |scratch|
        write_feed(scratch)

        stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_PUBLISH" => "fail",
                                                             "FAKE_GH_IS_DRAFT" => answer })

        assert_equal 1, status.exitstatus, label
        assert_equal [*CHECKS, *publish_calls(scratch), IS_DRAFT_CALL], calls(scratch), label
        assert_includes stderr, message, label
        assert_includes stderr, "Check https://github.com/Chlup/InvoicesTracker/releases", label
        refute_includes stdout, "Deleting", label
      end
    end
  end

  # A cancelled job ends the script with a signal. A draft is deleted all the same, and the run ends with the
  # status of the signal, never with success.
  %w[HUP INT TERM].each do |signal|
    define_method("test_a_run_stopped_by_#{signal}_after_the_draft_was_made_deletes_it") do
      skip "#{signal} is ignored in this environment, so no shell can trap it" if signal_ignored?(signal)

      with_scratch do |scratch|
        write_feed(scratch)

        _stdout, _stderr, status = publish(scratch, answers: { "FAKE_GH_UPLOAD" => "signal:#{signal}" })

        assert_equal 128 + Signal.list.fetch(signal), status.exitstatus
        assert_equal [*CHECKS, create_call(scratch), upload_calls(scratch).first, IS_DRAFT_CALL, DELETE_CALL],
                     calls(scratch)
        assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
      end
    end
  end

  # A signal that ends the script while the create runs is dealt with when gh is done, before the script has read
  # the ID that gh answered. The script has no ID then, so it deletes nothing, and the draft, if there is one, is left
  # for the reader to find.
  %w[HUP INT TERM].each do |signal|
    define_method("test_a_run_stopped_by_#{signal}_while_the_draft_is_created_deletes_nothing") do
      skip "#{signal} is ignored in this environment, so no shell can trap it" if signal_ignored?(signal)

      with_scratch do |scratch|
        write_feed(scratch)

        stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_CREATE" => "signal:#{signal}" })

        assert_equal 128 + Signal.list.fetch(signal), status.exitstatus
        assert_equal [*CHECKS, create_call(scratch)], calls(scratch)
        assert_includes stderr, "may have made the draft release v1.7.0-10"
        refute_includes stdout, "Deleting"
        assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
      end
    end
  end

  # A signal that ends the script while the tag is made is dealt with when gh is done, before the script has seen how
  # the call went. GitHub may have made the tag by then, and the script cannot tell it from a tag of that name that
  # someone else pushed, so the tag stays and the report says where to look. The draft is deleted all the same.
  %w[HUP INT TERM].each do |signal|
    define_method("test_a_run_stopped_by_#{signal}_while_the_tag_is_made_leaves_the_tag") do
      skip "#{signal} is ignored in this environment, so no shell can trap it" if signal_ignored?(signal)

      with_scratch do |scratch|
        write_feed(scratch)

        stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_TAG_CREATE" => "signal:#{signal}" })

        assert_equal 128 + Signal.list.fetch(signal), status.exitstatus
        assert_equal [*CHECKS, *calls_to_make_the_tag(scratch), IS_DRAFT_CALL, DELETE_CALL], calls(scratch)
        assert_includes stderr, "GitHub may have made the git tag v1.7.0-10 all the same"
        assert_includes stdout, "Deleted the draft release v1.7.0-10."
        assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
      end
    end
  end

  # A cancelled job gets INT and, some seconds later, TERM. The cleanup makes calls that take their time, so the
  # second signal comes while it runs, and it must not cut the cleanup short: the draft would be left behind. The run
  # still ends with the status of the first signal.
  def test_a_second_signal_during_the_cleanup_does_not_cut_it_short
    %w[INT TERM].each do |signal|
      skip "#{signal} is ignored in this environment, so no shell can trap it" if signal_ignored?(signal)
    end

    with_scratch do |scratch|
      write_feed(scratch)

      stdout, _stderr, status = publish(scratch, answers: { "FAKE_GH_UPLOAD" => "signal:INT",
                                                            "FAKE_GH_IS_DRAFT" => "signal:TERM" })

      assert_equal 128 + Signal.list.fetch("INT"), status.exitstatus
      assert_equal [*CHECKS, create_call(scratch), upload_calls(scratch).first, IS_DRAFT_CALL, DELETE_CALL],
                   calls(scratch)
      assert_includes stdout, "Deleted the draft release v1.7.0-10."
      assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
    end
  end

  def test_shell_syntax_in_the_changelog_is_never_run
    with_scratch do |scratch|
      write_feed(scratch, notes: "$(touch pwned) `touch pwned2`\n")

      _stdout, stderr, status = publish(scratch)

      assert_equal 0, status.exitstatus, stderr
      assert_empty Dir.glob(File.join(scratch.root, "**", "pwned*"), File::FNM_DOTMATCH), "something was run"
      assert_equal create_call(scratch), calls(scratch)[3], "the changelog must reach gh only as a file"
      refute_includes File.read(scratch.log), "pwned"
    end
  end

  def test_shell_syntax_in_release_json_is_never_run
    with_scratch do |scratch|
      write_feed(scratch, changes: { "title" => "$(touch pwned) `touch pwned2`" })

      stdout, stderr, status = publish(scratch)

      assert_equal 0, status.exitstatus, stderr
      assert_empty Dir.glob(File.join(scratch.root, "**", "pwned*"), File::FNM_DOTMATCH), "something was run"
      assert_equal create_call(scratch, title: "$(touch pwned) `touch pwned2`"), calls(scratch)[3]
      refute_includes stdout + stderr, "pwned"
    end
  end

  # The title goes to gh as text. One that gh would take for a file (@release-notes.md), for a boolean (true) or for a
  # number (123) if it were a typed field has to reach GitHub as the text it is.
  def test_a_title_that_looks_like_a_value_is_sent_as_text
    ["@release-notes.md", "true", "123"].each do |title|
      with_scratch do |scratch|
        write_feed(scratch, changes: { "title" => title })

        _stdout, stderr, status = publish(scratch)

        assert_equal 0, status.exitstatus, "#{title}: #{stderr}"
        assert_includes calls(scratch)[3], "-f name=#{title}", title
      end
    end
  end

  # A line of the log that starts with :: is a command of the workflow, so the title, which only has to be
  # something, is passed to gh and never printed. That holds for a create that fails too, whose message names the
  # call and not its arguments.
  def test_the_title_in_release_json_is_never_printed
    with_scratch do |scratch|
      write_feed(scratch, changes: { "title" => "Forged\n::error::forged" })

      stdout, stderr, status = publish(scratch)

      assert_equal 0, status.exitstatus, stderr
      [stdout, stderr, File.read(scratch.summary)].each do |text|
        refute_match(/^::/, text)
        refute_includes text, "Forged"
      end
    end

    with_scratch do |scratch|
      write_feed(scratch, changes: { "title" => "Forged\n::error::forged" })

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_CREATE" => "error" })

      assert_equal 1, status.exitstatus
      [stdout, stderr].each do |text|
        refute_match(/^::/, text)
        refute_includes text, "Forged"
      end
    end
  end

  def test_a_trailing_slash_on_the_feed_folder_is_dropped
    with_scratch do |scratch|
      write_feed(scratch)

      _stdout, stderr, status = publish(scratch, args: ["#{scratch.feed}/"])

      assert_equal 0, status.exitstatus, stderr
      assert_equal create_call(scratch), calls(scratch)[3]
    end
  end

  # The release is out by then, so the run has not failed.
  def test_a_job_summary_that_cannot_be_written_does_not_fail_a_published_release
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, env: { "GITHUB_STEP_SUMMARY" => scratch.work })

      assert_equal 0, status.exitstatus, stderr
      assert_includes stderr, "warning: could not write the summary of the job"
      assert_includes stdout, RELEASE_URL
      assert_equal [*CHECKS, *publish_calls(scratch)], calls(scratch)
    end
  end

  def test_the_arguments_are_checked
    with_scratch do |scratch|
      write_feed(scratch)

      [[], [scratch.feed, "extra"], ["--frobnicate"]].each do |args|
        stdout, stderr, status = publish(scratch, args: args)

        assert_equal 2, status.exitstatus, args.inspect
        assert_includes stderr, "Usage: Scripts/ci/publish-release.sh <feed-dir>", args.inspect
        assert_empty stdout
      end
      assert_empty calls(scratch)
    end
  end

  def test_help_prints_usage_and_exits_zero
    with_scratch do |scratch|
      %w[--help -h].each do |flag|
        stdout, _stderr, status = publish(scratch, args: [flag])

        assert_equal 0, status.exitstatus, flag
        assert_includes stdout, "Usage: Scripts/ci/publish-release.sh <feed-dir>"
      end
      assert_empty calls(scratch)
    end
  end

  def test_the_repository_must_be_given_as_owner_and_name
    with_scratch do |scratch|
      write_feed(scratch)

      [nil, "", "Chlup", "Chlup/InvoicesTracker/extra", "Chlup/Invoices Tracker", "-x/y"].each do |repository|
        _stdout, stderr, status = publish(scratch, env: { "GITHUB_REPOSITORY" => repository })

        refute_equal 0, status.exitstatus, repository.inspect
        assert_includes stderr, "GITHUB_REPOSITORY must be the repository as owner/name", repository.inspect
      end
      assert_empty calls(scratch)
    end
  end

  def test_a_missing_gh_stops_before_anything
    with_scratch do |scratch|
      write_feed(scratch)
      missing = File.join(scratch.root, "no-such-gh")

      _stdout, stderr, status = publish(scratch, env: { "GH" => missing })

      refute_equal 0, status.exitstatus
      assert_includes stderr, "#{missing} is not installed"
    end
  end

  # What the comment of with_scratch says: every path the script is given or reads from its environment has a space in
  # it, so a script that leaves one unquoted fails the tests above.
  def test_every_path_the_script_handles_has_a_space_in_it
    with_scratch do |scratch|
      { feed: scratch.feed, working_directory: scratch.work, TMPDIR: scratch.tmp, GH: scratch.gh,
        log_of_the_fake_gh: scratch.log, GITHUB_STEP_SUMMARY: scratch.summary }.each do |what, path|
        assert_includes path, " ", "the path of #{what} has no space in it: #{path}"
      end
    end
  end

  private

  # Yields the folders of one test, in a scratch directory that is removed afterwards. The name of the directory
  # has a space, so that every path the script handles has to be quoted. Dir.mktmpdir drops a space from the prefix it
  # is given, so the folder with the space is made inside the one it makes.
  def with_scratch
    Dir.mktmpdir("publish-release-") do |parent|
      root = File.join(parent, "publish release")
      Dir.mkdir(root)
      scratch = Scratch.new(root: root, feed: File.join(root, "feed"), work: File.join(root, "work"),
                            tmp: File.join(root, "tmp"), gh: File.join(root, "gh"), log: File.join(root, "gh.log"),
                            summary: File.join(root, "summary.md"))
      [scratch.feed, scratch.work, scratch.tmp].each { |dir| Dir.mkdir(dir) }
      File.write(scratch.gh, FAKE_GH)
      File.chmod(0o755, scratch.gh)
      yield scratch
    end
  end

  # Writes the feed folder the way the sparkle_feed lane does: the disk image, the update feed and the notes, and
  # the release.json that ReleaseManifest makes for them. `latest_tag` is the Latest release the build saw. A value
  # in `changes` replaces the one in release.json after that (`:omit` leaves the key out), which is how a test
  # makes a release.json that the build job would not write.
  def write_feed(scratch, notes: "- Fixed things\n", latest_tag: "v1.6.0-9", changes: {})
    dmg = "the disk image\n"
    appcast = "<rss version=\"2.0\"/>\n"
    File.write(File.join(scratch.feed, DMG_NAME), dmg)
    File.write(File.join(scratch.feed, "appcast.xml"), appcast)
    File.write(File.join(scratch.feed, Manifest::NOTES_FILE_NAME), notes)
    File.write(File.join(scratch.feed, File.basename(changes["notes"])), notes) if changes.key?("notes")

    contents = Manifest.contents(version: "1.7.0", build: "10", commit: COMMIT, dmg: DMG_NAME,
                                 dmg_sha256: Digest::SHA256.hexdigest(dmg),
                                 appcast_sha256: Digest::SHA256.hexdigest(appcast), latest_tag: latest_tag)
    changes.each { |key, value| value == :omit ? contents.delete(key) : contents[key] = value }
    File.write(File.join(scratch.feed, Manifest::FILE_NAME), Manifest.json(contents))
  end

  # Runs the script on the feed folder (or on `args`) in the working directory of the scratch, with the fake gh in
  # place of gh. `answers` replace what the fake answers and `env` any other variable; nil unsets one. The fake gets
  # the built commit too, which it answers when it is asked where the git tag points.
  def publish(scratch, args: nil, answers: {}, env: {})
    environment = DEFAULT_ANSWERS.merge(answers).merge(
      "GITHUB_REPOSITORY" => REPOSITORY, "GH" => scratch.gh, "GH_TOKEN" => TOKEN, "TMPDIR" => scratch.tmp,
      "GITHUB_STEP_SUMMARY" => scratch.summary, "FAKE_GH_LOG" => scratch.log, "FAKE_GH_COMMIT" => COMMIT
    ).merge(env)
    Open3.capture3(environment, SCRIPT, *(args || [scratch.feed]), chdir: scratch.work)
  end

  # Whether a process started from here has `signal` ignored. A job in the background ignores INT, and nohup
  # ignores HUP, and a shell cannot trap a signal that was ignored when it started.
  def signal_ignored?(signal)
    stdout, = Open3.capture2("sh", "-c", "kill -#{signal} $$; echo survived")
    stdout.include?("survived")
  end

  # The calls the fake gh got, in order, one string of arguments for each.
  def calls(scratch)
    File.exist?(scratch.log) ? File.readlines(scratch.log, chomp: true) : []
  end

  # The call that creates the draft release for the feed folder of `scratch`. The title is a raw field (-f), so that
  # it stays the text it is, and the notes are read from their file by gh.
  def create_call(scratch, notes: "release-notes.md", title: "InvoicesTracker 1.7.0 (10)")
    "api --method POST repos/Chlup/InvoicesTracker/releases -f tag_name=v1.7.0-10 -f target_commitish=#{COMMIT} " \
      "-f name=#{title} -F body=@#{scratch.feed}/#{notes} -F draft=true --jq .id"
  end

  # The two calls that attach the disk image and then the update feed to the draft, by its ID.
  def upload_calls(scratch)
    [[DMG_NAME, "application/x-apple-diskimage"], ["appcast.xml", "text/xml; charset=utf-8"]].map do |name, type|
      "api --method POST https://uploads.github.com/repos/Chlup/InvoicesTracker/releases/#{RELEASE_ID}/assets" \
        "?name=#{name} -H Content-Type: #{type} --input #{scratch.feed}/#{name} --silent"
    end
  end

  # The calls of a run that gets as far as making the git tag, after its checks: the create, the two uploads and the
  # call that makes the tag.
  def calls_to_make_the_tag(scratch)
    [create_call(scratch), *upload_calls(scratch), TAG_CREATE_CALL]
  end

  # The calls of a run that publishes, after its checks: the create, the two uploads, the tag and the publish. A test
  # that expects a release to go through compares with these, so that a new step of the publish is added in one place.
  def publish_calls(scratch)
    [*calls_to_make_the_tag(scratch), PUBLISH_CALL]
  end
end
