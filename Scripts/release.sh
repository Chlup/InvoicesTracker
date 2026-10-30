#!/usr/bin/env bash
set -euo pipefail

# fastlane needs a UTF-8 locale; a locale the caller already has is kept.
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# Always run from the repository root, wherever the script is called from.
cd "$(dirname "$0")/.."

usage() {
  cat <<'EOF'
Usage: Scripts/release.sh [--skip-tests]

Builds the signed, notarized InvoicesTracker disk image of the checked-out
branch with the fastlane `dmg` lane. The result is
build/InvoicesTracker-<version>-<build>.dmg.

  --skip-tests  skip the unit-test step
  -h, --help    show this help
EOF
}

SKIP_TESTS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tests) SKIP_TESTS=true ; shift ;;
    -h|--help) usage ; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2 ; usage >&2 ; exit 2 ;;
  esac
done

# FASTLANE_CMD replaces the command that runs fastlane (the tests use it). It
# is left unquoted on purpose, so a command with arguments splits into words.
FASTLANE="${FASTLANE_CMD:-bundle exec fastlane}"
exec $FASTLANE dmg skip_tests:"$SKIP_TESTS"
