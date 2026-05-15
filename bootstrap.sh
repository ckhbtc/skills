#!/usr/bin/env bash
# Bootstrap script for ckhbtc/skills.
#
# Wires this repo's skills into the two-layer symlink chain Claude Code uses:
#
#   ~/dev/skills/<name>/         (this repo — source of truth)
#   ~/.agents/skills/<name>      -> ~/dev/skills/<name>            (symlink farm)
#   ~/.claude/skills/<name>      -> ../../.agents/skills/<name>    (loaded view)
#
# The farm at ~/.agents/skills/ is a real directory that can also hold
# symlinks from other source repos (matt-pocock, InjectiveLabs/agent-skills,
# etc.). This script only manages entries for SKILLS IN THIS REPO. To add
# a skill from another source, symlink it into ~/.agents/skills/ manually,
# then re-run this script to pick it up in ~/.claude/skills/.
#
# Run this after cloning the repo (anywhere — the script auto-detects its
# location). Idempotent: re-run after `git pull` or after adding a new
# external source to the farm.

set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
FARM_DIR="${FARM_DIR:-$HOME/.agents/skills}"
TARGET_DIR="${TARGET_DIR:-$HOME/.claude/skills}"

if [[ ! -d "$REPO_DIR" ]]; then
  echo "error: REPO_DIR=$REPO_DIR does not exist"
  exit 1
fi

mkdir -p "$FARM_DIR" "$TARGET_DIR"

# If FARM_DIR is itself a symlink (legacy layout where ~/.agents/skills was
# a directory symlink to the repo), bail out — that's incompatible with the
# multi-source layout this script targets.
if [[ -L "$FARM_DIR" ]]; then
  echo "error: $FARM_DIR is a symlink (legacy layout). Convert it to a real"
  echo "       directory first:"
  echo "         rm $FARM_DIR && mkdir $FARM_DIR"
  echo "       Then re-run this script."
  exit 1
fi

farm_linked=0
farm_skipped=0
linked=0
skipped=0
existing=0
removed_stale=0

# --- Cleanup: remove stale ~/.claude/skills/<old-name> symlinks for renamed skills.
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

# --- Step 1: ensure every skill in THIS repo has a symlink in the farm.
for skill_path in "$REPO_DIR"/*/; do
  name="$(basename "$skill_path")"

  if [[ ! -f "$skill_path/SKILL.md" ]]; then
    continue
  fi

  link_path="$FARM_DIR/$name"
  abs_target="$REPO_DIR/$name"

  if [[ -L "$link_path" ]]; then
    current="$(readlink "$link_path")"
    # Tolerate optional trailing slash on either side
    if [[ "${current%/}" == "${abs_target%/}" ]]; then
      farm_skipped=$((farm_skipped+1))
      continue
    fi
    echo "warn: $link_path -> '$current' (expected '$abs_target') — leaving alone"
    continue
  fi

  if [[ -e "$link_path" ]]; then
    echo "warn: $link_path exists (not a symlink) — leaving alone"
    continue
  fi

  ln -s "$abs_target" "$link_path"
  farm_linked=$((farm_linked+1))
  echo "farm: $link_path -> $abs_target"
done

# --- Step 2: ensure every entry in the farm has a symlink in Claude's load path.
# This picks up skills from this repo AND from any other source (matt-pocock,
# agent-skills, etc.) that's been symlinked into the farm.
for skill_path in "$FARM_DIR"/*/; do
  name="$(basename "$skill_path")"

  if [[ ! -f "$skill_path/SKILL.md" ]]; then
    continue
  fi

  link_path="$TARGET_DIR/$name"
  expected="../../.agents/skills/$name"

  if [[ -L "$link_path" ]]; then
    current_target="$(readlink "$link_path")"
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

  ln -s "$expected" "$link_path"
  linked=$((linked+1))
  echo "linked: $link_path -> $expected"
done

echo ""
echo "summary:"
echo "  farm   (~/.agents/skills): $farm_linked new, $farm_skipped already correct"
echo "  claude (~/.claude/skills): $linked new, $skipped already correct, $removed_stale stale removed, $existing left alone"
