#!/usr/bin/env bash
#
# Shared helpers for the colormath release scripts. Sourced, never executed.
#
# Everything that knows *where* a version is written down lives here, in the
# read_*/write_* pairs below. Adding a new stamp site means adding one pair and
# one entry in STAMP_SITES — stamp.sh and verify.sh both drive off that list, so
# a new site cannot be stamped-but-unverified or verified-but-unstamped. That
# asymmetry is exactly how the Claude plugin.json drifted: it was a stamp site nothing
# checked.
#
# Note these are the *machine-read* sites only — refs that something resolves at
# runtime. Documentation examples are deliberately not stamped; they carry a
# literal "vX.Y.Z" placeholder so there is nothing there to rot.
#
# This tooling lives in release/ rather than scripts/ on purpose. gates.yml
# sparse-checks-out `scripts` onto every consumer runner (16 call sites), and
# cone-mode sparse checkout is recursive — so scripts/release/ would ship to
# every consumer CI run and become part of the published contract surface.
# release/ sits beside docs/ and example/, outside that checkout.

set -euo pipefail

# Repo root, regardless of where a script was invoked from.
COLORMATH_ROOT="${COLORMATH_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

GATES_WF="$COLORMATH_ROOT/.github/workflows/gates.yml"
MAKEFILE="$COLORMATH_ROOT/Makefile.colormath"
CLAUDE_PLUGIN_JSON="$COLORMATH_ROOT/plugin/.claude-plugin/plugin.json"
CODEX_PLUGIN_JSON="$COLORMATH_ROOT/plugin/.codex-plugin/plugin.json"
CHANGELOG="$COLORMATH_ROOT/CHANGELOG.md"

# The machine-read stamp sites, as "label:reader:writer". stamp.sh runs every
# writer; verify.sh runs every reader and requires them to agree.
STAMP_SITES=(
	"gates.yml colormath-ref default:read_gates_ref:write_gates_ref"
	"Makefile.colormath COLORMATH_REF:read_makefile_ref:write_makefile_ref"
	"Claude plugin.json version:read_claude_plugin_version:write_claude_plugin_version"
	"Codex plugin.json version:read_codex_plugin_version:write_codex_plugin_version"
)

die() {
	echo "error: $*" >&2
	exit 1
}

note() { echo "  $*"; }

# --- version helpers --------------------------------------------------------

# Accepts "3.1.0" or "v3.1.0"; always prints the "v" form. Rejects anything
# else, so a typo becomes an error rather than a tag named "v3..1.0".
normalize_version() {
	local v="${1#v}"
	[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "not a SemVer version: $1 (expected X.Y.Z or vX.Y.Z)"
	echo "v$v"
}

# The newest tag reachable from HEAD, by SemVer order.
#
# Deliberately not `git describe --tags --abbrev=0`, which returns the most
# recent tag by *commit distance*. On a history where v2.4.0 and v3.0.0 sit on
# adjacent merges, distance and SemVer can disagree, and the invariant is a
# statement about SemVer.
newest_reachable_tag() {
	git -C "$COLORMATH_ROOT" tag --merged HEAD --sort=-v:refname | head -1
}

# True when $1 sorts strictly above $2 in SemVer order.
version_gt() {
	[ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

tag_exists_locally() { git -C "$COLORMATH_ROOT" rev-parse -q --verify "refs/tags/$1" >/dev/null 2>&1; }

tag_exists_on_origin() { [ -n "$(git -C "$COLORMATH_ROOT" ls-remote --tags origin "refs/tags/$1" 2>/dev/null)" ]; }

# --- stamp site readers -----------------------------------------------------
#
# Each reader prints the version in "vX.Y.Z" form, or nothing if the site could
# not be parsed. Callers treat empty as a hard error — a site that stopped
# matching is a site that silently stopped being stamped.

read_gates_ref() {
	awk '
		/^      colormath-ref:/ { in_input = 1; next }
		in_input && /^      [a-z]/ { exit }
		in_input && /^        default:/ {
			gsub(/^        default: *"?|"? *$/, "")
			print; exit
		}
	' "$GATES_WF"
}

read_makefile_ref() {
	sed -n 's/^COLORMATH_REF[[:space:]]*=[[:space:]]*\(v[0-9][0-9.]*\)[[:space:]]*$/\1/p' "$MAKEFILE" | head -1
}

# Plugin manifests store a bare "3.1.0"; print it in "v" form so every reader
# is directly comparable.
read_plugin_manifest_version() {
	local manifest="$1" raw
	raw=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*$/\1/p' "$manifest" | head -1)
	[ -n "$raw" ] && echo "v$raw"
}

read_claude_plugin_version() {
	read_plugin_manifest_version "$CLAUDE_PLUGIN_JSON"
}

read_codex_plugin_version() {
	read_plugin_manifest_version "$CODEX_PLUGIN_JSON"
}

# The newest *released* section heading in the changelog, ignoring Unreleased.
read_changelog_latest() {
	sed -n 's/^## \(v[0-9][0-9.]*\) — .*$/\1/p' "$CHANGELOG" | head -1
}

changelog_has_unreleased() { grep -q '^## Unreleased[[:space:]]*$' "$CHANGELOG"; }

# --- stamp site writers -----------------------------------------------------
#
# Anchored patterns, never a global version replace. The repo is full of prose
# that names old versions on purpose ("Default-on since v2.0.0", "contractual at
# v1.0.0", the adoption notes recording what consumers actually run); rewriting
# any of it would be a silent falsification of the history.

write_gates_ref() {
	local v="$1"
	awk -v ver="$v" '
		/^      colormath-ref:/ { in_input = 1 }
		in_input && /^        default:/ {
			sub(/default:.*/, "default: \"" ver "\"")
			in_input = 0
		}
		in_input && /^      [a-z]/ && !/^      colormath-ref:/ { in_input = 0 }
		{ print }
	' "$GATES_WF" >"$GATES_WF.tmp" && mv "$GATES_WF.tmp" "$GATES_WF"
}

write_makefile_ref() {
	sed "s|^COLORMATH_REF[[:space:]]*=.*$|COLORMATH_REF = $1|" "$MAKEFILE" >"$MAKEFILE.tmp" &&
		mv "$MAKEFILE.tmp" "$MAKEFILE"
}

write_plugin_manifest_version() {
	local manifest="$1" version="$2"
	sed "s|^\([[:space:]]*\"version\"[[:space:]]*:[[:space:]]*\"\)[0-9][0-9.]*\(\"\)|\1${version#v}\2|" "$manifest" >"$manifest.tmp" &&
		mv "$manifest.tmp" "$manifest"
}

write_claude_plugin_version() {
	write_plugin_manifest_version "$CLAUDE_PLUGIN_JSON" "$1"
}

write_codex_plugin_version() {
	write_plugin_manifest_version "$CODEX_PLUGIN_JSON" "$1"
}
