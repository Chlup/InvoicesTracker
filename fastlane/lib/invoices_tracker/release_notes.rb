# frozen_string_literal: true

module InvoicesTracker
  # The release notes typed for a release, made ready to publish. The text may
  # hold a typed backslash and `n` where a line break is meant, and CRLF line
  # endings. Only the text is changed: nothing here runs it, so shell characters
  # stay as they are. No I/O.
  module ReleaseNotes
    module_function

    # The notes as they are published: UTF-8 whatever encoding `text` arrives in,
    # since a CI runner's locale may not be UTF-8. A line break replaces each
    # CRLF, each CR and each typed `\n`. Trailing spaces are removed from every
    # line, blank lines at either end are dropped, and blank lines in between
    # are kept. Nil or blank text gives "". A non-empty result ends with exactly
    # one line break.
    def normalize(text)
      lines = text.to_s.dup.force_encoding(Encoding::UTF_8)
                  .gsub("\\n", "\n")
                  .gsub(/\r\n?/, "\n")
                  .split("\n")
                  .map(&:rstrip)
      first = lines.index { |line| !line.empty? }
      return "" unless first

      last = lines.rindex { |line| !line.empty? }
      "#{lines[first..last].join("\n")}\n"
    end

    # The problems that keep these notes out of a release, empty when they are
    # fine. A deploy publishes the notes, so it needs some; a dry run that only
    # builds may go without.
    def errors(text, deploy:)
      return [] unless deploy && normalize(text).empty?

      ["the changelog is empty — a deploy needs release notes"]
    end
  end
end
