#!/usr/bin/env bash
# Scenario 1: two real agent runs of one skill start together on one issue,
# with the same GitHub login.
#
# Expected: one run takes the lock, posts the claim comment, applies
# in-progress and does the work. The other stops and names the owner before
# it writes anything (no comment, label or assignment). At the end the lock
# ref is gone and the issue carries one set of results.
#
# Usage: demo/01-skill-race.sh <issue-number> [skill, default om-auto-fix-issue]
. "$(dirname "$0")/lib.sh"
N=${1:-}; require_number "$N"
SKILL=${2:-om-auto-fix-issue}
case "$SKILL" in om-*) ;; *) die "skill must be an om-* name" ;; esac
require_skills
load_lock_helpers
STARTED=$(now)
OUT="$LOG_DIR/skill-race-$N-$(date +%Y%m%dT%H%M%S)"
mkdir -p "$OUT"
snapshot "$N" | tee "$OUT/before.txt"

start=$(( $(date +%s) + 5 ))
run_agent A "/$SKILL $N" "$OUT" "$start" & pa=$!
run_agent B "/$SKILL $N" "$OUT" "$start" & pb=$!
watch_locks "$OUT" "$pa" "$pb"
wait "$pa" || true; wait "$pb" || true

snapshot "$N" | tee "$OUT/after.txt"
claims=$(grep -c '^claim:' "$OUT/after.txt" || true)

cat > "$OUT/report.md" <<EOF
🧪 Demo harness — skill race: two \`$SKILL\` runs on #$N

Two headless Claude Code sessions started at the same second with the same GitHub login, each running \`/$SKILL $N\` with skills from open-mercato/skills@\`${SKILLS_REF:0:7}\`. Expected: one owner works, the other stops naming the owner before writing anything; afterwards no lock remains. Claim comments with \`Claim-Run\` after the race: **$claims**.

<details><summary>Lock timeline (UTC)</summary>

\`\`\`text
$(cat "$OUT/timeline.txt")
\`\`\`
</details>

<details><summary>Run A: final report (excerpt)</summary>

$(excerpt "$OUT/result-A.md")
</details>

<details><summary>Run B: final report (excerpt)</summary>

$(excerpt "$OUT/result-B.md")
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
