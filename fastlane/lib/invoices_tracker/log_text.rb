# frozen_string_literal: true

module InvoicesTracker
  # Text made safe to print as part of one line of a lane's output. A GitHub
  # Actions runner reads every line a step prints, and acts on a line that
  # starts with `::` (after any spaces) as a workflow command, such as
  # `::error::`, `::add-mask::` or `::stop-commands::`, and on `##[` anywhere in
  # a line as a command in the older form. Typed values such as the version
  # reach the lane's messages, so a typed line break followed by `::` could
  # start a command. The lane prints such text only after words of its own, so
  # keeping it on one line keeps it from starting one. No I/O.
  module LogText
    # The characters that end a line, or that a terminal acts on, none of which
    # belongs inside one line of a message: the C0 controls except the tab, DEL,
    # and Unicode's next line, line separator and paragraph separator.
    CONTROL = /[\x00-\x08\x0A-\x1F\x7F\u0085  ]/

    # How a workflow command in the older form starts, and what it is printed
    # as instead: the second `#` written as the escape of its code.
    OLDER_COMMAND = "##["
    OLDER_COMMAND_SHOWN = "#\\x23["

    module_function

    # `text` as one line: each character of `CONTROL` written as its escape,
    # the way Ruby writes it in a string literal (`\n`, `\r`, `\e`, ` `),
    # and `##[` as `#\x23[`. Ordinary text comes back as it is. Any value is
    # turned into text first, and bytes that are not UTF-8 become U+FFFD. The
    # text passed in is not changed.
    def line(text)
      text.to_s.dup.force_encoding(Encoding::UTF_8).scrub
          .gsub(CONTROL) { |character| character.dump[1...-1] }
          .gsub(OLDER_COMMAND, OLDER_COMMAND_SHOWN)
    end
  end
end
