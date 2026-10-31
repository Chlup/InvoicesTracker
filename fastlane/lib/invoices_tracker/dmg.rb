# frozen_string_literal: true

module InvoicesTracker
  # Builds the commands that produce the distributable disk image: a standard
  # drag-to-Applications window with the app icon on the left and a link to
  # /Applications on the right. dmgbuild makes the image and writes the window
  # layout into it without driving Finder; the layout itself is in
  # fastlane/dmg_settings.py. Pure argv construction with no I/O, so the
  # commands are unit-testable; callers run the arrays without a shell.
  module Dmg
    module_function

    # Named after the app it contains, so the download matches what the user
    # installs: " Invoices  Tracker " -> "Invoices-Tracker-1.2.3-45.dmg".
    def filename(app_name:, version:, build:)
      "#{app_name.strip.gsub(/\s+/, '-')}-#{version}-#{build}.dmg"
    end

    # The dmgbuild command that makes the disk image `dmg_path`, named `volname`
    # as a volume, from the app bundle at `app` and the layout of the dmgbuild
    # settings file `settings`. `dmgbuild` is the path of the executable. The app
    # and the volume icon reach the settings file as its defines: dmgbuild copies
    # the app into the image with ditto, so its signature and stapled ticket
    # survive, and nothing else of the folder the app is in goes along.
    # `volicon` (an .icns file) is optional; nil leaves the volume with the
    # default icon, which is what an app without an icon needs.
    def dmgbuild_command(dmgbuild:, settings:, app:, dmg_path:, volname:, volicon: nil)
      command = [dmgbuild, "-s", settings, "-D", "app=#{app}"]
      command += ["-D", "volicon=#{volicon}"] if volicon
      command + [volname, dmg_path]
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
