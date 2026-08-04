#!/usr/bin/env bash
#
# Write a version into every machine-read stamp site, and promote the
# changelog's Unreleased section to that version.
#
# Pure filesystem: no git, no network, no gh. That is deliberate — it makes the
# risky part (rewriting files with sed/awk) independently testable, and leaves
# cut.sh as the only script in the set that can mutate a ref or touch a remote.
#
# Idempotent: running it twice with the same version is a no-op the second time.
#
# Usage: stamp.sh vX.Y.Z [--date YYYY-MM-DD]
#
# What it does NOT touch, on purpose: prose that names an old version because
# that is a true historical statement ("Default-on since v2.0.0"), the adoption
# notes recording which release each consumer is actually on, and the
# documentation examples, which carry a literal vX.Y.Z placeholder precisely so
# that nothing has to remember to update them.

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

version=$(normalize_version "${1:?usage: stamp.sh vX.Y.Z [--date YYYY-MM-DD]}")
shift
release_date=$(date -u +%Y-%m-%d)
if [ "${1:-}" = "--date" ]; then
	release_date="${2:?--date needs a YYYY-MM-DD argument}"
fi

echo "Stamping $version (dated $release_date)"

# --- the machine-read sites -------------------------------------------------

for site in "${STAMP_SITES[@]}"; do
	label="${site%%:*}"
	writer="${site##*:}"
	"$writer" "$version"
	note "$label -> $version"
done

# --- the changelog ----------------------------------------------------------
#
# Promote "## Unreleased" to "## vX.Y.Z — DATE" and open a fresh empty
# Unreleased above it, so the next change has somewhere to land. The em dash
# matches the existing heading style and is what read_changelog_latest and
# notes.sh both key off.

if grep -q "^## $version — " "$CHANGELOG"; then
	note "CHANGELOG.md already has a $version section — leaving it alone"
else
	changelog_has_unreleased || die "CHANGELOG.md has no '## Unreleased' section to promote"

	awk -v ver="$version" -v d="$release_date" '
		!done && /^## Unreleased[[:space:]]*$/ {
			print "## Unreleased"
			print ""
			print "## " ver " — " d
			done = 1
			next
		}
		{ print }
	' "$CHANGELOG" >"$CHANGELOG.tmp" && mv "$CHANGELOG.tmp" "$CHANGELOG"
	note "CHANGELOG.md: Unreleased -> $version — $release_date"
fi

echo "Stamped. Nothing has been committed, tagged, or pushed."
