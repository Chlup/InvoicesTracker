#!/usr/bin/env bash
# Publishes the release that the build job left in a feed folder: the moment
# it is done, installed apps are offered the update. See usage() for what it
# does and what it needs.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: Scripts/ci/publish-release.sh <feed-dir>

Publishes the release that the build job left in <feed-dir> as the Latest
release of the repository. release.json in the folder names the other files:
the disk image, the release notes, and appcast.xml, the update feed.

The release is created as a draft with the disk image and appcast.xml attached,
and only then published and marked Latest, the moment installed apps are
offered the update. The script stops before it creates anything when a file
does not match its SHA-256 in release.json, when a release or a git tag of that
name exists, or when the Latest release is not the one the build saw. A run
that fails after the draft was created deletes that draft, and nothing else.

Environment:
  GITHUB_REPOSITORY    the repository as owner/name (required)
  GH_TOKEN             the token gh signs in with (only gh reads it)
  GH                   a program to run in place of gh (the tests use it)
  GITHUB_STEP_SUMMARY  a file to append a summary of the published release to
EOF
}

# The exit trap deletes the draft release when CREATE_ATTEMPTED is set and
# PUBLISHED is not: the draft may exist, and nobody has seen it.
CREATE_ATTEMPTED=false
PUBLISHED=false

# The file that holds what gh prints on standard error, and what the last call
# of call_gh printed on standard output and on standard error.
STDERR_FILE=""
GH_OUT=""
GH_ERR=""

# Prints the reason and ends the run with status 1. A value read from
# release.json is printed only after it was checked or through printable_tag,
# and the title is not printed at all: a line of the log that starts with ::
# would be taken for a command of the workflow.
fail() {
  echo "error: $*" >&2
  exit 1
}

# Runs on every exit. When the draft release may exist and was not published,
# deletes it, and keeps the status the run ends with.
cleanup() {
  local status=$?
  if [[ $CREATE_ATTEMPTED == true && $PUBLISHED != true ]]; then
    discard_draft
  fi
  if [[ -n $STDERR_FILE ]]; then
    rm -f "$STDERR_FILE"
  fi
  exit "$status"
}

# Deletes the release of the tag, which is the draft this run made: the checks
# before it found no release of that name. A draft that cannot be deleted is
# reported with where to delete it by hand, because the next run stops at it.
discard_draft() {
  local status=0
  echo "Deleting the draft release $TAG, which was not published..."
  call_gh release delete "$TAG" --repo "$REPO" --yes || status=$?
  if [[ $status -eq 0 ]]; then
    echo "Deleted the draft release $TAG."
  elif [[ $GH_ERR == *"release not found"* ]]; then
    echo "There was no draft release $TAG to delete."
  else
    echo "error: could not delete the draft release $TAG$(http_status)." \
      "Delete it at https://github.com/$REPO/releases before the next run." >&2
  fi
}

# Runs gh with the arguments. Its standard output goes to GH_OUT and its
# standard error to GH_ERR, and the status it ends with is the status of the
# function. Only the calls that ask a question go through here: the answer to
# one tells a release that is not there from a call that failed.
call_gh() {
  local status=0
  GH_OUT=$("$GH_CMD" "$@" 2>"$STDERR_FILE") || status=$?
  GH_ERR=$(<"$STDERR_FILE")
  return "$status"
}

# The HTTP status that gh printed for the call that just failed, as " (HTTP
# 502)", and nothing when it printed none.
http_status() {
  local pattern='HTTP ([0-9]{3})'
  if [[ $GH_ERR =~ $pattern ]]; then
    echo " (HTTP ${BASH_REMATCH[1]})"
  fi
}

# Stops after a gh call that failed in a way the script has no use for. The
# call and its HTTP status are reported and nothing else of what gh printed,
# which may be the body of the response.
fail_gh_call() {
  fail "gh $* failed$(http_status)"
}

# A tag for a message: "none" for no tag, else the tag with every character
# that a tag has no use for replaced by ?, because one of the two tags that the
# message compares comes from release.json.
printable_tag() {
  local unsafe='[^A-Za-z0-9._-]'
  if [[ -z $1 ]]; then
    echo "none"
  else
    echo "${1//$unsafe/?}"
  fi
}

# read_manifest NAME KEY sets the variable NAME to the text value of KEY in
# release.json, and stops when the key is missing or its value is no text.
read_manifest() {
  local value
  value=$(jq -er --arg key "$2" '.[$key] | strings' "$MANIFEST" 2>/dev/null) ||
    fail "release.json has no text value for \"$2\""
  printf -v "$1" '%s' "$value"
}

# verify_checksum NAME SHA256 stops unless the SHA-256 of the file NAME in the
# feed folder is the one release.json gives.
verify_checksum() {
  local name=$1 expected=$2 actual
  actual=$(shasum -a 256 "$FEED_DIR/$name") || fail "cannot read the SHA-256 of $name"
  actual=${actual%% *}
  [[ $actual == "$expected" ]] || fail "$name does not match its SHA-256 in release.json"
}

# Appends the published release to the summary of the job, when there is one.
write_summary() {
  [[ -n ${GITHUB_STEP_SUMMARY:-} ]] || return 0
  {
    echo "### Published $TAG"
    echo
    echo "$RELEASE_URL"
    echo
    echo "It is the Latest release, so installed apps are offered the update."
  } >>"$GITHUB_STEP_SUMMARY" || echo "warning: could not write the summary of the job" >&2
}

# --- the arguments and the environment ---------------------------------------

if [[ $# -ge 1 ]]; then
  case "$1" in
    -h|--help) usage ; exit 0 ;;
    -*) echo "error: unknown argument: $1" >&2 ; usage >&2 ; exit 2 ;;
  esac
fi
if [[ $# -ne 1 ]]; then
  echo "error: expected the feed folder as the one argument" >&2
  usage >&2
  exit 2
fi
FEED_DIR=${1%/}

REPO=${GITHUB_REPOSITORY:-}
repo_pattern='^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$'
[[ $REPO =~ $repo_pattern ]] || fail "GITHUB_REPOSITORY must be the repository as owner/name"

# GH replaces the command that runs gh (the tests use it). It is one program,
# so a path with a space in it works.
GH_CMD=${GH:-gh}
for tool in jq shasum "$GH_CMD"; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is not installed"
done

# A signal, like the cancelling of the job, ends the script with the status a
# shell gives for it, and the exit trap deletes the draft on the way out.
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
STDERR_FILE=$(mktemp "${TMPDIR:-/tmp}/publish-release.XXXXXX")

# --- the feed folder ---------------------------------------------------------

[[ -d $FEED_DIR ]] || fail "there is no feed folder at $FEED_DIR"
MANIFEST=$FEED_DIR/release.json
[[ -f $MANIFEST ]] || fail "there is no release.json in $FEED_DIR"
jq -e 'type == "object"' "$MANIFEST" >/dev/null 2>&1 || fail "release.json is not a JSON object"

read_manifest VERSION version
read_manifest BUILD build
read_manifest TAG tag
read_manifest TITLE title
read_manifest COMMIT commit
read_manifest DMG dmg
read_manifest DMG_SHA256 dmg_sha256
read_manifest APPCAST_SHA256 appcast_sha256
read_manifest NOTES notes
read_manifest LATEST_TAG_SEEN latest_tag_seen

# What is used from release.json goes to gh and into paths, so each value has
# the shape it has when the build job writes it. The names of the files are
# plain names, which cannot leave the folder or pass for an option.
version_pattern='^[0-9]+\.[0-9]+(\.[0-9]+)?$'
build_pattern='^[1-9][0-9]*$'
commit_pattern='^[0-9a-f]{40}$'
sha256_pattern='^[0-9a-f]{64}$'
file_name_pattern='^[A-Za-z0-9][A-Za-z0-9._-]*$'
[[ $VERSION =~ $version_pattern ]] || fail "\"version\" in release.json is not a version number"
[[ $BUILD =~ $build_pattern ]] || fail "\"build\" in release.json is not a build number"
[[ $TAG == "v$VERSION-$BUILD" ]] || fail "\"tag\" in release.json is not v<version>-<build>"
[[ -n $TITLE ]] || fail "\"title\" in release.json is empty"
[[ $COMMIT =~ $commit_pattern ]] || fail "\"commit\" in release.json is not a full commit hash"
[[ $DMG =~ $file_name_pattern && $DMG == *.dmg ]] || fail "\"dmg\" in release.json is not the name of a disk image"
[[ $DMG_SHA256 =~ $sha256_pattern ]] || fail "\"dmg_sha256\" in release.json is not a SHA-256"
[[ $APPCAST_SHA256 =~ $sha256_pattern ]] || fail "\"appcast_sha256\" in release.json is not a SHA-256"
[[ $NOTES =~ $file_name_pattern ]] || fail "\"notes\" in release.json is not a plain file name"

# The feed has to be called appcast.xml: the apps ask for
# releases/latest/download/appcast.xml.
APPCAST=appcast.xml
for name in "$DMG" "$APPCAST" "$NOTES"; do
  [[ -f $FEED_DIR/$name ]] || fail "there is no $name in $FEED_DIR"
done
echo "Checking $DMG and $APPCAST against release.json..."
verify_checksum "$DMG" "$DMG_SHA256"
verify_checksum "$APPCAST" "$APPCAST_SHA256"

# --- what GitHub has ---------------------------------------------------------

# Nothing is created unless GitHub has neither a release nor a git tag of this
# name, and the Latest release is the one the build saw. gh answers "release not
# found" or HTTP 404 for what is not there.
echo "Asking GitHub about $TAG and the Latest release of $REPO..."

status=0
call_gh release view "$TAG" --repo "$REPO" || status=$?
if [[ $status -eq 0 ]]; then
  fail "the release $TAG exists already (a draft that an earlier run left behind is a release too)." \
    "See https://github.com/$REPO/releases"
elif [[ $GH_ERR != *"release not found"* && $GH_ERR != *"HTTP 404"* ]]; then
  fail_gh_call release view "$TAG" --repo "$REPO"
fi

status=0
call_gh api "repos/$REPO/git/ref/tags/$TAG" || status=$?
if [[ $status -eq 0 ]]; then
  fail "the git tag $TAG exists already (this version and build may have been released before)"
elif [[ $GH_ERR != *"HTTP 404"* ]]; then
  fail_gh_call api "repos/$REPO/git/ref/tags/$TAG"
fi

status=0
call_gh api "repos/$REPO/releases/latest" --jq .tag_name || status=$?
if [[ $status -eq 0 ]]; then
  LATEST_TAG_NOW=$GH_OUT
elif [[ $GH_ERR == *"HTTP 404"* ]]; then
  LATEST_TAG_NOW=""
else
  fail_gh_call api "repos/$REPO/releases/latest"
fi
if [[ $LATEST_TAG_NOW != "$LATEST_TAG_SEEN" ]]; then
  fail "the Latest release changed after the build checked it" \
    "(then $(printable_tag "$LATEST_TAG_SEEN"), now $(printable_tag "$LATEST_TAG_NOW"))." \
    "Run the release again, so that its checks see the Latest release as it is now."
fi

# --- the release -------------------------------------------------------------

# The notes reach gh as a file and the title as one argument, so nothing in
# them is read by the shell. The draft has no git tag yet: publishing it makes
# the tag, at the commit the build was made from.
echo "Creating the draft release $TAG with $DMG and $APPCAST..."
CREATE_ATTEMPTED=true
"$GH_CMD" release create "$TAG" --repo "$REPO" --draft --target "$COMMIT" --title "$TITLE" \
  --notes-file "$FEED_DIR/$NOTES" "$FEED_DIR/$DMG" "$FEED_DIR/$APPCAST" ||
  fail "gh release create failed"

echo "Publishing $TAG as the Latest release..."
"$GH_CMD" release edit "$TAG" --repo "$REPO" --draft=false --latest || fail "gh release edit failed"
PUBLISHED=true

RELEASE_URL=https://github.com/$REPO/releases/tag/$TAG
echo "Published $TAG as the Latest release: $RELEASE_URL"
write_summary
