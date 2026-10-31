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
name exists, or when the Latest release is not the one the build saw. Once the
draft exists, every call names it by the release ID that GitHub answered when it
was created, never by its tag. A run that fails or is stopped after that asks
GitHub whether the release is still a draft, and deletes it only if the answer
is yes. A release that is not a draft any more, or that cannot be asked about,
is left alone and reported, and the run still fails. A create that GitHub
refuses makes no draft. One that fails in another way, answers without an ID, or
is stopped before the ID was read may have made a draft all the same, which the
script cannot tell from a draft of that tag that someone else made, so it
deletes nothing and says where to look.

Environment:
  GITHUB_REPOSITORY    the repository as owner/name (required)
  GH_TOKEN             the token gh signs in with (only gh reads it)
  GH                   a program to run in place of gh (the tests use it)
  GITHUB_STEP_SUMMARY  a file to append a summary of the published release to
EOF
}

# The exit trap deals with the release when CREATE_ATTEMPTED is set and
# PUBLISHED is not: a draft may exist, or the release may be published
# although the script has not seen the call that did it succeed.
CREATE_ATTEMPTED=false
PUBLISHED=false

# The ID that GitHub answered when it created the draft: empty until a create
# succeeded with an answer that is nothing but a release ID. From then on it is
# the one name the script uses for the release, and never the tag, because a tag
# can belong to a draft that someone else made after the checks.
RELEASE_ID=""

# Whether GitHub refused the create with an HTTP status of 4xx, which means that
# it made no draft.
CREATE_REFUSED=false

# What became of the git tag of the release. It is empty until the script makes
# the tag. Then it is unknown, from just before the call, and it stays so when
# the call fails in a way that says nothing about whether GitHub did what it was
# asked, or when a stop ends the run during the call. Otherwise it becomes made,
# when the call succeeded, exists, when GitHub answered that a tag of that name
# was there already, or refused, when GitHub refused the call in another way,
# which means that it made no tag. Only a tag that is made is one that this run
# may delete.
TAG_STATE=""

# Whether discard_draft found the release to be a draft, whether or not it could
# delete it, or to be gone. The exit trap goes on to the git tag only then: a
# release that is published, or that cannot be asked about, may be using it.
RELEASE_GONE_OR_DRAFT=false

# The files that hold what gh prints on standard output and on standard error,
# and what the last call of call_gh printed on each of the two.
STDOUT_FILE=""
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

# Runs on every exit. When the create was attempted and the script has not seen
# the release published, it deals with the draft by the ID that the create
# answered: it discards the draft if it is still one, and then the git tag, if
# the release was a draft or is gone (see discard_tag). Without an ID there is
# no release it can name, and a draft of the tag may be one that someone else
# made, so nothing is deleted. It says instead that GitHub refused the create,
# which made no draft, or that GitHub may have made the draft all the same,
# which is the case after a create that failed in another way, one that
# answered without an ID, and a stop before the script had read the ID. It keeps
# the status the run ends with. A cancelled job gets INT and, some seconds
# later, TERM, and the trap for the second would end the script in the middle of
# the cleanup, which makes several calls. So the cleanup ignores HUP, INT and
# TERM from its first line, and runs to its end.
cleanup() {
  local status=$?
  trap '' HUP INT TERM
  if [[ $CREATE_ATTEMPTED == true && $PUBLISHED != true ]]; then
    if [[ -n $RELEASE_ID ]]; then
      discard_draft
      if [[ $RELEASE_GONE_OR_DRAFT == true ]]; then
        discard_tag
      fi
    elif [[ $CREATE_REFUSED == true ]]; then
      echo "GitHub refused to create the release $TAG, so no draft was made."
    else
      echo "error: GitHub may have made the draft release $TAG all the same, so nothing was deleted." \
        "Check https://github.com/$REPO/releases and delete a draft of $TAG there if this run left one:" \
        "the next run stops at it." >&2
    fi
  fi
  if [[ -n $STDOUT_FILE ]]; then
    rm -f "$STDOUT_FILE"
  fi
  if [[ -n $STDERR_FILE ]]; then
    rm -f "$STDERR_FILE"
  fi
  exit "$status"
}

# Deletes the release with RELEASE_ID when it is still a draft, and only then.
# The ID is the one the create answered, so the release is this run's own and
# not a draft of the same tag that someone else made. But a run that fails or is
# stopped after the create may have published it all the same: the publish call
# can fail after GitHub applied the change, and a signal can end the script when
# gh is done with a publish that went through. A published release is the
# Latest one, and deleting it would take the update away from every app and
# leave the git tag behind. So the release is asked whether it is a draft first.
# Only an answer of exactly true from a call that succeeded lets the delete
# follow; what a failed call printed is not an answer. A release that is not a
# draft, that is not there, or that cannot be asked about is left alone and
# reported. RELEASE_GONE_OR_DRAFT records that the release was a draft, whether
# or not it could be deleted, or was gone: the exit trap goes on to the git tag
# only then.
discard_draft() {
  local status=0 releases="https://github.com/$REPO/releases"
  call_gh api "repos/$REPO/releases/$RELEASE_ID" --jq .draft || status=$?
  if [[ $status -eq 0 && $GH_OUT == true ]]; then
    RELEASE_GONE_OR_DRAFT=true
    delete_draft
  elif [[ $status -eq 0 && $GH_OUT == false ]]; then
    echo "error: the release $TAG is not a draft any more, so it was not deleted." \
      "It may be published and Latest. Check $releases" >&2
  elif [[ $status -ne 0 && $GH_ERR == *"HTTP 404"* ]]; then
    RELEASE_GONE_OR_DRAFT=true
    echo "There is no release $TAG on GitHub any more, so no draft was left behind."
  else
    echo "error: could not tell whether the release $TAG is a draft$(http_status), so it was not deleted." \
      "Check $releases and delete the draft there if one was left behind." >&2
  fi
}

# Deletes the release with RELEASE_ID, which discard_draft found to be a draft.
# A draft that cannot be deleted is reported with where to delete it by hand,
# because the next run stops at it.
delete_draft() {
  local status=0
  echo "Deleting the draft release $TAG, which was not published..."
  call_gh api --method DELETE "repos/$REPO/releases/$RELEASE_ID" --silent || status=$?
  if [[ $status -eq 0 ]]; then
    echo "Deleted the draft release $TAG."
  else
    echo "error: could not delete the draft release $TAG$(http_status)." \
      "Delete it at https://github.com/$REPO/releases before the next run." >&2
  fi
}

# Deals with the git tag that make_tag may have made, when discard_draft found
# the release to be a draft or gone. In any other case the tag is not touched,
# because a release that is published, or that could not be asked about, may be
# using it. A tag that was made is deleted when it is still the run's (see
# discard_made_tag), because the next run would stop at it. A tag that GitHub
# may have made all the same, which is the case after a failure that says
# nothing about it and after a stop during the call, cannot be told from a tag
# of that name that someone else pushed, so it is not deleted, and the message
# says where to look. A call that GitHub refused made no tag. A tag that was
# there already is not the run's, and before make_tag there is no tag, so
# neither is mentioned.
discard_tag() {
  local tags="https://github.com/$REPO/tags"
  case $TAG_STATE in
    made)
      discard_made_tag
      ;;
    unknown)
      echo "error: GitHub may have made the git tag $TAG all the same, so it was not deleted." \
        "Check $tags and delete it there if this run made it: the next run stops at it." >&2
      ;;
    refused)
      echo "GitHub refused to create the git tag $TAG, so this run made no tag."
      ;;
  esac
}

# Deletes the git tag that the call of make_tag made, when it is still the one
# the run made and no published release uses it. The run made a tag that names
# the built commit itself, so a tag that points anywhere else, or at a tag
# object because an annotated tag replaced it, is someone else's now. A
# published release with the tag would be left without it. A tag that is gone is
# nothing to delete. A question that fails leaves the tag where it is and says
# which question it was, and what the failed call printed is not an answer. The
# delete follows the two answers, where the tag points and whether a published
# release uses it, by one round trip, and GitHub has no conditional delete of a
# ref, so a tag that is moved or a release that is published in exactly that
# moment would still be deleted.
discard_made_tag() {
  local status=0 tags="https://github.com/$REPO/tags"
  call_gh api "repos/$REPO/git/ref/tags/$TAG" --jq '.object.type + ":" + .object.sha' || status=$?
  if [[ $status -ne 0 && $GH_ERR == *"HTTP 404"* ]]; then
    echo "There is no git tag $TAG any more, so none was left behind."
    return 0
  elif [[ $status -ne 0 ]]; then
    echo "error: could not tell where the git tag $TAG points$(http_status), so it was not deleted." \
      "Check $tags" >&2
    return 0
  elif [[ $GH_OUT != "commit:$COMMIT" ]]; then
    echo "error: the git tag $TAG does not point at the built commit any more, so it was not deleted." \
      "Check $tags" >&2
    return 0
  fi

  status=0
  call_gh api "repos/$REPO/releases/tags/$TAG" --silent || status=$?
  if [[ $status -eq 0 ]]; then
    echo "error: a published release uses the git tag $TAG, so it was not deleted." \
      "Check https://github.com/$REPO/releases" >&2
  elif [[ $GH_ERR != *"HTTP 404"* ]]; then
    echo "error: could not tell whether a published release uses the git tag $TAG$(http_status)," \
      "so it was not deleted. Check $tags" >&2
  else
    delete_tag
  fi
}

# Deletes the git tag, which discard_made_tag found to be the one this run made
# and to have no published release. A tag that cannot be deleted is reported
# with where to delete it by hand, because the next run stops at it.
delete_tag() {
  local status=0
  call_gh api --method DELETE "repos/$REPO/git/refs/tags/$TAG" --silent || status=$?
  if [[ $status -eq 0 ]]; then
    echo "Deleted the git tag $TAG, which this run made."
  else
    echo "error: could not delete the git tag $TAG$(http_status)." \
      "Delete it at https://github.com/$REPO/tags before the next run." >&2
  fi
}

# Runs gh with the arguments. What it prints on standard output goes to GH_OUT
# and what it prints on standard error to GH_ERR, and the status it ends with is
# the status of the function. Every call of gh goes through here. Both streams
# go to files and gh is a direct child of the script, not of a command
# substitution, so a signal for the script is handled as soon as gh is done,
# before the script has read anything that gh printed: a run that is stopped
# while the create runs has not kept the ID that the create answered.
call_gh() {
  local status=0
  "$GH_CMD" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE" || status=$?
  GH_OUT=$(<"$STDOUT_FILE")
  GH_ERR=$(<"$STDERR_FILE")
  return "$status"
}

# The three digits of the HTTP status that gh printed for the call that just
# failed, and nothing when it printed none. This is the one place that reads the
# status out of what gh printed: http_status, refused_by_github and
# workflow_hint all go through it, so that they cannot disagree about it.
http_status_code() {
  local pattern='HTTP ([0-9]{3})'
  if [[ $GH_ERR =~ $pattern ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

# The HTTP status that gh printed for the call that just failed, as " (HTTP
# 502)", and nothing when it printed none.
http_status() {
  local code
  code=$(http_status_code)
  if [[ -n $code ]]; then
    echo " (HTTP $code)"
  fi
}

# Whether the call that just failed was refused by GitHub, which is when gh
# printed an HTTP status of 4xx for it. A request that GitHub refused made
# nothing. A failure without a status, such as a connection that was lost, and a
# status of 5xx say nothing about whether GitHub did what it was asked.
refused_by_github() {
  [[ $(http_status_code) == 4* ]]
}

# Stops after a gh call that failed in a way the script has no use for. The
# call and its HTTP status are reported and nothing else of what gh printed,
# which may be the body of the response.
fail_gh_call() {
  fail "gh $* failed$(http_status)"
}

# Prints the likely cause of the step that just failed, as one line of standard
# error, when GitHub answered it with HTTP 404 or 403: GitHub refuses the
# workflow's token a release or a tag of a commit that adds or changes files
# under .github/workflows/ compared with the default branch, and it answers with
# one of those two statuses. Any other status, and none at all, says nothing
# about that rule and gets no line.
workflow_hint() {
  case $(http_status_code) in
    403|404)
      echo "GitHub answers 404 or 403 here when the built commit adds or changes files under .github/workflows/" \
        "compared with the default branch, which the workflow's token may not publish. Merge the default branch" \
        "into the branch, or land the workflow change there first, then run the release again." >&2
      ;;
  esac
}

# Stops as fail does, with the line of workflow_hint right after the one that
# names the step: a call of workflow_hint before fail would print it first. Only
# the create, the tag and the publish end here, the three steps that the rule can
# make GitHub refuse.
fail_with_workflow_hint() {
  echo "error: $*" >&2
  workflow_hint
  exit 1
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

# Creates the release of the tag as a draft and keeps the ID that GitHub
# answers in RELEASE_ID. The title reaches gh as a raw field (-f), so that a
# title that looks like @file, true or a number stays the text it is, and the
# notes as a file that gh reads (-F body=@file), so nothing in either is read by
# the shell. The draft has no git tag yet: make_tag makes it, at the commit the
# build was made from, right before the publish. The commit is named here too,
# so that a tag which has vanished again by the publish is made at it. A create
# that fails is reported with its HTTP status and nothing else, because a
# message that repeated the call would print the title, and a 404 or 403 adds
# the line of workflow_hint. One that GitHub refused with a status of 4xx made
# nothing, which CREATE_REFUSED records for the exit trap. After any other
# failure, and after an answer that is no release ID, GitHub may have made the
# draft all the same, and the exit trap deletes nothing.
create_draft() {
  local status=0 pattern='^[1-9][0-9]*$'
  call_gh api --method POST "repos/$REPO/releases" -f "tag_name=$TAG" -f "target_commitish=$COMMIT" \
    -f "name=$TITLE" -F "body=@$FEED_DIR/$NOTES" -F draft=true --jq .id || status=$?
  if [[ $status -ne 0 ]]; then
    if refused_by_github; then
      CREATE_REFUSED=true
    fi
    fail_with_workflow_hint "creating the draft release $TAG failed$(http_status)"
  fi
  [[ $GH_OUT =~ $pattern ]] || fail "the answer to creating the draft release $TAG has no release ID"
  RELEASE_ID=$GH_OUT
}

# upload_asset NAME TYPE attaches the file NAME of the feed folder to the draft,
# with the content type TYPE. The address names the release by its ID, and the
# asset gets the name of the file.
upload_asset() {
  local name=$1 type=$2
  call_gh api --method POST "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$name" \
    -H "Content-Type: $type" --input "$FEED_DIR/$name" --silent ||
    fail "uploading $name to the draft release $TAG failed$(http_status)"
}

# Makes the git tag of the release at COMMIT, the commit the build was made from,
# right before the publish. Publishing the draft would make the tag too, but
# GitHub takes a tag of that name that is there already as it is, whatever
# commit it names, so a tag that someone pushed after the checks would become
# the tag of the release. Making the reference is refused instead (HTTP 422,
# "Reference already exists"), and the run stops. TAG_STATE records the outcome
# for the exit trap: a failure that is neither that refusal nor another one of
# 4xx leaves it unknown, because it says nothing about whether GitHub did what
# it was asked. A failure is reported with its HTTP status and nothing else of
# what gh printed, and a 404 or 403 adds the line of workflow_hint.
make_tag() {
  local status=0
  TAG_STATE=unknown
  call_gh api --method POST "repos/$REPO/git/refs" -f "ref=refs/tags/$TAG" -f "sha=$COMMIT" --silent || status=$?
  if [[ $status -eq 0 ]]; then
    TAG_STATE=made
  elif [[ $GH_ERR == *"Reference already exists"* ]]; then
    TAG_STATE=exists
    fail "the git tag $TAG appeared after the checks, so the release was not published." \
      "Check https://github.com/$REPO/tags"
  else
    if refused_by_github; then
      TAG_STATE=refused
    fi
    fail_with_workflow_hint "creating the git tag $TAG failed$(http_status)"
  fi
}

# Publishes the draft and marks it as the Latest release. A failure is reported
# with its HTTP status, and a 404 or 403 adds the line of workflow_hint.
publish_release() {
  call_gh api --method PATCH "repos/$REPO/releases/$RELEASE_ID" -F draft=false -f make_latest=true --silent ||
    fail_with_workflow_hint "publishing the release $TAG failed$(http_status)"
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
# shell gives for it, and the exit trap deals with the draft on the way out.
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
STDOUT_FILE=$(mktemp "${TMPDIR:-/tmp}/publish-release.XXXXXX")
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

# The create answers the ID of the draft, and the uploads and the publish name
# the draft by it: see create_draft. The git tag is made right before the
# publish, so that a tag which someone else pushed in the meantime stops the run
# and is not taken for the tag of the release: see make_tag.
echo "Creating the draft release $TAG with $DMG and $APPCAST..."
CREATE_ATTEMPTED=true
create_draft
upload_asset "$DMG" application/x-apple-diskimage
upload_asset "$APPCAST" "text/xml; charset=utf-8"

echo "Making the git tag $TAG at the built commit $COMMIT..."
make_tag

echo "Publishing $TAG as the Latest release..."
publish_release
PUBLISHED=true

RELEASE_URL=https://github.com/$REPO/releases/tag/$TAG
echo "Published $TAG as the Latest release: $RELEASE_URL"
write_summary
