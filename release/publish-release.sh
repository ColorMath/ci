#!/usr/bin/env bash
#
# Create the GitHub Release for a tag, with the body taken from CHANGELOG.md.
#
# Split out of cut.sh so it is independently re-runnable. The push and the
# release creation cannot be made one transaction — they are two different
# systems — so the design makes the second half idempotent instead: if the tag
# landed but `gh` failed, rerunning fixes it, and rerunning when the release
# already exists is a no-op.
#
# Usage: publish-release.sh vX.Y.Z [--latest=false] [--dry-run]

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib.sh"

version=$(normalize_version "${1:?usage: publish-release.sh vX.Y.Z [--latest=false] [--dry-run]}")
shift
latest_flag="--latest"
dry_run=0
for arg in "$@"; do
	case "$arg" in
	--latest=false) latest_flag="--latest=false" ;;
	--latest=true) latest_flag="--latest" ;;
	--dry-run) dry_run=1 ;;
	*) die "unknown argument: $arg" ;;
	esac
done

if gh release view "$version" --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)" >/dev/null 2>&1; then
	note "GitHub Release $version already exists — nothing to do"
	exit 0
fi

notes=$("$here/notes.sh" "$version")

if [ "$dry_run" -eq 1 ]; then
	echo "DRY RUN: would create GitHub Release $version ($latest_flag) with body:"
	echo "---"
	printf '%s\n' "$notes" | head -20
	printf '%s\n' "$notes" | tail -n +21 | head -1 | grep -q . && echo "  ... ($(printf '%s\n' "$notes" | wc -l) lines total)"
	echo "---"
	exit 0
fi

notes_file=$(mktemp)
trap 'rm -f "$notes_file"' EXIT
printf '%s\n' "$notes" >"$notes_file"

# --verify-tag refuses to invent a tag: if the ref is not on the remote, this
# fails instead of silently creating one from the default branch.
gh release create "$version" \
	--title "$version" \
	--notes-file "$notes_file" \
	--verify-tag \
	"$latest_flag"

note "GitHub Release $version created"
