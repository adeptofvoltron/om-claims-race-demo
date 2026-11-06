#!/usr/bin/env bash
# Scenario 2: crash, block, human reset, recovery.
#
# 1. Run A starts. As soon as it owns the issue (lock ref + in-progress) the
#    script kills its whole process group with SIGKILL, like a crashed worker.
# 2. Run B starts and must stop: the dead run's lock still owns the issue.
# 3. A human adds the `claim-reset` label in the GitHub UI. The script waits
#    until the audited label event (newer than the crash) is visible.
# 4. Run C verifies the human reset, retires the dead generation by its exact
#    SHA, takes the issue, finishes and releases.
#
# Usage: demo/02-crash-recovery.sh <issue-number> [skill, default om-auto-fix-issue]
. "$(dirname "$0")/lib.sh"
N=${1:-}; require_number "$N"
SKILL=${2:-om-auto-fix-issue}
case "$SKILL" in om-*) ;; *) die "skill must be an om-* name" ;; esac
require_skills
load_lock_helpers
[ "$(gh_get_lock issue "$N")" = null ] || die "#$N already has a lock; pick a free issue"
STARTED=$(now)
OUT="$LOG_DIR/crash-recovery-$N-$(date +%Y%m%dT%H%M%S)"
mkdir -p "$OUT"
snapshot "$N" | tee "$OUT/before.txt"

# Job control gives the background agent its own process group, so the kill
# takes its tool subprocesses down with it.
set -m
# shellcheck disable=SC2086 # AGENT_FLAGS is a word list
(cd "$DEMO_ROOT" && exec claude -p "/$SKILL $N" $AGENT_FLAGS) > "$OUT/run-A.jsonl" 2> "$OUT/run-A.err" &
pa=$!
set +m
echo "[$(now)] run A started (pid $pa)" | tee -a "$OUT/timeline.txt"
deadline=$(( $(date +%s) + 900 ))
until owned "$N"; do
  kill -0 "$pa" 2>/dev/null || die "run A exited before it owned #$N; see $OUT"
  [ "$(date +%s)" -lt "$deadline" ] || { kill -9 -- "-$pa"; die "run A did not claim #$N within 15 minutes"; }
  sleep 2
done
kill -9 -- "-$pa" 2>/dev/null || true
wait "$pa" 2>/dev/null || true
CRASHED_AT=$(now)
echo "[$CRASHED_AT] run A owned #$N and was killed with SIGKILL" | tee -a "$OUT/timeline.txt"
snapshot "$N" | tee "$OUT/after-crash.txt"

run_agent B "/$SKILL $N" "$OUT"
snapshot "$N" | tee "$OUT/after-B.txt"

echo
echo ">>> Human step: open $(issue_url "$N") and add the label 'claim-reset' in the sidebar."
echo ">>> Waiting for the audited label event (newer than $CRASHED_AT)…"
deadline=$(( $(date +%s) + 3600 ))
until reset=$(gh_get_claim_reset "$N" 2>/dev/null) && [ "$reset" != null ] &&
      printf '%s' "$reset" | jq -e --arg t "$CRASHED_AT" '.createdAt > $t' >/dev/null; do
  [ "$(date +%s)" -lt "$deadline" ] || die "no human claim-reset within an hour"
  sleep 5
done
echo "[$(now)] verified human reset: $(printf '%s' "$reset" | jq -c .)" | tee -a "$OUT/timeline.txt"

run_agent C "/$SKILL $N" "$OUT" & pc=$!
watch_locks "$OUT" "$pc"
wait "$pc" || true
snapshot "$N" | tee "$OUT/after-C.txt"

cat > "$OUT/report.md" <<EOF
🧪 Demo harness — crash and human reset: \`$SKILL\` on #$N

Skills from open-mercato/skills@\`${SKILLS_REF:0:7}\`. Expected: run B stops while the killed run A still owns the lock; after a human applies \`claim-reset\`, run C retires A's lock by its exact SHA, does the work and releases.

<details><summary>Timeline (UTC)</summary>

\`\`\`text
$(cat "$OUT/timeline.txt")
\`\`\`
</details>

<details><summary>State right after run A was killed</summary>

\`\`\`text
$(cat "$OUT/after-crash.txt")
\`\`\`
</details>

<details><summary>Run B: final report (excerpt)</summary>

$(excerpt "$OUT/result-B.md")
</details>

<details><summary>Run C: final report (excerpt)</summary>

$(excerpt "$OUT/result-C.md")
</details>

<details><summary>Final state</summary>

\`\`\`text
$(cat "$OUT/after-C.txt")
\`\`\`
</details>

Started $STARTED, raw logs in \`.demo/$(basename "$OUT")\` on the presenter's machine. Remove the \`claim-reset\` label when you are done; it is a breadcrumb, not a standing bypass.
EOF
post_report "$N" "$OUT/report.md"
