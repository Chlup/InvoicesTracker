# frozen_string_literal: true

module InvoicesTracker
  # The fixed facts about the app and the developer account it is released under.
  module Release
    # The Apple developer team that owns the app. Signing picks this team's
    # Developer ID identity by its SHA-1: the keychain also holds another
    # team's Developer ID, so matching on the bare name "Developer ID
    # Application" would be ambiguous.
    TEAM_ID = "3VN358756R"

    BUNDLE_ID = "info.chlup.InvoicesTracker"

    # Product name of the app target. It names the .app, the archive and the
    # disk image volume.
    APP_NAME = "InvoicesTracker"

    PROJECT = "InvoicesTracker.xcodeproj"
    SCHEME = "InvoicesTracker"

    # Name of the Developer ID provisioning profile. The profile is looked up
    # and replaced by this exact name, so renewing it never leaves copies with
    # a timestamp appended.
    PROFILE_NAME = "InvoicesTracker Developer ID"
  end
end
