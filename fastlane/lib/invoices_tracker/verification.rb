# frozen_string_literal: true

module InvoicesTracker
  # Judges what the macOS tools print about a finished disk image. Each method
  # takes the text of one tool and returns the problems it shows, empty when the
  # check passes. No I/O: callers run the tools and pass their output. spctl and
  # codesign write to stderr, so the output handed in must include that stream.
  module Verification
    module_function

    # Output of `spctl --assess --type open --context context:primary-signature
    # -vvv <path>`. Both parts are required: an image that is merely signed with
    # a Developer ID is not enough, the release has to be notarized. The verdict
    # must also be about `path`, not about some other file.
    def gatekeeper_errors(spctl_output, path:)
      lines = spctl_output.lines.map(&:strip)
      return [] if lines.include?("#{path}: accepted") && spctl_output.include?("source=Notarized Developer ID")

      first_line = lines.find { |line| !line.empty? } || "no output"
      ["Gatekeeper does not accept #{path} as notarized Developer ID: #{first_line}"]
    end

    # Output of `xcrun stapler validate <path>`. The ticket stapled into the
    # image is what lets it open on a Mac that is offline.
    def staple_errors(stapler_output, path:)
      return [] if stapler_output.include?("The validate action worked!")

      ["#{path} has no valid notarization ticket stapled"]
    end

    # Output of `codesign -dv --verbose=2 <path>`. The team is read from the
    # TeamIdentifier line and has to match whole: the "Authority" lines name a
    # team too, and an identifier that merely starts like the team's is another
    # team.
    def team_errors(codesign_output, path:, team_id:)
      lines = codesign_output.lines.map(&:strip)
      return [] if lines.include?("TeamIdentifier=#{team_id}")

      found = lines.find { |line| line.start_with?("TeamIdentifier=") } || "no TeamIdentifier"
      ["#{path} is not signed by team #{team_id} (#{found})"]
    end
  end
end
