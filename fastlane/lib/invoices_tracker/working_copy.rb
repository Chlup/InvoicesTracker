# frozen_string_literal: true

module InvoicesTracker
  # The working copy as git reports it at one moment, and whether it is still
  # the same later. The lane takes one snapshot in the preflight and another
  # right after the app is archived: whatever changed in between (a branch
  # switch, a stash pop, an editor's autosave) was compiled into the app, and
  # the finished DMG would pass every check while matching no commit. No I/O:
  # the lane runs git and hands over what it printed.
  module WorkingCopy
    # How much of a commit the lane shows in its output, in the "Building" and
    # "DMG ready" lines.
    SHORT_HEAD_LENGTH = 7

    # More changed paths than this are cut off, so a messy working copy does not
    # bury the rest of a message.
    MAX_LISTED_PATHS = 10

    # - `head`: the commit HEAD points at, as `git rev-parse HEAD` prints it.
    # - `dirty_paths`: the lines of `git status --porcelain --untracked-files=normal`,
    #   which lists untracked files that are not ignored as well as modified ones.
    Snapshot = Struct.new(:head, :dirty_paths, keyword_init: true) do
      def short_head
        head[0, SHORT_HEAD_LENGTH]
      end
    end

    module_function

    # `head_output` is what `git rev-parse HEAD` printed and `status_output` what
    # `git status --porcelain --untracked-files=normal` printed.
    def snapshot(head_output:, status_output:)
      Snapshot.new(head: head_output.strip, dirty_paths: status_output.lines(chomp: true).reject(&:empty?))
    end

    # Why the working copy is no longer the one `before` saw, as a message for
    # the user, or nil when `after` is the same commit with nothing uncommitted.
    #
    # `before` was taken by a preflight that stops the lane for uncommitted
    # changes, so only its commit matters. `after` has to be clean as well:
    # whatever is uncommitted in it may have been compiled into the app.
    def error_since(before, after)
      reasons = []
      reasons << head_moved(before, after) if after.head != before.head
      reasons << "uncommitted changes: #{list_paths(after.dirty_paths)}" unless after.dirty_paths.empty?
      return if reasons.empty?

      "The working copy changed while the app was being built: #{reasons.join('; ')}" \
        " — commit or stash, then run again"
    end

    # The paths as one line, cut off after MAX_LISTED_PATHS.
    def list_paths(paths)
      listed = paths.first(MAX_LISTED_PATHS).join(", ")
      paths.size > MAX_LISTED_PATHS ? "#{listed} …" : listed
    end

    # Both commits as people read them. Two different commits can share their
    # first characters; they are then given whole, so the message never says
    # that a commit moved to itself.
    def head_moved(before, after)
      from = before.short_head
      to = after.short_head
      from, to = before.head, after.head if from == to
      "HEAD moved from #{from} to #{to}"
    end
    private_class_method :head_moved
  end
end
