#!/usr/bin/env bash
#
# The consistency oracle for colormath releases. One script, three modes, used
# by CI on every PR, by cut.sh immediately before it pushes, and by hand to
# audit tags after the fact.
#
# The invariant it enforces, in default mode:
#
#   On main, at every commit: the machine-read stamps agree with each other,
#   they equal the newest tag reachable from HEAD, and that tag exists.
#
# Why that is the right invariant. Consumers pin exact tags, and the stamps are
# how colormath fetches its own scripts at that pin. If a stamp names a tag that
# does not exist yet — the state main was left in when v3.1.0 was stamped but
# never tagged — then `make preflight` in every consumer 404s on every gate
# script. If a stamp names an older tag than the commit it ships in — the state
# the tagged v3.0.0 artifact is in today — then CI and the local mirror silently
# run different gate scripts. The old refs-lockstep check caught neither: it
# compared the two stamps to each other and never asked whether the ref
# resolved.
#
# The invariant holds continuously under the stamp-at-release model, including
# on the release commit itself, because that commit is tagged with the version
# it stamps in the same atomic push. That is what makes it safe to make
# blocking: it is already true, so it can never stand between a hotfix and main.
#
# Usage:
#   verify.sh                 default: check the working tree against the tags
#   verify.sh --expect vX.Y.Z release-time: check everything is stamped vX.Y.Z
#                             and that vX.Y.Z is a legal next tag
#   verify.sh --tag vX.Y.Z    audit: is that already-published tag self-consistent?
#   verify.sh --audit-all     audit every tag, print a table, never fail

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

failures=0

fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
	# GitHub Actions surfaces this in the PR's file view when it can.
	[ -n "${GITHUB_ACTIONS:-}" ] && echo "::error::$*"
	return 0
}

pass() { echo "ok: $*"; }

# Read every stamp site; require each to parse and all to agree. Sets
# SITES_VERSION to the agreed version, or empty when they disagree or one failed
# to parse.
#
# Sets a global rather than printing, deliberately: a command substitution would
# run this in a subshell and every fail() increment would be discarded with it,
# so the script would report success while printing failures.
SITES_VERSION=""
check_sites_agree() {
	local agreed="" site label reader value
	SITES_VERSION=""
	for site in "${STAMP_SITES[@]}"; do
		label="${site%%:*}"
		reader="${site#*:}"
		reader="${reader%%:*}"
		value=$("$reader" || true)
		if [ -z "$value" ]; then
			fail "could not parse a version out of $label — the stamp site moved or changed shape"
			return 0
		fi
		echo "  $label = $value"
		if [ -z "$agreed" ]; then
			agreed="$value"
		elif [ "$value" != "$agreed" ]; then
			fail "stamp sites disagree: $label is $value, an earlier site is $agreed"
			return 0
		fi
	done
	SITES_VERSION="$agreed"
}

verify_worktree() {
	local expected="${1:-}" stamped changelog_latest

	check_sites_agree
	stamped="$SITES_VERSION"
	[ -n "$stamped" ] || return 0
	pass "all ${#STAMP_SITES[@]} stamp sites agree at $stamped"

	changelog_latest=$(read_changelog_latest)
	if [ "$changelog_latest" != "$stamped" ]; then
		fail "CHANGELOG.md's newest released section is $changelog_latest, but the stamps say $stamped"
	else
		pass "CHANGELOG.md's newest released section is $stamped"
	fi

	if [ -n "$expected" ]; then
		# Release mode: the stamps must be the version we are about to cut.
		[ "$stamped" = "$expected" ] || fail "expected everything stamped $expected, found $stamped"
	else
		# Steady-state mode: the stamps must be the newest reachable tag, and
		# that tag must actually exist.
		local newest
		newest=$(newest_reachable_tag)
		if [ -z "$newest" ]; then
			fail "no tags reachable from HEAD — cannot check the stamps against a release"
		elif [ "$stamped" != "$newest" ]; then
			if tag_exists_locally "$stamped"; then
				fail "stamps say $stamped but the newest reachable tag is $newest — a release was cut without restamping, or a stamp was hand-edited"
			else
				fail "stamps say $stamped, which is not a tag at all (newest reachable is $newest) — every fetch of scripts/ at that ref will 404"
			fi
		else
			pass "stamps match the newest reachable tag ($newest)"
		fi

		if changelog_has_unreleased; then
			pass "CHANGELOG.md has an '## Unreleased' section"
		else
			fail "CHANGELOG.md has no '## Unreleased' section — changes land there, and the release renames it"
		fi
	fi
}

# The documentation examples were deliberately de-versioned to a literal vX.Y.Z
# placeholder, because nine of them had rotted to v2.0.0/v1.1.0/v1.0.0 while the
# repo was on v3.1.0. Nothing stamps them, so the only way they stay correct is
# by staying placeholders. This catches a well-meaning "fix" that pins them
# again, anywhere in the repo rather than only in the files that had the problem.
#
# The allowlist is short and each entry is a place where naming an old version is
# the correct, truthful thing to do.
verify_doc_placeholders() {
	local hits
	hits=$(git -C "$COLORMATH_ROOT" grep -nE 'ColorMath/ci(/\.github/workflows/[a-z-]+\.yml@|/)v[0-9]+\.[0-9]+\.[0-9]+' -- \
		':!CHANGELOG.md' \
		':!docs/adoption-notes.md' \
		':!release/' \
		':!example/node_modules/' 2>/dev/null || true)
	if [ -n "$hits" ]; then
		fail "these name a concrete colormath version; docs must stay 'vX.Y.Z' placeholders so they cannot rot:"
		printf '%s\n' "$hits" >&2
	else
		pass "documentation examples are still vX.Y.Z placeholders"
	fi
}

# example/ vendors two of the three vendored files and they must stay
# byte-identical to the root copies — example/ is the compliance reference, so a
# consumer reading it must see exactly what they would fetch. They are identical
# today, by hand and by luck; nothing checked.
verify_vendored_copies() {
	local f
	for f in AGENTS.colormath.md eslint.config.colormath.mjs; do
		if [ ! -f "$COLORMATH_ROOT/example/$f" ]; then
			fail "example/$f is missing — example/ must vendor the same files a consumer would"
		elif ! cmp -s "$COLORMATH_ROOT/$f" "$COLORMATH_ROOT/example/$f"; then
			fail "example/$f differs from the root copy — example/ must show consumers exactly what they'd fetch"
		else
			pass "example/$f is byte-identical to the root copy"
		fi
	done
}

verify_plugin_packaging() {
	if "$COLORMATH_ROOT/plugin/validate.sh"; then
		pass "shared Agent Skills and Claude/Codex packaging are valid"
	else
		fail "shared Agent Skills or plugin packaging validation failed"
	fi
}

verify_expect_is_a_legal_next_tag() {
	local version="$1" newest
	newest=$(newest_reachable_tag)

	if tag_exists_on_origin "$version"; then
		fail "$version already exists on origin — pick the next version, or delete the tag if it was a mistake"
	else
		pass "$version is not yet on origin"
	fi

	if [ -n "$newest" ] && ! version_gt "$version" "$newest"; then
		fail "$version does not sort above the newest reachable tag ($newest)"
	else
		pass "$version sorts above $newest"
	fi

	local today section_date
	today=$(date -u +%Y-%m-%d)
	section_date=$(sed -n "s/^## $version — \(.*\)$/\1/p" "$CHANGELOG" | head -1)
	if [ "$section_date" != "$today" ]; then
		fail "CHANGELOG.md's $version section is dated '$section_date', expected today ($today)"
	else
		pass "CHANGELOG.md's $version section is dated today"
	fi

	# notes.sh already fails on a missing or empty section.
	if "$(dirname "${BASH_SOURCE[0]}")/notes.sh" "$version" >/dev/null 2>&1; then
		pass "$version has a non-empty changelog body"
	else
		fail "$version has no non-empty changelog body"
	fi
}

# Audit an already-published tag by reading its blobs directly. No checkout, so
# this is safe to run against any tag from a dirty working tree.
audit_tag() {
	local tag="$1" g m pc px problems=""
	# Early tags predate some of these files entirely; a missing blob is "-",
	# not an error, so `|| true` guards each pipeline against pipefail.
	g=$(git -C "$COLORMATH_ROOT" show "$tag:.github/workflows/gates.yml" 2>/dev/null |
		awk '/^      colormath-ref:/{f=1;next} f&&/^      [a-z]/{exit} f&&/^        default:/{gsub(/^        default: *"?|"? *$/,"");print;exit}' || true)
	m=$(git -C "$COLORMATH_ROOT" show "$tag:Makefile.colormath" 2>/dev/null |
		sed -n 's/^COLORMATH_REF[[:space:]]*=[[:space:]]*\(v[0-9][0-9.]*\).*$/\1/p' | head -1 || true)
	pc=$(git -C "$COLORMATH_ROOT" show "$tag:plugin/.claude-plugin/plugin.json" 2>/dev/null |
		sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*$/v\1/p' | head -1 || true)
	px=$(git -C "$COLORMATH_ROOT" show "$tag:plugin/.codex-plugin/plugin.json" 2>/dev/null |
		sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*$/v\1/p' | head -1 || true)

	[ -n "$g" ] && [ "$g" != "$tag" ] && problems="${problems}gates=$g "
	[ -n "$m" ] && [ "$m" != "$tag" ] && problems="${problems}makefile=$m "
	[ -n "$pc" ] && [ "$pc" != "$tag" ] && problems="${problems}claude-plugin=$pc "
	[ -n "$px" ] && [ "$px" != "$tag" ] && problems="${problems}codex-plugin=$px "

	printf '%-10s %-10s %-10s %-10s %-10s %s\n' "$tag" "${g:--}" "${m:--}" "${pc:--}" "${px:--}" \
		"$([ -n "$problems" ] && echo "DRIFTED: $problems" || echo "consistent")"
}

main() {
	case "${1:-}" in
	--audit-all)
		# Advisory only: never exits non-zero. Published tags are immutable in
		# practice — consumers are pinned to them — so this reports history, it
		# does not gate anything.
		printf '%-10s %-10s %-10s %-10s %-10s %s\n' TAG GATES MAKEFILE CLAUDE CODEX STATUS
		local t
		for t in $(git -C "$COLORMATH_ROOT" tag --sort=v:refname); do audit_tag "$t"; done
		echo
		echo "Advisory. Published tags are never rewritten — consumers pin them."
		return 0
		;;
	--tag)
		local tag
		tag=$(normalize_version "${2:?usage: verify.sh --tag vX.Y.Z}")
		tag_exists_locally "$tag" || die "no such tag: $tag"
		printf '%-10s %-10s %-10s %-10s %-10s %s\n' TAG GATES MAKEFILE CLAUDE CODEX STATUS
		audit_tag "$tag"
		return 0
		;;
	--expect)
		local version
		version=$(normalize_version "${2:?usage: verify.sh --expect vX.Y.Z}")
		echo "Verifying the working tree is fully stamped for $version..."
		verify_worktree "$version"
		verify_expect_is_a_legal_next_tag "$version"
		verify_doc_placeholders
		verify_vendored_copies
		verify_plugin_packaging
		;;
	"")
		echo "Verifying release consistency..."
		verify_worktree
		verify_doc_placeholders
		verify_vendored_copies
		verify_plugin_packaging
		;;
	*)
		die "unknown argument: $1"
		;;
	esac

	echo
	if [ "$failures" -gt 0 ]; then
		echo "$failures check(s) failed." >&2
		echo "See LIFECYCLE.md, 'Releasing' — stamps move only in a release commit." >&2
		exit 1
	fi
	echo "All release-consistency checks passed."
}

main "$@"
