#!/usr/bin/env bash
# Scenario 0: the atomic primitive on real GitHub, without an agent.
#
# Each round starts two contenders with the same login on one issue. Both read
# "no lock yet", then fire the create-only ref POST together (demo/bin/gh holds
# each one until the other arrives). Expected per round: exactly one `acquired`,
# one `conflict`, and the owner's exact-SHA release leaves no ref behind. A last
# round shows that a late release by a retired owner cannot delete its successor.
#
# Usage: demo/00-helper-race.sh <issue-number> [rounds, default 10]
. "$(dirname "$0")/lib.sh"
N=${1:-}; require_number "$N"
ROUNDS=${2:-10}; require_number "$ROUNDS"
load_lock_helpers
ACTOR=$("$REAL_GH" api user --jq .login)
BASE=$(base_sha)
STARTED=$(now)
OUT="$LOG_DIR/helper-race-$N-$(date +%Y%m%dT%H%M%S)"
mkdir -p "$OUT"
export REAL_GH
[ "$(gh_get_lock issue "$N")" = null ] || die "#$N already has a lock; release it first"

contender() ( # $1 run id, $2 barrier dir
  export PATH="$DEMO_ROOT/demo/bin:$PATH" RACE_BARRIER="$2" RACE_WORKER="$1"
  gh_acquire_lock issue "$N" "$1" "$ACTOR" "$BASE"
)

status_of() { jq -r '.status // empty' "$1" 2>/dev/null | grep . || echo error; }

passed=0
rows=""
for r in $(seq 1 "$ROUNDS"); do
  barrier="$OUT/barrier-$r"; mkdir "$barrier"
  a="r$r-a-$$"; b="r$r-b-$$"
  contender "$a" "$barrier" > "$OUT/$r-a.json" 2> "$OUT/$r-a.err" & pa=$!
  contender "$b" "$barrier" > "$OUT/$r-b.json" 2> "$OUT/$r-b.err" & pb=$!
  wait "$pa" || true; wait "$pb" || true
  sa=$(status_of "$OUT/$r-a.json"); sb=$(status_of "$OUT/$r-b.json")

  owner="-"; after="-"
  if lock=$(gh_get_lock issue "$N") && [ "$lock" != null ]; then
    owner=$(printf '%s' "$lock" | jq -r .runId)
    sha=$(printf '%s' "$lock" | jq -r .sha)
    gh_release_lock issue "$N" "$sha" "$owner" "$ACTOR" > "$OUT/$r-release.txt" 2>&1 || true
    after=$(gh_get_lock issue "$N" | jq -r 'if . == null then "none" else "STILL HELD" end')
  fi

  pair=$(printf '%s\n%s\n' "$sa" "$sb" | sort | tr '\n' ' ')
  if [ "$pair" = "acquired conflict " ] && [ "$after" = none ]; then verdict="✅"; passed=$((passed + 1)); else verdict="❌"; fi
  row="| $r | $sa | $sb | \`$owner\` | $after | $verdict |"
  echo "$row"; rows="$rows$row
"
done

# Fencing: the retired owner wakes up late and tries to release "its" lock.
old=$(gh_acquire_lock issue "$N" "fence-old-$$" "$ACTOR" "$BASE" | jq -c .lock)
old_sha=$(printf '%s' "$old" | jq -r .sha); old_run=$(printf '%s' "$old" | jq -r .runId)
gh_release_lock issue "$N" "$old_sha" "$old_run" "$ACTOR" > "$OUT/fence-recovery.txt"
new=$(gh_acquire_lock issue "$N" "fence-new-$$" "$ACTOR" "$BASE" | jq -c .lock)
if gh_release_lock issue "$N" "$old_sha" "$old_run" "$ACTOR" > "$OUT/fence-stale.txt" 2>&1; then
  stale="released (unexpected)"
else
  stale="refused"
fi
kept=$(gh_get_lock issue "$N" | jq -r --arg run "fence-new-$$" 'if .runId == $run then "yes" else "no" end')
gh_release_lock issue "$N" "$(printf '%s' "$new" | jq -r .sha)" "fence-new-$$" "$ACTOR" > "$OUT/fence-final.txt"
if [ "$stale" = refused ] && [ "$kept" = yes ]; then fence="✅"; else fence="❌"; fi
echo "fencing: stale release $stale, successor kept: $kept $fence"

cat > "$OUT/report.md" <<EOF
🧪 Demo harness — atomic lock race (helper level)

Two contenders with the same login (\`$ACTOR\`) race for \`refs/om-locks/issue-$N\` in each round. Both pass the "no lock yet" read before either create is sent, so GitHub's create-only ref API picks the owner. Helpers are loaded verbatim from \`.ai/trackers/github.md\` at open-mercato/skills@\`${SKILLS_REF:0:7}\`.

**Result: $passed/$ROUNDS rounds with exactly one owner and a clean release.**

| Round | Contender A | Contender B | Owner run | Lock after owner's release | |
|---|---|---|---|---|---|
$rows
**Fencing $fence:** an old owner released by recovery tried to release its lock again after a successor took the issue. Result: $stale. Successor kept: $kept.

Started $STARTED, raw output in \`.demo/$(basename "$OUT")\` on the presenter's machine.
EOF
post_report "$N" "$OUT/report.md"
[ "$passed" = "$ROUNDS" ] && [ "$fence" = "✅" ]
