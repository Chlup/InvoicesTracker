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
published anywhere. To build the DMG on GitHub, and to publish it, see
[Release from GitHub](#release-from-github).

## Prerequisites

- Ruby 4.0.5 through rbenv (`.ruby-version`), then `bundle install` in the
  repository root.
- `brew install python xcbeautify`. Python 3.10 or newer runs dmgbuild, which
  makes the disk image; the lane installs dmgbuild into `build/dmg-env` on its
  first run (see [The first run](#the-first-run)).
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
intermediate files are in `build/release/`. The Python environment with dmgbuild
is in `build/dmg-env/`, outside `build/release/`, so that it outlasts the runs.
The window of the disk image (its size, the icon positions and the link to
`/Applications`) is laid out by `fastlane/dmg_settings.py`.

The lane names the commit it builds, as the seven-character short SHA: in the
`Building <short sha> …` line after the preflight, and at the end in
`DMG ready: <path> (<short sha>)`, so the run's output says which commit a DMG
was built from. The DMG itself does not carry the SHA.

The lane shows xcodebuild's output through xcbeautify. The full xcodebuild logs
are in `~/Library/Logs/scan` (the tests) and `~/Library/Logs/gym` (archive and
export).

## The first run

The lane installs dmgbuild with pip into a virtual environment in
`build/dmg-env`, from `fastlane/requirements-dmg.txt`, which pins dmgbuild and
what it needs to exact versions with their hashes. That needs network access to
PyPI, and happens again only when that file changes. Delete `build/dmg-env` to
have it installed again, for example after the Python it was made with was
removed.

macOS may ask whether `codesign` may use the Developer ID key in the login
keychain. Enter the login password and choose Always Allow.

A run that has to create or renew the profile shows two `get_provisioning_profile`
steps in fastlane's summary, the first marked 💥: that is the attempt to reuse
the profile failing, as expected, and the second one creates it.

## Release from GitHub

The workflow `.github/workflows/release.yml`, named "Release", makes the same
DMG as `bundle exec fastlane dmg` on a GitHub-hosted Mac, and can publish it. A
run builds the branch you choose and leaves the signed, notarized DMG as the
run's artifact. With the `deploy` box ticked it also publishes a GitHub release
with a signed Sparkle update feed, and installed copies of the app offer that
release as an update. The workflow commits, pushes and bumps nothing: the
version and the build number are bumped in a pull request first.

It runs the lane `ci_dmg` and, for a deploy, `sparkle_feed`. `ci_dmg` refuses to
run anywhere but on a CI runner (`CI=true`); on a Mac, use `dmg`. The build job
runs on GitHub's `xcode-27` runner (macOS 27) and selects Xcode 27.1. Runs go
one at a time: a run started while another is going waits in the queue, and none
is cancelled.

### One-time setup

You need the `gh` command-line tool, signed in (`gh auth login`) to the account
that owns the repository.

Make the environment. In the repository's Settings, open Environments and make a
new environment named `release`. Under "Deployment branches and tags" choose
"Selected branches and tags" and add `main`. The secrets live in this
environment, so a workflow file edited on another branch cannot reach them.

The environment holds six secrets:

- `DEVELOPER_ID_P12`: the Developer ID Application certificate of team
  3VN358756R with its private key, as a .p12 file in base64.
- `DEVELOPER_ID_P12_PASSWORD`: the password of that .p12 file.
- `ASC_KEY_ID`: the ID of the App Store Connect API key.
- `ASC_ISSUER_ID`: the issuer ID of that key.
- `ASC_KEY_P8`: the text of the key file, `AuthKey_<key id>.p8`.
- `SPARKLE_PRIVATE_KEY`: the Sparkle private key, as `generate_keys -x` exports
  it.

The API key is the same kind as the local lane needs: a **Team** key of team
3VN358756R whose role can register App IDs, manage provisioning profiles and
notarize.

Export the Developer ID identity. In Keychain Access, open My Certificates,
select "Developer ID Application: … (3VN358756R)" together with its private key
and choose File > Export Items…, then save it as a .p12 file with a password.
Put the file in the clipboard as base64 and set the secrets:

    base64 -i DeveloperID.p12 | pbcopy
    gh secret set DEVELOPER_ID_P12 --env release --repo Chlup/InvoicesTracker
    gh secret set DEVELOPER_ID_P12_PASSWORD --env release --repo Chlup/InvoicesTracker

`gh` asks for each value: paste the clipboard for the first, type the password
for the second. Delete the .p12 file afterwards. The App Store Connect secrets
are set the same way; `ASC_KEY_P8` is the key file itself:

    gh secret set ASC_KEY_ID --env release --repo Chlup/InvoicesTracker
    gh secret set ASC_ISSUER_ID --env release --repo Chlup/InvoicesTracker
    gh secret set ASC_KEY_P8 --env release --repo Chlup/InvoicesTracker < fastlane/AuthKey_<key id>.p8

The Sparkle key sits in the login keychain, made with `generate_keys --account
InvoicesTracker`. Export it to a file, set the secret from the file, and delete
the file:

    ~/SparkleTools/bin/generate_keys --account InvoicesTracker -x sparkle-key.txt
    gh secret set SPARKLE_PRIVATE_KEY --env release --repo Chlup/InvoicesTracker < sparkle-key.txt
    rm sparkle-key.txt

Keep a backup of the Sparkle key, in a password manager for example, before you
delete the file. Installed copies accept only updates signed with that key, so
if it is lost they can never accept another update.

### Starting a run

From the web, open the repository's Actions tab, choose "Release" in the list of
workflows and press "Run workflow". Leave "Use workflow from" on `main`: a run
from any other ref stops at its first step. Fill in the form and start it.

From a terminal:

    gh workflow run release.yml -f branch=main -f version=1.7.0 -f build=10 -f deploy=true \
      -f changelog="$(cat notes.md)"

`gh run watch` follows the run. In the form each box is labelled with its
description; the names below are the ones `gh workflow run -f` takes. What the
boxes do:

- `branch`: the branch to build, `main` by default. It only chooses what is
  built; the workflow file always comes from `main`.
- `version` and `build`: the marketing version (X.Y or X.Y.Z) and the build
  number. They must equal `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` of
  the project on that branch, or the run stops before anything slow.
- `changelog`: the release notes in Markdown. A deploy needs them: they become
  the text of the release and what Sparkle's update window shows. The box in the
  Actions form is one line, so type `\n` where a line break belongs. A text with
  real line breaks passed through `gh workflow run` keeps them.
- `skip_tests`: skips the unit tests.
- `deploy`: also publishes the release and the update feed. Without it the run
  only builds the DMG, and nothing else changes.

The run checks what it can before it builds anything slow, and reports every
problem at once: the typed numbers against the branch's, the working copy, the
tools, the API key and the Developer ID identity. A deploy also checks that the
changelog is not empty, that the tag does not exist yet, that the build number
is higher than the newest published one, and that the app's `SUFeedURL` is the
official feed address and its `SUPublicEDKey` the public half of
`SPARKLE_PRIVATE_KEY`. A branch whose app has no Sparkle cannot be deployed.

### What a run leaves

Every run, deploy or not, uploads the DMG as the run's artifact,
`InvoicesTracker-<version>-<build>.dmg`: the file itself, not a zip, signed,
notarized and stapled. It is uploaded as soon as it has passed verification, so
a deploy that fails later still leaves it. Find it at the bottom of the run's
page. The run's summary names the commit, the version and the build.

A deploy then makes the update feed, and a second job publishes the release
"InvoicesTracker <version> (<build>)": the tag `v<version>-<build>` on the built
commit, the changelog as its text, not a pre-release, with the DMG and
`appcast.xml` attached. It is created as a draft, then published and marked as
the Latest release. That is the moment installed copies can see it: they read
`https://github.com/Chlup/InvoicesTracker/releases/latest/download/appcast.xml`,
so a copy with an older build is offered the update within a day, or at once
from "Zkontrolovat aktualizace…". Each release's `appcast.xml` lists only its own
version.

### When a deploy fails

The release is a draft until the very end. If the publish job fails or is
stopped after it created the draft, it asks GitHub whether the release is still
a draft and deletes it if so, so the next run starts clean. If its log says it
could not delete the draft, or could not tell whether it is one, delete the
leftover draft on the Releases page
(https://github.com/Chlup/InvoicesTracker/releases) before you run again: a run
stops at a release or a tag of the name it wants. A release that is not a draft
any more was published; look at it before you do anything else. When the build
job fails nothing is published, and the DMG is still there if it got that far.

### Two warnings

Only the workflow should create releases. The app reads the feed from the Latest
release, so a release made by hand and marked Latest, without an `appcast.xml`,
makes the update check of every installed copy fail, and the next deploy stops
at it.

Anyone with write access can build their own branch with these secrets. The
workflow stops unless it was started from `main` by someone with admin, maintain
or write access, and only `main` can reach the `release` environment. But the
`branch` box chooses what is built, and that branch's own build scripts and
tests run on the runner, next to the signing identity and the API key. Give
write access only to people you would trust with the secrets.

### What differs on the runner

The tests are signed ad hoc, because the runner has no Apple Development
certificate: `CODE_SIGN_IDENTITY=-`, manual signing, no team and no profile. The
four suites that fail when an operation takes longer than 500 ms are left out,
because GitHub's shared runners are slower than a Mac: `InvoiceListPerformanceTests`,
`InvoiceNetIncomePerformanceTests`, `InvoiceRepositoryPerformanceTests` and
`SearchPerformanceTests`. The local lane still runs them.

The archive is signed with the Developer ID identity, from a temporary keychain
with a random password that the run deletes at the end. Only the app target is
switched to manual signing for the archive, and the project file is put back
before the working copy is checked again.

There is no `fastlane/.env` on a runner. The preflight's message about a
missing App Store Connect setting still says "is not set in fastlane/.env", but
there the values come from the secrets of the `release` environment:
`ASC_KEY_ID` and `ASC_ISSUER_ID` are the secrets of those names, and
`ASC_KEY_FILEPATH` is set by the workflow to the key file it writes from
`ASC_KEY_P8`. Look at those secrets when the message appears in a run.

## Tests

    bundle exec rake test

runs the unit tests of the helpers in `fastlane/lib/invoices_tracker/`, of
`Scripts/release.sh` and `Scripts/ci/publish-release.sh`, and checks of the
release workflow's file. Those checks run `actionlint` as well when it is
installed (`brew install actionlint`); `.github/actionlint.yaml` tells it about
the `xcode-27` runner label and the `queue` key, which its current version does
not know yet.
