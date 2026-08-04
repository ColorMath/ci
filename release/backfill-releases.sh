#!/usr/bin/env bash
#
# Create the missing GitHub Releases for tags that were cut before there was
# machinery to create them.
#
# All sixteen tags up to v3.0.0 were published bare: the release notes existed
# only in CHANGELOG.md, so `/releases/latest` — the obvious place a consumer
# looks to answer "what should I pin to?" — was empty. This walks the tags
# oldest to newest and fills them in from the changelog.
#
# Idempotent: a tag that already has a Release is skipped, so a partial run is
# fixed by rerunning. One-shot in practice — cut.sh creates the Release for
# every tag from v3.1.0 on.
#
# Usage: backfill-releases.sh [--apply]
#
# Dry-run by default. --apply is required to create anything, because this
# writes to a public repo and notifies watchers.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib.sh"

apply=0
[ "${1:-}" = "--apply" ] && apply=1

gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)

tags=$(git -C "$COLORMATH_ROOT" tag --list 'v[0-9]*' --sort=v:refname)
[ -n "$tags" ] || die "no tags found"
newest=$(printf '%s\n' "$tags" | tail -1)

echo "Repo:   $repo"
echo "Newest: $newest (gets --latest; every other tag gets --latest=false)"
echo

created=0 skipped=0 missing=0

for tag in $tags; do
	if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
		printf '  %-10s skip (Release already exists)\n' "$tag"
		skipped=$((skipped + 1))
		continue
	fi

	if ! "$here/notes.sh" "$tag" >/dev/null 2>&1; then
		printf '  %-10s SKIP — no non-empty CHANGELOG.md section\n' "$tag"
		missing=$((missing + 1))
		continue
	fi

	# LIFECYCLE.md: pins become contractual at v1.0.0, so the 0.x tags are
	# honestly pre-releases. This also keeps them out of "latest" regardless of
	# the flag below.
	prerelease=""
	case "$tag" in v0.*) prerelease="--prerelease" ;; esac

	latest_flag="--latest=false"
	[ "$tag" = "$newest" ] && latest_flag="--latest=true"

	if [ "$apply" -eq 0 ]; then
		printf '  %-10s would create (%s lines of notes) %s %s\n' \
			"$tag" "$("$here/notes.sh" "$tag" | wc -l)" "$latest_flag" "$prerelease"
		created=$((created + 1))
		continue
	fi

	notes_file=$(mktemp)
	"$here/notes.sh" "$tag" >"$notes_file"
	# --verify-tag: never invent a tag that does not exist.
	gh release create "$tag" \
		--repo "$repo" \
		--title "$tag" \
		--notes-file "$notes_file" \
		--verify-tag \
		$latest_flag $prerelease >/dev/null
	rm -f "$notes_file"
	printf '  %-10s created %s %s\n' "$tag" "$latest_flag" "$prerelease"
	created=$((created + 1))
done

echo
if [ "$apply" -eq 0 ]; then
	echo "Dry run: $created would be created, $skipped already exist, $missing have no notes."
	echo "Rerun with --apply to create them."
else
	echo "Done: $created created, $skipped already existed, $missing skipped for missing notes."
fi

# GitHub does not allow backdating published_at, so every backfilled Release
# shows today's date. The changelog date is in each body and the tag's own
# commit date is on the release page, so the historical record survives where it
# matters.
