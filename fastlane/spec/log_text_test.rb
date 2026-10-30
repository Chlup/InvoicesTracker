# frozen_string_literal: true

require "minitest/autorun"
require "invoices_tracker/log_text"

class InvoicesTrackerLogTextTest < Minitest::Test
  def line(text)
    InvoicesTracker::LogText.line(text)
  end

  def test_ordinary_text_is_left_as_it_is
    message = "the branch's MARKETING_VERSION is 1.6.0, not the typed 1.7.0 — bump it in a PR first"

    assert_equal message, line(message)
    assert_equal "tabs\tstay", line("tabs\tstay")
  end

  # A typed line break followed by `::` would make the runner read the rest
  # as a workflow command.
  def test_line_breaks_are_shown_as_escapes_so_no_new_line_can_start
    assert_equal "the typed version '1.0\\n::error::boom' is not X.Y or X.Y.Z",
                 line("the typed version '1.0\n::error::boom' is not X.Y or X.Y.Z")
    assert_equal "a\\r::add-mask::b\\r\\nc", line("a\r::add-mask::b\r\nc")
  end

  def test_unicode_line_separators_and_other_controls_are_escaped_too
    assert_equal "a\\u2028b\\u2029c\\u0085d", line("a b c\u0085d")
    assert_equal "bell\\a esc\\e[31m nul\\x00 del\\x7F vt\\v ff\\f", line("bell\a esc\e[31m nul\0 del\x7F vt\v ff\f")
  end

  # The older form of a workflow command, `##[name]`, counts anywhere in a
  # line, not only at its start.
  def test_the_older_command_form_is_broken_up
    assert_equal "typed '#\\x23[add-mask]1.0'", line("typed '##[add-mask]1.0'")
    refute_includes line("x ##[error]y ##[warning]z"), "##["
  end

  def test_every_result_is_one_line_without_a_command
    hostile = "1.0\n::stop-commands::t\r\n  ::error::x ::warning::y ##[error]z"
    result = line(hostile)

    assert_equal 1, result.lines.size
    refute_match(/[\r\n  \u0085]/, result)
    refute_includes result, "##["
  end

  def test_bytes_that_are_not_utf8_do_not_break_it
    assert_equal "caf�\\n", line("caf\xE9\n".b)
  end

  def test_nil_and_other_values_become_text
    assert_equal "", line(nil)
    assert_equal "42", line(42)
  end

  def test_the_text_passed_in_is_not_changed
    text = +"a\nb"
    line(text)

    assert_equal "a\nb", text
  end
end
