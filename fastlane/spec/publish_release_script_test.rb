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

  # The calls of a run that goes through, as the fake logs them (`create_call` is the one that depends on the
  # folder).
  VIEW_CALL = "release view v1.7.0-10 --repo Chlup/InvoicesTracker"
  TAG_REF_CALL = "api repos/Chlup/InvoicesTracker/git/ref/tags/v1.7.0-10"
  LATEST_CALL = "api repos/Chlup/InvoicesTracker/releases/latest --jq .tag_name"
  EDIT_CALL = "release edit v1.7.0-10 --repo Chlup/InvoicesTracker --draft=false --latest"
  DELETE_CALL = "release delete v1.7.0-10 --repo Chlup/InvoicesTracker --yes"
  CHECKS = [VIEW_CALL, TAG_REF_CALL, LATEST_CALL].freeze

  # What the fake answers unless a test says otherwise: no release and no tag yet, the Latest release is the one
  # the feed was made against, and every write works.
  DEFAULT_ANSWERS = {
    "FAKE_GH_RELEASE_VIEW" => "missing",
    "FAKE_GH_TAG_REF" => "404",
    "FAKE_GH_LATEST" => "v1.6.0-9",
    "FAKE_GH_CREATE" => "ok",
    "FAKE_GH_EDIT" => "ok",
    "FAKE_GH_DELETE" => "ok"
  }.freeze

  # A stand-in for gh that answers the way the real tool does: `release view` and `release delete` say
  # "release not found" for a release that is not there, and a failed `gh api` call prints the body of the error on
  # standard output and its status on standard error. A call or an answer it does not know ends with status 99, so
  # a typo in a test cannot pass quietly.
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

    case "$1 $2" in
      "release view")
        case "$FAKE_GH_RELEASE_VIEW" in
          found) echo "title: InvoicesTracker 1.7.0 (10)" ;;
          missing) echo "release not found" >&2 ; exit 1 ;;
          error) echo "HTTP 502: Bad Gateway ($api/releases/tags/v1.7.0-10)" >&2 ; exit 1 ;;
          *) unknown FAKE_GH_RELEASE_VIEW "$FAKE_GH_RELEASE_VIEW" ;;
        esac ;;
      "api repos/"*"/git/ref/tags/"*)
        case "$FAKE_GH_TAG_REF" in
          found) echo '{"ref":"refs/tags/v1.7.0-10"}' ;;
          404) http_error "Not Found" 404 ;;
          error) http_error "Server Error" 500 ;;
          *) unknown FAKE_GH_TAG_REF "$FAKE_GH_TAG_REF" ;;
        esac ;;
      "api repos/"*"/releases/latest")
        case "$FAKE_GH_LATEST" in
          404) http_error "Not Found" 404 ;;
          error) http_error "Server Error" 500 ;;
          v*) echo "$FAKE_GH_LATEST" ;;
          *) unknown FAKE_GH_LATEST "$FAKE_GH_LATEST" ;;
        esac ;;
      "release create")
        case "$FAKE_GH_CREATE" in
          ok) echo "https://github.com/Chlup/InvoicesTracker/releases/tag/untagged-0123456789abcdef" ;;
          fail) echo "error uploading the asset: connection reset" >&2 ; exit 1 ;;
          signal:*) kill -"${FAKE_GH_CREATE#signal:}" "$PPID" ;;
          *) unknown FAKE_GH_CREATE "$FAKE_GH_CREATE" ;;
        esac ;;
      "release edit")
        case "$FAKE_GH_EDIT" in
          ok) echo "https://github.com/Chlup/InvoicesTracker/releases/tag/v1.7.0-10" ;;
          fail) echo "HTTP 500: Server Error ($api/releases/1)" >&2 ; exit 1 ;;
          *) unknown FAKE_GH_EDIT "$FAKE_GH_EDIT" ;;
        esac ;;
      "release delete")
        case "$FAKE_GH_DELETE" in
          ok) echo "Deleted release v1.7.0-10" ;;
          missing) echo "release not found" >&2 ; exit 1 ;;
          fail) echo "HTTP 500: Server Error ($api/releases/1)" >&2 ; exit 1 ;;
          *) unknown FAKE_GH_DELETE "$FAKE_GH_DELETE" ;;
        esac ;;
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
      assert_equal [*CHECKS, create_call(scratch), EDIT_CALL], calls(scratch)
      assert_includes stdout, RELEASE_URL
      assert_includes File.read(scratch.summary), RELEASE_URL
      assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
      [stdout, stderr, File.read(scratch.summary), File.read(scratch.log)].each do |text|
        refute_includes text, TOKEN
      end
    end
  end

  def test_the_first_release_is_published_when_none_exists_yet
    with_scratch do |scratch|
      write_feed(scratch, latest_tag: nil)

      _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_LATEST" => "404" })

      assert_equal 0, status.exitstatus, stderr
      assert_equal [*CHECKS, create_call(scratch), EDIT_CALL], calls(scratch)
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

  def test_a_failed_publish_deletes_only_its_draft
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_EDIT" => "fail" })

      refute_equal 0, status.exitstatus
      assert_equal [*CHECKS, create_call(scratch), EDIT_CALL, DELETE_CALL], calls(scratch)
      assert_includes stderr, "gh release edit failed"
      assert_includes stdout, "Deleted the draft release v1.7.0-10"
      assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
    end
  end

  def test_a_failed_create_deletes_the_draft_it_may_have_left
    with_scratch do |scratch|
      write_feed(scratch)

      _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_CREATE" => "fail" })

      refute_equal 0, status.exitstatus
      assert_equal [*CHECKS, create_call(scratch), DELETE_CALL], calls(scratch)
      assert_includes stderr, "gh release create failed"
    end
  end

  def test_a_failed_create_that_left_no_draft_says_so
    with_scratch do |scratch|
      write_feed(scratch)

      stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_CREATE" => "fail", "FAKE_GH_DELETE" => "missing" })

      refute_equal 0, status.exitstatus
      assert_includes stdout, "There was no draft release v1.7.0-10 to delete"
      refute_includes stderr, "could not delete"
    end
  end

  def test_a_draft_that_cannot_be_deleted_is_reported_and_the_run_still_fails
    with_scratch do |scratch|
      write_feed(scratch)

      _stdout, stderr, status = publish(scratch, answers: { "FAKE_GH_EDIT" => "fail", "FAKE_GH_DELETE" => "fail" })

      refute_equal 0, status.exitstatus
      assert_equal [*CHECKS, create_call(scratch), EDIT_CALL, DELETE_CALL], calls(scratch)
      assert_includes stderr, "could not delete the draft release v1.7.0-10 (HTTP 500)"
      assert_includes stderr, "https://github.com/Chlup/InvoicesTracker/releases"
    end
  end

  # A cancelled job ends the script with a signal. The draft is deleted all the same, and the run ends with the
  # status of the signal, never with success.
  %w[HUP INT TERM].each do |signal|
    define_method("test_a_run_stopped_by_#{signal}_after_the_draft_was_made_deletes_it") do
      skip "#{signal} is ignored in this environment, so no shell can trap it" if signal_ignored?(signal)

      with_scratch do |scratch|
        write_feed(scratch)

        _stdout, _stderr, status = publish(scratch, answers: { "FAKE_GH_CREATE" => "signal:#{signal}" })

        assert_equal 128 + Signal.list.fetch(signal), status.exitstatus
        assert_equal [*CHECKS, create_call(scratch), DELETE_CALL], calls(scratch)
        assert_empty Dir.children(scratch.tmp), "the script must remove the files it made"
      end
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

  # A line of the log that starts with :: is a command of the workflow, so the title, which only has to be
  # something, is passed to gh and never printed.
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
      assert_equal [*CHECKS, create_call(scratch), EDIT_CALL], calls(scratch)
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

  private

  # Yields the folders of one test, in a scratch directory that is removed afterwards. The name of the directory
  # has a space, so that every path the script handles has to be quoted.
  def with_scratch
    Dir.mktmpdir("publish release ") do |root|
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
  # place of gh. `answers` replace what the fake answers and `env` any other variable; nil unsets one.
  def publish(scratch, args: nil, answers: {}, env: {})
    environment = DEFAULT_ANSWERS.merge(answers).merge(
      "GITHUB_REPOSITORY" => REPOSITORY, "GH" => scratch.gh, "GH_TOKEN" => TOKEN, "TMPDIR" => scratch.tmp,
      "GITHUB_STEP_SUMMARY" => scratch.summary, "FAKE_GH_LOG" => scratch.log
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

  # The call that creates the draft release for the feed folder of `scratch`.
  def create_call(scratch, notes: "release-notes.md", title: "InvoicesTracker 1.7.0 (10)")
    "release create v1.7.0-10 --repo Chlup/InvoicesTracker --draft --target #{COMMIT} --title #{title} " \
      "--notes-file #{scratch.feed}/#{notes} #{scratch.feed}/#{DMG_NAME} #{scratch.feed}/appcast.xml"
  end
end
