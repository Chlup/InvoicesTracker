# frozen_string_literal: true

require "minitest/autorun"
require "invoices_tracker/release_notes"

class InvoicesTrackerReleaseNotesTest < Minitest::Test
  def test_normalize_turns_a_typed_backslash_n_into_a_new_line
    assert_equal "- Oprava\n- Nová funkce\n",
                 InvoicesTracker::ReleaseNotes.normalize("- Oprava\\n- Nová funkce")
  end

  def test_normalize_drops_carriage_returns_trailing_spaces_and_blank_edges
    assert_equal "  - a\nb\n", InvoicesTracker::ReleaseNotes.normalize("\r\n\n  - a  \r\nb\r\n\n")
  end

  def test_normalize_turns_a_lone_carriage_return_into_a_new_line
    assert_equal "- a\n- b\n", InvoicesTracker::ReleaseNotes.normalize("- a\r- b")
  end

  def test_normalize_keeps_blank_lines_between_paragraphs
    assert_equal "- a\n\n- b\n", InvoicesTracker::ReleaseNotes.normalize("- a\r\n\r\n- b")
  end

  def test_normalize_of_nothing_is_empty
    assert_equal "", InvoicesTracker::ReleaseNotes.normalize(nil)
    assert_equal "", InvoicesTracker::ReleaseNotes.normalize("  \\n  ")
  end

  def test_normalize_keeps_czech_text_in_utf8
    out = InvoicesTracker::ReleaseNotes.normalize("Příliš žluťoučký kůň")

    assert_equal "Příliš žluťoučký kůň\n", out
    assert_equal Encoding::UTF_8, out.encoding
  end

  def test_normalize_reads_bytes_in_another_encoding_as_utf8
    out = InvoicesTracker::ReleaseNotes.normalize("Příliš žluťoučký kůň".b)

    assert_equal "Příliš žluťoučký kůň\n", out
    assert_equal Encoding::UTF_8, out.encoding
  end

  def test_normalize_leaves_shell_syntax_as_text
    assert_equal "$(touch pwned) `id` \"q\"; x\n",
                 InvoicesTracker::ReleaseNotes.normalize("$(touch pwned) `id` \"q\"; x")
  end

  def test_a_deploy_needs_notes
    assert_equal ["the changelog is empty — a deploy needs release notes"],
                 InvoicesTracker::ReleaseNotes.errors(" ", deploy: true)
  end

  def test_a_dry_run_goes_without_notes
    assert_equal [], InvoicesTracker::ReleaseNotes.errors("", deploy: false)
  end

  def test_notes_with_text_have_no_errors
    assert_equal [], InvoicesTracker::ReleaseNotes.errors("- x", deploy: true)
  end
end
