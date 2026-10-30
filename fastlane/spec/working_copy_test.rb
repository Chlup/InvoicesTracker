# frozen_string_literal: true

require "minitest/autorun"
require "invoices_tracker/working_copy"

class InvoicesTrackerWorkingCopyTest < Minitest::Test
  WORKING_COPY = InvoicesTracker::WorkingCopy

  BUILT = "e644452dc76fb013abe74bf9910c50c4207de76e"
  MOVED_TO = "8a1b2c3d4e5f60718293a4b5c6d7e8f901234567"

  CHANGED = "The working copy changed while the app was being built: "
  WHAT_TO_DO = " — commit or stash, then run again"

  def snapshot(head: BUILT, dirty_paths: [])
    WORKING_COPY::Snapshot.new(head: head, dirty_paths: dirty_paths)
  end

  # What the lane finds right after the archive, against the clean snapshot the
  # preflight took of the same commit.
  def error_after_build(**after)
    WORKING_COPY.error_since(snapshot, snapshot(**after))
  end

  def test_the_same_commit_with_nothing_uncommitted_is_no_change
    assert_nil error_after_build
  end

  def test_a_moved_head_is_a_change
    assert_equal "#{CHANGED}HEAD moved from e644452 to 8a1b2c3#{WHAT_TO_DO}", error_after_build(head: MOVED_TO)
  end

  def test_a_modified_file_is_a_change
    assert_equal "#{CHANGED}uncommitted changes:  M InvoicesTracker/App.swift#{WHAT_TO_DO}",
                 error_after_build(dirty_paths: [" M InvoicesTracker/App.swift"])
  end

  def test_an_untracked_file_is_a_change
    assert_equal "#{CHANGED}uncommitted changes: ?? notes.txt#{WHAT_TO_DO}",
                 error_after_build(dirty_paths: ["?? notes.txt"])
  end

  def test_a_moved_head_and_a_changed_file_are_both_named
    assert_equal "#{CHANGED}HEAD moved from e644452 to 8a1b2c3; uncommitted changes: ?? notes.txt#{WHAT_TO_DO}",
                 error_after_build(head: MOVED_TO, dirty_paths: ["?? notes.txt"])
  end

  # A staged change is a change too: git lists it with its own status letters.
  def test_every_path_git_lists_counts
    lines = ["M  staged.swift", "A  added.swift", "D  deleted.swift", "R  old.swift -> new.swift", " D gone.swift"]

    lines.each do |line|
      assert_equal "#{CHANGED}uncommitted changes: #{line}#{WHAT_TO_DO}", error_after_build(dirty_paths: [line])
    end
  end

  # A messy working copy does not bury the rest of the message.
  def test_long_lists_of_changes_are_cut_after_ten
    message = error_after_build(dirty_paths: (1..12).map { |i| " M file#{i}.swift" })

    assert message.end_with?(" M file10.swift …#{WHAT_TO_DO}"), message
    refute_includes message, "file11.swift"
  end

  # The whole commit is compared, not the form people read. Two commits can
  # share their first seven characters; the message then gives them whole, so
  # it never says that a commit moved to itself.
  def test_commits_that_look_alike_in_short_form_are_still_different
    look_alike = BUILT[0, 7] + ("0" * 33)

    assert_equal "#{CHANGED}HEAD moved from #{BUILT} to #{look_alike}#{WHAT_TO_DO}",
                 error_after_build(head: look_alike)
  end

  def test_the_first_snapshot_names_the_commit_that_counts
    other_build = snapshot(head: MOVED_TO)

    assert_nil WORKING_COPY.error_since(other_build, snapshot(head: MOVED_TO))
    assert_equal "#{CHANGED}HEAD moved from 8a1b2c3 to e644452#{WHAT_TO_DO}",
                 WORKING_COPY.error_since(other_build, snapshot)
  end

  def test_a_snapshot_is_made_of_what_git_printed
    result = WORKING_COPY.snapshot(head_output: "#{BUILT}\n", status_output: " M a.swift\n?? b.txt\n\n")

    assert_equal BUILT, result.head
    assert_equal [" M a.swift", "?? b.txt"], result.dirty_paths
  end

  def test_a_clean_working_copy_has_no_paths
    assert_empty WORKING_COPY.snapshot(head_output: "#{BUILT}\n", status_output: "").dirty_paths
  end

  def test_the_short_commit_is_its_first_seven_characters
    assert_equal "e644452", snapshot.short_head
    assert_equal "8a1b2c3", snapshot(head: MOVED_TO).short_head
  end

  def test_listed_paths_are_cut_after_ten
    paths = (1..10).map { |i| "?? f#{i}" }

    assert_equal "?? f1", WORKING_COPY.list_paths(["?? f1"])
    assert_equal paths.join(", "), WORKING_COPY.list_paths(paths)
    assert_equal "#{paths.join(', ')} …", WORKING_COPY.list_paths(paths + ["?? f11"])
  end
end
