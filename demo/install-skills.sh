#!/usr/bin/env bash
# Installs open-mercato/skills at the commit in demo/SKILLS_REF into
# .claude/skills (project scope, git-ignored) and checks that the committed
# tracker descriptor comes from the same commit.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
ref=$(tr -d '[:space:]' < "$root/demo/SKILLS_REF")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

gh api "repos/open-mercato/skills/tarball/$ref" > "$tmp/skills.tgz"
mkdir "$tmp/src"
tar -xzf "$tmp/skills.tgz" -C "$tmp/src"
src=$(find "$tmp/src" -mindepth 1 -maxdepth 1 -type d)
[ -d "$src/skills" ] || { echo "tarball has no skills/ directory" >&2; exit 1; }

cmp -s "$src/skills/om-setup-agent-pipeline/references/trackers/github.md" "$root/.ai/trackers/github.md" ||
  { echo ".ai/trackers/github.md differs from the descriptor at $ref" >&2; exit 1; }

rm -rf "$root/.claude/skills"
mkdir -p "$root/.claude"
cp -R "$src/skills" "$root/.claude/skills"
printf '%s\n' "$ref" > "$root/.claude/skills.ref"
echo "Installed $(ls "$root/.claude/skills" | wc -l | tr -d ' ') skills from open-mercato/skills@$ref"
