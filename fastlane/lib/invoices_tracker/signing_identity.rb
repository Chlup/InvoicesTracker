# frozen_string_literal: true

module InvoicesTracker
  # Picks the identity to sign the release with out of the listing that
  # `security find-identity -v -p codesigning` prints. Pure parsing with no I/O;
  # callers run the command and pass its output.
  module SigningIdentity
    Identity = Struct.new(:sha1, :name, keyword_init: true)

    # `identity` is set exactly when `error` is nil.
    Result = Struct.new(:identity, :error, keyword_init: true) do
      def ok?
        error.nil?
      end
    end

    # One listed identity: `  1) <40 hex digits> "<name>"`. The closing quote
    # has to end the line, so a line that carries anything after the name, such
    # as a certificate-status note, is not taken for an identity.
    LISTED_IDENTITY = /^\s*\d+\)\s+([0-9A-F]{40})\s+"(.+)"$/

    NAME_PREFIX = "Developer ID Application: "

    module_function

    # Finds the Developer ID Application certificate of `team_id`. The team is
    # told by the "(TEAMID)" that ends the certificate name: the keychain also
    # holds other teams' Developer ID certificates, and signing with one of
    # those would make Gatekeeper attribute the image to someone else.
    #
    # A certificate that sits in several keychains is listed once per keychain
    # with the same SHA-1 and counts once. Two different certificates of the team
    # are an error, because picking either one would be a guess.
    def developer_id(find_identity_output, team_id:)
      listed = find_identity_output.each_line(chomp: true).filter_map do |line|
        match = LISTED_IDENTITY.match(line)
        Identity.new(sha1: match[1], name: match[2]) if match
      end
      teams = listed.select { |identity| developer_id_of?(identity.name, team_id) }.uniq(&:sha1)

      case teams.size
      when 1
        Result.new(identity: teams.first, error: nil)
      when 0
        Result.new(identity: nil,
                   error: "no valid 'Developer ID Application' identity for team #{team_id} in the keychain")
      else
        Result.new(identity: nil,
                   error: "several 'Developer ID Application' identities for team #{team_id} in the keychain: " \
                          "#{teams.map(&:name).join(', ')}")
      end
    end

    def developer_id_of?(name, team_id)
      name.start_with?(NAME_PREFIX) && name.end_with?("(#{team_id})")
    end
    private_class_method :developer_id_of?
  end
end
