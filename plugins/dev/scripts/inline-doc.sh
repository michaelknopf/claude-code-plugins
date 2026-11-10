#!/usr/bin/env bash
# Inline one of our canonical docs into a skill/agent/command body.
#
# Two things this does that a bare `cat` cannot:
#
#   1. Strips the front matter, and only the front matter. The block is
#      recognized solely when `---` is the very first line, so a horizontal rule
#      mid-document survives — `sed '1,/^---$/d'` would truncate the doc there.
#   2. Emits a warning when the doc cannot be read. An empty inline is the
#      dangerous failure: the agent proceeds believing no guidance applies. Say
#      so instead.
#
# Usage: inline-doc.sh "${CLAUDE_PLUGIN_ROOT}/docs/<name>.md"
#
# Callers pass the full path because Claude Code substitutes ${CLAUDE_PLUGIN_ROOT}
# into the text of a `!` line but does not export it to the shell that runs it.

set -euo pipefail

doc="${1:-}"

warn() {
  printf '> [!WARNING]\n'
  printf '> Could not load the guidance at `%s` (%s).\n' "${doc:-<none>}" "$1"
  printf '> It is MISSING here, not empty — do not assume no guidance applies.\n'
  printf '> Find that file under `plugins/dev/docs/` in the claude-code-plugins repo and read it.\n'
}

if [[ -z "$doc" ]]; then
  warn "no doc path given"
  exit 0
fi

if [[ ! -r "$doc" ]]; then
  warn "no readable file there"
  exit 0
fi

# Front matter only when `---` opens the file; print from the line after the
# closing delimiter. Otherwise print everything.
awk '
  NR == 1 && $0 == "---" { in_fm = 1; next }
  in_fm && $0 == "---"   { in_fm = 0; next }
  in_fm                  { next }
                         { print }
' "$doc"
