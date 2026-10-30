# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

InvoicesTracker is a macOS SwiftUI app that keeps a Czech sole trader's invoices and computes the year's income tax and social and health insurance. The UI is in Czech.

## Commands

Run these from the repository root.
- Every `xcodebuild` call takes `-skipMacroValidation` and `-derivedDataPath DerivedData`. `DerivedData/` is repo-local and gitignored.
- Test with the `InvoicesTracker` scheme, not `InvoicesTrackerTests`.

```bash
# All tests
xcodebuild test -project InvoicesTracker.xcodeproj -scheme InvoicesTracker -destination 'platform=macOS' \
  -derivedDataPath DerivedData -skipMacroValidation

# One suite, or one test: append to the command above (keep the parentheses; quote it in zsh)
#   -only-testing:InvoicesTrackerTests/ScreenTests
#   -only-testing:'InvoicesTrackerTests/ScreenTests/<testName>()'

# Debug build
xcodebuild build -project InvoicesTracker.xcodeproj -scheme InvoicesTracker -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData -skipMacroValidation

# Release: a signed, notarized DMG of the checked-out commit in build/ (the working copy must be clean)
./Scripts/release.sh [--skip-tests]    # runs: bundle exec fastlane dmg [skip_tests:true]
bundle exec rake test                  # tests of the fastlane helpers and of release.sh
```

`fastlane/README.md` documents the release prerequisites. `fastlane/.env` and `*.p8` hold the App Store Connect key:
- never read them (`.claude/settings.json` denies it);
- never search recursively in `fastlane/`.

### Full-suite results that are not regressions

- One expected failure in `WaitingHelperTests`.
- `AppWindowLayoutTests.aWheelOverTheClientTableScrollsThePageUpAndDownAndTheTableSideways` fails whenever the Mac's screen is locked. Check with `ioreg -n Root -d1 -a | grep -A1 CGSSessionScreenIsLocked`.
- `InvoiceListPerformanceTests` is load-sensitive. Re-run it alone before believing a failure.

## Architecture

The app target is Swift 6 with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so pure value types, enums and builders are declared `nonisolated`. The packages are SQLCipher and Sparkle (linked to the app target only). Both targets use file-system synchronized groups, so a new `.swift` file needs no project edit.

The code is layered, bottom to top:

- **Storage** (`Storage/`):
  - **Database.** `actor Database` runs on raw sqlite3 with SQLCipher (`SQLite/SQLiteConnection.swift`). Its `write {}` is a transaction. Repositories are `extension Database` in `Storage/Repositories/`.
  - **Schema.** `Schema.migrations` is versioned with `PRAGMA user_version`. A schema change is a new `Migration`, applied in one transaction. Databases and backups of older versions migrate when opened or restored; newer data is refused. Backups (`Storage/Backup/`) carry their schema version.
  - **Files.** `Vault` owns the data folder in Application Support, plus an optional backup folder outside the Mac. The folder holds:
    - `InvoicesTracker.sqlite`;
    - `InvoicesTracker.keys`, the wrapped key (`Storage/Keys/`: Secure Enclave, recovery code);
    - `Backups/`.
  - **Settings.** App settings are JSON rows in the database's `app_settings` table. UserDefaults holds only the idle-lock mirror and Sparkle's own settings (the daily-check switch and the last check time), because the updater starts before the data are unlocked.
- **Domain** (`Domain/`), models and values:
  - money is `Int64` haléře, or whole Kč where the name says so;
  - dates are `CivilDate`, which has no time zone;
  - displayed numbers and dates go through `CzechFormat`, which adds the Czech no-break spaces.
- **TaxEngine** (`TaxEngine/`), pure:
  - `YearInput` holds receipts, months of activity, deductions, family and planned advances. `TaxEngine.compute(_:asOf:)` turns it into a `TaxResult`: tax, social, health, the balance per authority and the marginal levy.
  - The rules of each year are in `TaxRules+Years.swift`.
  - Call the engine through `AppModel.compute(_:asOf:)`, which validates the input first.
  - Minimum insurance counts the active months through the as-of month.
- **Prediction** (`Prediction/`), pure. It predicts a year's whole income client by client, and feeds the predicted payments to the engine as synthetic receipts, computed as of 31 Dec. `AppModel.predictionOutcome(year:)` loads it, always from today's data and never from K datu.
- **Feature services**, used by the models:
  - `ExchangeRates/`: ČNB daily rates, and the GFŘ uniform rate of a year;
  - `Import/`: Fakturoid CSV import;
  - `Invoices/`: numbering, PDF and the QR payment code;
  - `Search/`.
- **Updates** (`Updates/`). Sparkle 2 updates the app from the feed `https://github.com/Chlup/InvoicesTracker/releases/latest/download/appcast.xml`:
  - the feed URL must keep working for every installed version, so it never moves, and only the release workflow publishes releases;
  - the public key (`SUPublicEDKey`) is committed. The appcast and every archive must be signed with its private half, which is never committed (`SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction`);
  - Sparkle's keys are in the partial `InvoicesTracker-Info.plist` at the repository root. Xcode merges it with the generated Info.plist, and it stays outside the synchronized `InvoicesTracker/` folder so that it is not copied into the app. The sandbox exception for Sparkle's installer is in `InvoicesTracker.entitlements`;
  - `AppUpdater` starts Sparkle's updater once at launch, never under the test host, and is its delegate. It is the only code that imports Sparkle: the app reaches the updater through `AppModel.updates` (nil in tests, which use `FakeUpdater`), an `UpdatesModel` that mirrors an `AppUpdating`;
  - Debug builds refuse the updater's daily check in the background (`UpdateCheckPolicy`). A check the person asks for runs in every build.
- **App** (`App/`):
  - `AppModel` is `@MainActor @Observable`, split across `AppModel+*.swift`. It holds:
    - the unlocked database and the selected screen;
    - `asOf`, the toolbar's "K datu": the year and day the screens compute as of (`AsOfState`);
    - `today`;
    - the app-wide state.
  - `AppDependencies` injects the clock, time zone, network and system services, so tests run at a fixed day.
- **UI** (`UI/<Screen>/`):
  - **Per screen:** a `<Name>Screen` view; a `@MainActor @Observable final class <Name>Model`; and a pure `<Name>Builder` that turns loaded data into `<Name>Data`, which carries every displayed text.
  - **Loading.** Screens load in `.task(id: app.reloadKey)` and publish only the newest load. Odhad odvodů and Přehled also reload when `today` changes.
  - **Writes.** A write calls `await app.didWrite()`, which changes `reloadKey` and schedules backups.
  - **Where things live.** Navigation is `Screen` plus `UI/Root/` (sidebar, toolbar, root view); shared layouts and parts are in `UI/Shared/`.

`Resources/Localizable.xcstrings` (source language cs) gets its entries from the Xcode build. Feature work does not edit it by hand.

## Tests

Swift Testing, with sentence-style test names. Conventions that are easy to miss:

- **App-model suites** are `@Suite(.settlesBackups) @MainActor`. `.settlesBackups` waits for the backups a test's writes start, so no temporary folder is left behind.
- **Window tests** host real windows (`withAppWindow`, `AppWindowSize.minimum` / `.large`), check layout through the accessibility tree, and are `.serialized`. A test that types into a field, or checks focus, runs inside `whileTypingAlone`.
- **No-break spaces** are spelled `\u{00A0}` in expectations.
- **Golden tests** pin the engine (`TaxEngine*Tests`) and the prediction (`PredictionGoldenTests`, `PredictionSample`) to the haléř. Their figures come from an independent calculation, so a mismatch is a finding, not an expectation to update.

## Style

- Lines wrap at 120 columns.
- Almost every type and function has a doc comment that describes its behaviour in full sentences. New code does the same.

## UI design system

Every screen follows one design system. New and changed UI follows these rules.

The detailed reference is the "Reference – V2" page of the design canvas "InvoicesTracker", a private claude.ai
artifact of the repository's owner. Claude sessions find it by that name with the Artifact tool's `list` action and
read it with the `read` action, passing a file's `path`. Two files there apply:

- `project/DesignSystemV2.dc.html`, the design system board: tokens, type, components, screen layouts and glossary.
- `project/PrototypV2.dc.html`, the clickable prototype of every screen and dialog. Its markup and script hold every
  displayed text and how each number is formatted. Its calculations are a mock-up: the app's numbers come from
  `TaxEngine` and `Prediction`.

The canvas's other pages are older explorations and do not apply. Where the canvas and this section disagree, ask the
user before building.

- **Screen types.** Each screen is one of three:
  - **List with detail** (Faktury, Odběratelé): one row above the table card (the filters on Faktury, the add button on
    Odběratelé); the table card, with a summary row on top (count and totals); a detail panel on the right. A click on a
    row opens the detail; a second click or ✕ closes it.
  - **Report** (Výpočet, Odhad odvodů, Simulátor):
    - a result card: the key figure on the left and the levy bar on the right, with any further figures in a
      full-width row under a hairline;
    - cards with side facts (Výpočet: Mezní odvod and Hranice roku; Odhad odvodů: Příjmy);
    - a note on what the numbers are based on;
    - "Rozpis výpočtu", with the bill cards in two columns.

    The Simulátor keeps its inputs on the left and the result on the right.
  - **Dashboard** (Přehled), which starts with the same result card as the reports.

  A screen's title is its sidebar label. The toolbar has no control for the day: the current year counts money received
  through today and invoices issued through the end of the month, and another year is shown as a whole. The sidebar
  shows the app version under Nastavení.
- **Colour.**
  - Views use only the colour tokens from the asset catalog, never literal colours:
    - text;
    - backgrounds;
    - separators;
    - accent;
    - green, orange and red, each with text and tint variants;
    - tax, social and health.
  - Each status colour has one meaning: blue is action and information, green is paid and your money, orange is an
    estimate or attention, and red is overdue or an error.
- **Type.** Only the macOS text styles: largeTitle 26, title 22, title2 17, title3 15, headline 13, body 13, callout 12
  and subheadline 11. The one exception is the display size (44, bold, rounded) for a screen's key figure. No other
  `.font(.system(size:))`.
- **Shape and spacing.**
  - Radii: card 16, panel 10, control 6, and a capsule for pills and every filled button.
  - A 4-point grid: cards are padded 20, sit 16 apart, and use 12 inside.
- **Components.** Use the shared view for each job (in `UI/Shared/`):
  - card;
  - key figure;
  - levy bar: one bar split into three solid parts in the authorities' colours, each as wide as its levy; short names
    and amounts under it. The advances and what is left to pay appear only in the popover on hover or focus;
  - figure tile: label, figure and note. Tiles sit next to each other with one gap and are never stretched into
    columns across the card;
  - table: a 32-point header and 40-point rows with one line of text each; further details belong in the detail panel;
  - pill;
  - note (info, estimate, success, warning);
  - bill row;
  - buttons: 32 for page and toolbar actions, 28 inside cards, segments and filters.

  Selection always uses the accent.
- **Words.** Use these terms: Odvody (daň + sociální + zdravotní), Zálohy, Zbývá zaplatit, Doplatek / Přeplatek,
  Čistý příjem, Mezní odvod, Odhad. Authorities get their full names in rows (Daň z příjmů, Sociální pojištění,
  Zdravotní pojištění) and short ones in inline splits.
- **Numbers.**
  - Whole Kč in summaries, charts and tooltips; haléře only on invoice amounts and in bills.
  - Percentages have one decimal. The levy share of income stands right next to a levy total.
  - A card never shows the same number twice.
  - "≈" marks only a lone estimate among actual values: an unpaid invoice, or a conversion at the issue rate. It is
    never used inside an area already marked as an estimate.
- **Invoices.** A paid invoice is not edited, only its payment ("Upravit platbu"). Removing a payment is possible but
  deliberately hard: the person types the invoice number to confirm, and the invoice can then be edited again.
