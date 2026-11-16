#!/bin/sh
# Verify the parts of this skill that can silently rot.
#
# A skill that names a tool the binary does not have is worse than no skill, because the
# agent will call it and get a protocol error instead of an answer.
set -eu
cd "$(dirname "$0")"
fail=0
note() { printf '  %s\n' "$1"; fail=1; }

printf 'frontmatter\n'
head -1 SKILL.md | grep -qx -- '---' || note "SKILL.md does not open with ---"
sed -n '2,/^---$/p' SKILL.md | grep -q '^name: ' || note "no name: in the frontmatter"
sed -n '2,/^---$/p' SKILL.md | grep -q '^description: ' || note "no description: in the frontmatter"

printf 'links resolve\n'
links=$(grep -o '](\([^)]*\.md\))' SKILL.md | sed 's/^](//;s/)$//' | sort -u)
for l in $links; do
	[ -f "$l" ] || note "SKILL.md links to $l, which does not exist"
done

printf 'nothing orphaned\n'
for f in reference/*.md; do
	printf '%s\n' "$links" | grep -qx -- "$f" || note "$f is not linked from SKILL.md"
done

printf 'tool names match the binary\n'
if command -v spawn >/dev/null 2>&1; then
	# tools/list over stdio. stderr is dropped: spawn mcp puts its own logging there.
	live=$(printf '%s\n' \
		'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"check","version":"0"}}}' \
		'{"jsonrpc":"2.0","id":2,"method":"tools/list"}' |
		spawn mcp 2>/dev/null | grep -o '"spawn_[a-z][a-z]*"' | tr -d '"' | sort -u)
	[ -n "$live" ] || note "spawn mcp returned no tools"
	documented=$(grep -rho 'spawn_[a-z][a-z]*' SKILL.md reference/ | sort -u)
	for t in $live; do
		printf '%s\n' "$documented" | grep -qx -- "$t" || note "$t exists but is documented nowhere"
	done
	for t in $documented; do
		printf '%s\n' "$live" | grep -qx -- "$t" || note "$t is documented but the binary has no such tool"
	done
else
	printf '  spawn not installed, skipping\n'
fi

[ "$fail" -eq 0 ] && printf '\nok\n' || printf '\nFAILED\n'
exit "$fail"
