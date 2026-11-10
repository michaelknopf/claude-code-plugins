#!/usr/bin/env bash
# Print the report directory path for the current git branch.
# Normalizes branch names into filesystem-safe slugs by replacing any
# character that isn't [A-Za-z0-9._-] with a single dash, and collapsing
# runs of dashes. This handles forward slashes, colons, spaces, and other
# characters that can legally appear in git refs but are awkward in paths.
#
# Usage: branch-report-dir.sh
# Output: docs/local/reports/<slug>
#
# Exits non-zero if not in a git repo or HEAD is detached with no branch name.

set -euo pipefail

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
  echo "error: detached HEAD or no branch name" >&2
  exit 1
fi

# Replace any non-safe char with `-`, then collapse repeats, then trim leading/trailing dashes.
SLUG=$(printf '%s' "$BRANCH" \
  | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/-+/-/g; s/^-//; s/-$//')

printf 'docs/local/reports/%s\n' "$SLUG"
