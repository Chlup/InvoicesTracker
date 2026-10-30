# frozen_string_literal: true

module InvoicesTracker
  # Builds the commands that produce the distributable disk image: a standard
  # drag-to-Applications window with the app icon on the left and a link to
  # /Applications on the right. Pure argv construction with no I/O, so the
  # layout is unit-testable; callers run the arrays without a shell.
  module Dmg
    module_function

    # Named after the app it contains, so the download matches what the user
    # installs: " Invoices  Tracker " -> "Invoices-Tracker-1.2.3-45.dmg".
    def filename(app_name:, version:, build:)
      "#{app_name.strip.gsub(/\s+/, '-')}-#{version}-#{build}.dmg"
    end

    # `app_bundle` is the file name of the app as it appears inside
    # `source_dir`, which must contain ONLY the app bundle: create-dmg turns the
    # whole folder into the volume. `volicon` (an .icns file) is optional; nil
    # leaves the volume with the default icon, which is what an app without an
    # icon needs.
    def create_dmg_command(app_bundle:, source_dir:, dmg_path:, volname:, volicon: nil)
      command = ["create-dmg", "--volname", volname]
      command += ["--volicon", volicon] if volicon
      command + [
        "--window-pos", "200", "120",
        "--window-size", "600", "400",
        "--icon-size", "128",
        "--icon", app_bundle, "150", "190",
        "--app-drop-link", "450", "190",
        "--hide-extension", app_bundle,
        dmg_path, source_dir
      ]
    end

    # `identity` has no default on purpose. Pass the SHA-1 of the team's own
    # Developer ID certificate: codesign accepts a partial name match, and the
    # keychain also holds another team's Developer ID, so a bare "Developer ID
    # Application" could sign with the wrong one.
    def codesign_command(path:, identity:)
      ["codesign", "--sign", identity, "--timestamp", "--force", path]
    end
  end
end
