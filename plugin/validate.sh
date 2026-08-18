#!/usr/bin/env bash
# Validate the shared Agent Skills tree and both host packaging manifests.

set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skills_root="$plugin_root/skills"
claude_manifest="$plugin_root/.claude-plugin/plugin.json"
codex_manifest="$plugin_root/.codex-plugin/plugin.json"
expected_skills=7

fail() {
	echo "error: $*" >&2
	exit 1
}

skill_files=("$skills_root"/*/SKILL.md)
[ "${#skill_files[@]}" -eq "$expected_skills" ] ||
	fail "expected $expected_skills canonical skills, found ${#skill_files[@]}"

for manifest in "$claude_manifest" "$codex_manifest"; do
	python3 -m json.tool "$manifest" >/dev/null || fail "invalid JSON: $manifest"
	grep -Eq '"skills"[[:space:]]*:[[:space:]]*"\./skills/"' "$manifest" ||
		fail "$manifest must point skills at ./skills/"
done

claude_version=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*$/\1/p' "$claude_manifest" | head -1)
codex_version=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*$/\1/p' "$codex_manifest" | head -1)
[ -n "$claude_version" ] && [ "$claude_version" = "$codex_version" ] ||
	fail "Claude and Codex plugin manifests must share one release version"

for skill_file in "${skill_files[@]}"; do
	skill_dir=$(basename "$(dirname "$skill_file")")
	skill_name=$(sed -n 's/^name:[[:space:]]*//p' "$skill_file" | head -1)
	[ "$skill_name" = "$skill_dir" ] ||
		fail "$skill_file name '$skill_name' must match directory '$skill_dir'"
	grep -q '^description:[[:space:]]*[^[:space:]]' "$skill_file" ||
		fail "$skill_file needs a non-empty description"
	grep -q '^compatibility:[[:space:]]*[^[:space:]]' "$skill_file" ||
		fail "$skill_file needs compatibility metadata for required host capabilities"
done

# Canonical skills must stay portable. Host-specific installation and invocation
# examples belong in clearly labeled documentation sections outside skills/.
forbidden='\$ARGUMENTS|/colormath:|AskUserQuestion|multiSelect|mcp__[[:alnum:]_]+|claude-sonnet|CLAUDE\.md|`(Bash|Read|Edit|Write|Grep|Glob|Skill)`|^(allowed-tools|argument-hint|model):'
if hits=$(grep -nEH "$forbidden" "${skill_files[@]}" 2>/dev/null); then
	echo "$hits" >&2
	fail "host-specific constructs found in canonical skills"
fi

if command -v skills-ref >/dev/null 2>&1; then
	for skill_file in "${skill_files[@]}"; do
		skills-ref validate "$(dirname "$skill_file")"
	done
	echo "ok: Agent Skills reference validator passed all ${#skill_files[@]} skills"
elif command -v agentskills >/dev/null 2>&1; then
	for skill_file in "${skill_files[@]}"; do
		agentskills validate "$(dirname "$skill_file")"
	done
	echo "ok: Agent Skills reference validator passed all ${#skill_files[@]} skills"
else
	echo "skip: skills-ref/agentskills is not installed; portable fallback checks passed"
fi

skill_names=$(printf '%s\n' "${skill_files[@]}" | sed -E 's|.*/skills/([^/]+)/SKILL.md|\1|' | paste -sd, -)
echo "ok: Claude and Codex manifests discover ${#skill_files[@]} shared skills: $skill_names"
