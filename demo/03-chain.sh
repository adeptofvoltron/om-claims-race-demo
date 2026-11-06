#!/usr/bin/env bash
# Scenario 3: one full chain on one issue (verify, fix, open PR, review).
#
# The lock must keep one owner run across every hand-off: no step blocks on its
# own run's lock, and the issue never looks unclaimed mid-chain. At the end the
# lock refs are gone. With a single GitHub account the review step cannot
# approve its own PR; the skill is expected to report that, not work around it.
#
# Usage: demo/03-chain.sh <issue-number> [skill, default om-auto-fix-issue]
. "$(dirname "$0")/lib.sh"
N=${1:-}; require_number "$N"
SKILL=${2:-om-auto-fix-issue}
case "$SKILL" in om-*) ;; *) die "skill must be an om-* name" ;; esac
require_skills
load_lock_helpers
STARTED=$(now)
OUT="$LOG_DIR/chain-$N-$(date +%Y%m%dT%H%M%S)"
mkdir -p "$OUT"
snapshot "$N" | tee "$OUT/before.txt"

run_agent A "/$SKILL $N" "$OUT" & pa=$!
watch_locks "$OUT" "$pa"
wait "$pa" || true
snapshot "$N" | tee "$OUT/after.txt"

issue_runs=$(sed -n 's/.*issue-'"$N"' @ [0-9a-f]* run=\([^;]*\);.*/\1/p' "$OUT/timeline.txt" | sort -u | grep -c . || true)

cat > "$OUT/report.md" <<EOF
🧪 Demo harness — chain: \`$SKILL\` on #$N

Skills from open-mercato/skills@\`${SKILLS_REF:0:7}\`. Expected: the issue lock keeps a single owner run through every hand-off (distinct owner runs seen for \`issue-$N\`: **$issue_runs**), no step stops on its own lock, and no lock remains at the end.

<details><summary>Lock timeline (UTC)</summary>

\`\`\`text
$(cat "$OUT/timeline.txt")
\`\`\`
</details>

<details><summary>Final report (excerpt)</summary>

$(excerpt "$OUT/result-A.md" 25)
</details>

<details><summary>Ownership state before and after</summary>

\`\`\`text
$(cat "$OUT/before.txt")

$(cat "$OUT/after.txt")
\`\`\`
</details>

Started $STARTED, raw logs in \`.demo/$(basename "$OUT")\` on the presenter's machine.
EOF
post_report "$N" "$OUT/report.md"
