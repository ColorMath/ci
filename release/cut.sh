#!/usr/bin/env bash
#
# Cut a colormath release: stamp, commit, tag, push, publish. One gesture.
#
# The whole point is atomicity. The old process was a six-step checklist in
# LIFECYCLE.md, and the steps drifted apart: v3.1.0 was stamped into main and
# written into the changelog but never tagged, leaving every consumer's
# `make preflight` fetching gate scripts from a ref that 404s. Nine of the
# sixteen published tags are internally inconsistent for the same reason.
#
# The fix is that the stamps and the tag land in a single `git push --atomic`.
# Git updates both refs or neither, so there is no window in which main
# advertises a tag that does not exist — not days, not seconds. If someone else
# pushed to main in the meantime, the whole push is rejected and nothing
# partial happens; rerun after pulling.
#
# The one thing that cannot be inside the transaction is the GitHub Release,
# which lives in a different system. So that step is idempotent and this script
# is resumable: if the tag is already on origin at HEAD, it skips straight to
# publishing.
#
# Usage:
#   cut.sh vX.Y.Z              cut the release
#   cut.sh vX.Y.Z --dry-run    do everything except commit/tag/push/publish
#
# Env:
#   COLORMATH_SKIP_CI_CHECK=1  skip the "CI is green on this SHA" precondition

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib.sh"

version=$(normalize_version "${1:?usage: cut.sh vX.Y.Z [--dry-run]}")
shift
dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

cd "$COLORMATH_ROOT"

step() { echo; echo "==> $*"; }

# --- resume path ------------------------------------------------------------
#
# Push succeeded, publish failed. Don't redo the transaction; finish it.
if tag_exists_on_origin "$version"; then
	remote_sha=$(git ls-remote --tags origin "refs/tags/$version^{}" | cut -f1)
	[ -n "$remote_sha" ] || remote_sha=$(git ls-remote --tags origin "refs/tags/$version" | cut -f1)
	if [ "$remote_sha" = "$(git rev-parse HEAD)" ]; then
		step "$version is already on origin at HEAD — resuming at the publish step"
		exec "$here/publish-release.sh" "$version" ${dry_run:+$([ "$dry_run" -eq 1 ] && echo --dry-run)}
	fi
	die "$version already exists on origin, pointing at $remote_sha (HEAD is $(git rev-parse HEAD))"
fi

# --- preconditions ----------------------------------------------------------

step "Checking preconditions"

[ -z "$(git status --porcelain)" ] || die "working tree is dirty — commit or stash first"
note "working tree is clean"

branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = "main" ] || die "releases are cut from main, not $branch"
note "on main"

git fetch --quiet origin main --tags
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] ||
	die "main is not in sync with origin/main — pull, or push what you have, then rerun"
note "in sync with origin/main"

gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"
note "gh is authenticated"

if [ "${COLORMATH_SKIP_CI_CHECK:-0}" != "1" ]; then
	sha=$(git rev-parse HEAD)
	conclusion=$(gh run list --workflow=CI --branch=main --limit=20 \
		--json headSha,conclusion,status \
		--jq "[.[] | select(.headSha == \"$sha\")] | first | .conclusion // \"none\"" 2>/dev/null || echo none)
	case "$conclusion" in
	success) note "CI is green on $sha" ;;
	none) die "no CI run found for $sha — wait for CI, or set COLORMATH_SKIP_CI_CHECK=1" ;;
	*) die "the CI run for $sha concluded '$conclusion' — fix main before releasing" ;;
	esac
else
	note "CI check skipped (COLORMATH_SKIP_CI_CHECK=1)"
fi

# --- verify the baseline ----------------------------------------------------

step "Verifying the current state is consistent before changing anything"
"$here/verify.sh"

# --- stamp ------------------------------------------------------------------

step "Stamping $version"
"$here/stamp.sh" "$version"

step "Verifying the stamped tree"
"$here/verify.sh" --expect "$version"

echo
echo "==> Release diff"
git --no-pager diff --stat
echo
git --no-pager diff

if [ "$dry_run" -eq 1 ]; then
	echo
	echo "==> DRY RUN — reverting the stamp, nothing was committed"
	git checkout -- .
	echo
	echo "Would have run:"
	echo "  git commit -m 'chore(release): $version'"
	echo "  git tag -a $version -m <changelog section>"
	echo "  git push --atomic origin main refs/tags/$version"
	echo "  publish-release.sh $version"
	exit 0
fi

# --- the transaction --------------------------------------------------------

step "Committing and tagging"
git add -A
git commit --quiet -m "chore(release): $version"

# Annotated, always. The repo's history flips between lightweight and annotated
# tags (v2.0.0-v2.3.0 annotated, v2.4.0 and v3.0.0 lightweight); annotated tags
# carry the tagger, date, and message, so the release notes travel with the tag
# itself and not only with the GitHub Release.
notes_file=$(mktemp)
trap 'rm -f "$notes_file"' EXIT
{
	echo "$version"
	echo
	"$here/notes.sh" "$version"
} >"$notes_file"
git tag -a "$version" -F "$notes_file"

step "Pushing main and $version atomically"
if ! git push --atomic origin main "refs/tags/$version"; then
	echo
	echo "Atomic push rejected — NOTHING was published." >&2
	echo "Neither main nor the tag moved on origin. Cleaning up the local commit and tag." >&2
	git tag -d "$version" >/dev/null
	git reset --hard HEAD~1 >/dev/null
	die "push rejected (someone else pushed to main?). Pull and rerun."
fi
note "main and $version are on origin"

step "Publishing the GitHub Release"
"$here/publish-release.sh" "$version"

echo
echo "Released $version."
echo "Next, per LIFECYCLE.md: canary talas, then intendent, then runwayz."
