#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${1:-https://github.com/pwoodman/python-mastery-skills.git}"
INSTALL_ROOT="${CLAUDE_SKILLS_ROOT:-$HOME/.claude/skills}"
SKILL_NAME="python-mastery"
TARGET="${INSTALL_ROOT}/${SKILL_NAME}"

echo "Installing Python Mastery skill..."

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is required but was not found on PATH." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/python-mastery-skills.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$INSTALL_ROOT"
rm -rf "$TARGET"

git clone --depth 1 "$REPO_URL" "$TMP_DIR/repo" >/dev/null

if [[ ! -d "$TMP_DIR/repo/docs" ]]; then
  echo "Error: expected docs directory not found in cloned repository." >&2
  exit 1
fi

mkdir -p "$TARGET"
cp -R "$TMP_DIR/repo/docs/." "$TARGET/"

echo "Installed to $TARGET"
echo "Restart Claude Code to use the skill."
