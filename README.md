# om-claims-race-demo

A public, disposable test bed for [open-mercato/skills PR #176](https://github.com/open-mercato/skills/pull/176),
"fix(claims): elect one run before claiming work". It runs the PR's claim
protocol against a real GitHub repository, so every claim, conflict, label,
lock ref and release is visible in this repo's issues and refs.

## What the PR changes

Before the PR, a skill claimed an issue or PR by reading (assignee, `in-progress`,
claim comment) and then writing. Two runs starting close together could both
read "free" and both do the work. The PR makes each run first create the Git
ref `refs/om-locks/{kind}-{number}` through GitHub's create-only API. Only one
create can succeed, so only one run owns the item; the loser stops before
writing anything. The owner releases the ref last, with an expected-SHA Git
lease, so a late or stale release cannot delete a successor's lock.

Everything here runs the PR head, `open-mercato/skills@9c0ef49` (pinned in
`demo/SKILLS_REF`). The tracker descriptor in `.ai/trackers/github.md` is a
verbatim copy from that commit; `demo/install-skills.sh` refuses to run if it drifts.

## Scenarios

| # | Script | Shows | Cost |
|---|---|---|---|
| 0 | `demo/00-helper-race.sh <issue> [rounds]` | The atomic primitive under true simultaneity: two same-login contenders reach the create-only POST together; one `acquired`, one `conflict`, clean release. Plus fencing: a retired owner's late release cannot delete its successor. | API calls only, ~1 min |
| 1 | `demo/01-skill-race.sh <issue> [skill]` | Two real agent runs (default `om-auto-fix-issue`) start in the same second. One claims and works; the other stops naming the owner and writes nothing to the tracker. The winner continues the whole chain, so the timeline also shows the lock moving from the issue to the PR. | 2 agent sessions, one full chain |
| 2 | `demo/02-crash-recovery.sh <issue> [skill]` | The owner is killed with SIGKILL right after it claims. A second run is blocked. A human adds `claim-reset`; a third run retires the dead lock by its exact SHA and finishes. | 3 agent sessions + 1 label |
| 3 | `demo/03-chain.sh <issue> [skill]` | One `om-auto-fix-issue` chain on its own (verify, root cause, fix, PR, review): one owner run across every hand-off, no self-block, no unclaimed gap. Optional, since scenario 1's winner shows the same. | 1 long agent session |

`om-auto-fix-issue` claims in its `om-fix` step, after the read-only triage
and root-cause steps, so in scenario 1 the second run usually finds the lock
already taken rather than racing the create itself. Scenario 0 covers the
truly simultaneous create.

Each script prints a timeline, and posts a `🧪 Demo harness` report on the issue
it targeted. Raw agent logs stay in `.demo/` (git-ignored) on the machine that ran them.

| Issue | Use it for |
|---|---|
| [#1](../../issues/1) | Scenario 0 |
| [#2](../../issues/2) | Observation: scenario 1's script with `om-auto-manage-issues`, a skill that takes no lock |
| [#3](../../issues/3) | Scenario 2 |
| [#4](../../issues/4) | Scenario 1 (and the chain) |

## Results

| What | Result |
|---|---|
| PR's own validation gate (10 commands from `.ai/agentic.config.json`, run locally on `9c0ef49`) | ✅ all exit 0, including the new atomic-claim, claim-protocol and GitLab/Forgejo lock tests |
| Scenario 0 on [#1](../../issues/1) | ✅ 10/10 rounds with exactly one owner (A won 5, B won 5); in every round both contenders reached the create-only POST before either was sent. A late release by a retired owner was refused and the successor kept its lock. No lock ref left behind. |
| Side effects of lock refs | ✅ ~24 creates/deletes under `refs/om-locks/` started no workflow run (the only run is the initial push to `main`). |
| Two `om-auto-manage-issues` runs on [#2](../../issues/2) | ⚠️ Not protected. The skill is skip-only by design ("a light housekeeping pass, so it does not take its own long-lived `in-progress` lock"): both runs saw no lock, both did the work. Each of its four comments is on the issue twice, and both runs rewrote the issue body seven seconds apart. |
| Scenarios 1–2 with `om-auto-fix-issue` | _running_ |

## Setup

Requirements: `gh` authenticated with `repo` scope and wired as the Git
credential helper (`gh auth setup-git`), because lock release goes through
`git push`, not the REST API. Also `jq`, Node.js 20+, and the `claude` CLI for
scenarios 1–3.

```bash
gh repo clone adeptofvoltron/om-claims-race-demo && cd om-claims-race-demo
demo/install-skills.sh      # skills from the pinned commit into .claude/skills
demo/setup-labels.sh        # idempotent; in-progress must exist or claims block
```

## During a presentation

- Watch locks live: `git ls-remote origin 'refs/om-locks/*'`
- Ownership of one issue: `bash -c '. demo/lib.sh; load_lock_helpers; snapshot 2'`
- Claim comments carry `Claim-Run`, `Claim-Lock` and `Claim-Lock-SHA`; the
  losing run in a race leaves no comment at all.
- The Actions tab shows whether lock-ref pushes start workflow runs (the
  workflow here is deliberately unfiltered).

## Limits of this demo

- One GitHub account plays every role. That is the realistic case for two
  scheduled bot runs, but it cannot show that a `claim-reset` applied by a bot
  is ignored, and the review step cannot approve a PR from the same account.
- Only GitHub. The PR's GitLab and Forgejo helpers are covered by its own
  tests with real Git and mocked APIs, not here.
- Agent runs use `--permission-mode bypassPermissions`. Interactions on this
  repository are limited to collaborators so outsiders cannot plant issue or
  comment text for those runs to read.
