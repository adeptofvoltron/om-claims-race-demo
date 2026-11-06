# Shared helpers for the demo scripts. Source it; do not execute it.
set -eu

DEMO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DESCRIPTOR="$DEMO_ROOT/.ai/trackers/github.md"
SKILLS_REF=$(tr -d '[:space:]' < "$DEMO_ROOT/demo/SKILLS_REF")
LOG_DIR="$DEMO_ROOT/.demo"
mkdir -p "$LOG_DIR"
REPO=${REPO:-$(cd "$DEMO_ROOT" && gh repo view --json nameWithOwner --jq .nameWithOwner)}
REAL_GH=$(command -v gh)

# The shipped helpers address the target repository through tracker_repo.
tracker_repo() { printf '%s\n' "$REPO"; }

die() { echo "error: $*" >&2; exit 1; }

require_number() {
  case "${1:-}" in ''|*[!0-9]*) die "expected a number, got '${1:-}'" ;; esac
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

issue_url() { printf 'https://github.com/%s/issues/%s\n' "$REPO" "$1"; }

# Head commit of the default branch: the base every lock metadata commit hangs off.
base_sha() {
  branch=$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name) || return 1
  sha=$(gh api "repos/$REPO/commits/$branch" --jq .sha) || return 1
  printf '%s' "$sha" | grep -Eq '^[0-9a-f]{40}$' || die "cannot resolve the head of $branch"
  printf '%s\n' "$sha"
}

# Loads the lock helpers verbatim from the pinned descriptor, so the demo runs
# exactly the code the skills run.
load_lock_helpers() {
  awk '/^gh_(lock_target|get_lock|acquire_lock|release_lock|get_claim_reset)\(\) \{$/ { f = 1 }
       f { print }
       f && /^}$/ { f = 0 }' "$DESCRIPTOR" > "$LOG_DIR/lock-helpers.sh"
  for fn in gh_lock_target gh_get_lock gh_acquire_lock gh_release_lock gh_get_claim_reset; do
    grep -q "^$fn() {" "$LOG_DIR/lock-helpers.sh" || die "descriptor lacks $fn"
  done
  . "$LOG_DIR/lock-helpers.sh"
}

# Agent scenarios need the skills from the pinned commit installed in this checkout.
require_skills() {
  command -v claude >/dev/null || die "the claude CLI is not on PATH"
  [ "$(cat "$DEMO_ROOT/.claude/skills.ref" 2>/dev/null)" = "$SKILLS_REF" ] ||
    die "skills at $SKILLS_REF are not installed; run demo/install-skills.sh"
}

# Prints the ownership state of one issue: lock ref, labels, assignees, claim comments.
snapshot() {
  echo "### #$1 at $(now)"
  if lock=$(gh_get_lock issue "$1"); then
    if [ "$lock" = null ]; then echo "lock:      none"
    else printf '%s' "$lock" | jq -r '"lock:      \(.ref) @ \(.sha[0:12]) run=\(.runId) actor=\(.actor) created=\(.createdAt)"'; fi
  else echo "lock:      UNREADABLE"; fi
  gh issue view "$1" --repo "$REPO" --json labels,assignees \
    --jq '"labels:    " + ([.labels[].name] | join(", ")) + "\nassignees: " + ([.assignees[].login] | join(", "))'
  gh api --paginate "repos/$REPO/issues/$1/comments?per_page=100" --jq '.[]
    | select(.body | test("Claim-Run:"))
    | "claim:     comment \(.id) by \(.user.login) at \(.created_at) state=" + ([.body | scan("Claim-State: ([a-z]+)")] | .[0][0] // "?")'
}

# True when the issue has a readable lock and the in-progress label.
owned() {
  lock=$(gh_get_lock issue "$1") || return 1
  [ "$lock" != null ] || return 1
  gh issue view "$1" --repo "$REPO" --json labels \
    --jq '[.labels[].name] | index("in-progress") != null' | grep -qx true
}

# Logs every change of the repository's lock refs (with owner run ids) until
# all given pids exit. $1 = output dir, then pids.
watch_locks() {
  out=$1; shift; last=unset
  while :; do
    alive=0
    for pid in "$@"; do kill -0 "$pid" 2>/dev/null && alive=1; done
    raw=$(gh api "repos/$REPO/git/matching-refs/om-locks/" --jq '.[] | .ref + " " + .object.sha' 2>/dev/null) || raw=unreadable
    # LOCK_FILTER (an extended regex on refs) keeps parallel scenarios' timelines apart.
    if [ -n "${LOCK_FILTER:-}" ] && [ "$raw" != unreadable ]; then
      raw=$(printf '%s\n' "$raw" | grep -E "$LOCK_FILTER" || true)
    fi
    if [ "$raw" != "$last" ]; then
      if [ -z "$raw" ]; then state="no lock refs"
      elif [ "$raw" = unreadable ]; then state="lock listing unreadable"
      else
        state=$(printf '%s\n' "$raw" | while read -r ref sha; do
          name=${ref#refs/om-locks/}
          run=$(gh_get_lock "${name%%-*}" "${name#*-}" 2>/dev/null | jq -r '.runId // "?"' 2>/dev/null) || run="?"
          printf '%s @ %s run=%s; ' "$name" "${sha:0:12}" "${run:-?}"
        done)
      fi
      echo "[$(now)] locks: $state" | tee -a "$out/timeline.txt"
      last=$raw
    fi
    [ "$alive" = 1 ] || break
    sleep 5
  done
}

# Headless agent flags. Only project/local settings load, so the presenter's
# personal hooks and plugins cannot change how the skills behave.
AGENT_FLAGS="--permission-mode bypassPermissions --setting-sources project,local --output-format stream-json --verbose"

# Runs one headless agent session. $1 label, $2 prompt, $3 output dir,
# $4 optional epoch second to start at (so two runs start together).
run_agent() {
  if [ -n "${4:-}" ]; then while [ "$(date +%s)" -lt "$4" ]; do sleep 0.1; done; fi
  echo "[$(now)] run $1 started: $2" | tee -a "$3/timeline.txt"
  # shellcheck disable=SC2086 # AGENT_FLAGS is a word list
  (cd "$DEMO_ROOT" && exec claude -p "$2" $AGENT_FLAGS) > "$3/run-$1.jsonl" 2> "$3/run-$1.err" || true
  jq -r 'select(.type == "result") | .result' "$3/run-$1.jsonl" > "$3/result-$1.md" 2>/dev/null || true
  echo "[$(now)] run $1 finished" | tee -a "$3/timeline.txt"
}

# First lines of an agent's final report, with the local home directory masked.
excerpt() {
  head -n "${2:-15}" "$1" 2>/dev/null | sed "s|$HOME|~|g"
}

# Posts a harness comment on the issue. Harness comments use the 🧪 prefix and
# never the 🤖 skill marker, so claim parsers ignore them.
post_report() { # $1 issue, $2 body file
  gh issue comment "$1" --repo "$REPO" --body-file "$2" >/dev/null
  echo "Report posted on $(issue_url "$1")"
}
