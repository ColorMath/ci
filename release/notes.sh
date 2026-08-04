#!/usr/bin/env bash
#
# Print one release's section body from CHANGELOG.md.
#
# Single source of truth for release notes: both `cut.sh` (annotated tag message
# + GitHub Release body) and `backfill-releases.sh` read notes from here, so a
# GitHub Release can never say something the changelog doesn't. There is no
# second place to write release notes and therefore no second place to forget.
#
# Usage: notes.sh vX.Y.Z
#
# Prints everything between the `## vX.Y.Z — DATE` heading and the next `## `
# heading, trimmed of leading/trailing blank lines. Exits non-zero when the
# section is missing or empty — a release with no notes is a release nobody can
# review, and that is worth failing over.

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

version=$(normalize_version "${1:?usage: notes.sh vX.Y.Z}")

body=$(awk -v want="## $version " '
	index($0, want) == 1 { in_section = 1; next }
	in_section && /^## / { exit }
	in_section { print }
' "$CHANGELOG")

# Strip leading and trailing blank lines.
body=$(printf '%s\n' "$body" | sed -e '/./,$!d' | tac | sed -e '/./,$!d' | tac)

[ -n "$body" ] || die "CHANGELOG.md has no non-empty '## $version — DATE' section"

printf '%s\n' "$body"
