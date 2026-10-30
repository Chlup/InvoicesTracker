# Release: the signed, notarized DMG

`bundle exec fastlane dmg` turns the checked-out commit into a disk image that
opens on any Mac without a Gatekeeper warning, even offline. It first checks,
without contacting Apple, that the working copy is clean (untracked files
count), the tools and settings are there, the Developer ID identity of team
3VN358756R is in the keychain and the project's version is usable. Then it runs
the unit tests, registers the App ID if needed, reuses or renews the
`InvoicesTracker Developer ID` provisioning profile, archives the app, exports
it signed with that identity, checks that the working copy is still the clean
one it started from, notarizes and staples the app, puts it in a
drag-to-Applications disk image, signs, notarizes and staples the image, and
verifies the image and the app. The version and build number come from the
Xcode project; nothing is bumped, committed or tagged, and the DMG is not
published anywhere.

## Prerequisites

- Ruby 4.0.5 through rbenv (`.ruby-version`), then `bundle install` in the
  repository root.
- `brew install create-dmg xcbeautify`
- The Developer ID Application certificate of team 3VN358756R, with its private
  key, in the login keychain.
- `fastlane/.env`, copied from `fastlane/.env.example` and filled in, with the
  App Store Connect API key (`AuthKey_<key id>.p8`) beside it in `fastlane/`.
  Both are gitignored. fastlane's own `APP_STORE_CONNECT_API_KEY_*` names for
  the three settings work as well. The key must be an App Store Connect API
  **Team** key of team 3VN358756R whose role can register App IDs, manage
  provisioning profiles and notarize (Admin covers all three); a key whose role
  is too low fails a few minutes into the run with Apple's bare 403.

## Usage

From the repository root, with everything committed:

    bundle exec fastlane dmg [skip_tests:true]
    ./Scripts/release.sh [--skip-tests]

`skip_tests:true` and `--skip-tests` skip the unit tests. Uncommitted changes
stop the lane before anything is built. The lane checks the working copy again
right after the app is archived: if HEAD has moved or a file has changed since
the preflight, it stops before any DMG exists, because the app would then match
no commit. Commit or stash, then run it again. The committed
`fastlane/.env.default` turns off fastlane's update check, whose banner would
bury the lane's result.

## Output

`build/InvoicesTracker-<version>-<build>.dmg`, for example
`build/InvoicesTracker-1.0-1.dmg`. A DMG of that name is deleted when a run
starts, and the new one appears only once it has passed verification, so a
failed run leaves none. The archive, the exported app and the other
intermediate files are in `build/release/`.

The lane names the commit it builds, as the seven-character short SHA: in the
`Building <short sha> …` line after the preflight, and at the end in
`DMG ready: <path> (<short sha>)`, so the run's output says which commit a DMG
was built from. The DMG itself does not carry the SHA.

The lane shows xcodebuild's output through xcbeautify. The full xcodebuild logs
are in `~/Library/Logs/scan` (the tests) and `~/Library/Logs/gym` (archive and
export).

## The first run

macOS may ask:

- whether `codesign` may use the Developer ID key in the login keychain. Enter
  the login password and choose Always Allow.
- whether the app that runs the lane (Terminal, iTerm, ...) may control Finder,
  which create-dmg uses to lay out the disk image window. Allow it; it can be
  changed later in System Settings → Privacy & Security → Automation.

A run that has to create or renew the profile shows two `get_provisioning_profile`
steps in fastlane's summary, the first marked 💥: that is the attempt to reuse
the profile failing, as expected, and the second one creates it.

## Tests

    bundle exec rake test

runs the unit tests of the helpers in `fastlane/lib/invoices_tracker/` and of
`Scripts/release.sh`.
