#!/usr/bin/env bash
# Commit + push to GitHub. RingApp is iOS-only — no server, no deploy.
# Use this when you've reached a working state worth recording.

set -euo pipefail

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  echo "Usage: ./scripts/commit.sh \"commit message\"" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  echo "Not inside a git repo." >&2
  exit 1
fi
cd "$repo_root"

git add .
if git diff --cached --quiet; then
  echo "Nothing staged. Working tree clean."
  exit 0
fi

git commit -m "$1"
git push

upstream="$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo '<no upstream>')"
echo "✓ Committed $(git rev-parse --short HEAD) and pushed to $upstream"
