#!/usr/bin/env bash
# Bootstrap script for ckhbtc/skills.
#
# Walks every skill directory in this repo and creates a corresponding
# symlink at ~/.claude/skills/<name> -> ../../.agents/skills/<name>.
# That's the path Claude Code actually loads from; the canonical files
# live under ~/.agents/skills/.
#
# Run this on a fresh machine after cloning the repo to ~/.agents/skills/.
# Idempotent: re-running won't break existing correct symlinks. Existing
# real directories at ~/.claude/skills/<name> (e.g. plugin-managed copies)
# are left alone — fix those manually first if you want them symlinked.

set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/.agents/skills}"
TARGET_DIR="${TARGET_DIR:-$HOME/.claude/skills}"

if [[ ! -d "$REPO_DIR" ]]; then
  echo "error: $REPO_DIR does not exist. Clone the repo there first:"
  echo "  git clone git@github.com:ckhbtc/skills.git \"$REPO_DIR\""
  exit 1
fi

mkdir -p "$TARGET_DIR"

linked=0
skipped=0
existing=0
removed_stale=0

RENAMED_SKILLS=(
  "injective-trade:injective-orderbook-trade"
  "injective-autosign:injective-orderbook-autosign"
  "injective-market-data:injective-derivatives-market-data"
)

for rename in "${RENAMED_SKILLS[@]}"; do
  old_name="${rename%%:*}"
  new_name="${rename#*:}"
  link_path="$TARGET_DIR/$old_name"
  expected_old="../../.agents/skills/$old_name"

  if [[ ! -L "$link_path" ]]; then
    continue
  fi

  current_target="$(readlink "$link_path")"
  if [[ "$current_target" == "$expected_old" && -f "$REPO_DIR/$new_name/SKILL.md" ]]; then
    rm "$link_path"
    removed_stale=$((removed_stale+1))
    echo "removed stale symlink: $link_path (renamed to $new_name)"
  fi
done

for skill_path in "$REPO_DIR"/*/; do
  name="$(basename "$skill_path")"

  # Only link directories that actually contain a SKILL.md
  if [[ ! -f "$skill_path/SKILL.md" ]]; then
    continue
  fi

  link_path="$TARGET_DIR/$name"

  if [[ -L "$link_path" ]]; then
    current_target="$(readlink "$link_path")"
    expected="../../.agents/skills/$name"
    if [[ "$current_target" == "$expected" ]]; then
      skipped=$((skipped+1))
      continue
    fi
    echo "warn: $link_path is a symlink to '$current_target' (expected '$expected') — skipping"
    existing=$((existing+1))
    continue
  fi

  if [[ -e "$link_path" ]]; then
    echo "warn: $link_path exists as a real path (not a symlink) — skipping"
    existing=$((existing+1))
    continue
  fi

  ln -s "../../.agents/skills/$name" "$link_path"
  linked=$((linked+1))
  echo "linked: $link_path -> ../../.agents/skills/$name"
done

echo ""
echo "summary: $linked new symlink(s), $skipped already correct, $removed_stale stale symlink(s) removed, $existing existing path(s) left alone"
