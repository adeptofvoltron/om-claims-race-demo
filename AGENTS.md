# Agent instructions

This is a public, synthetic test bed for the race-safe claim protocol from
open-mercato/skills PR #176. The only product code is `src/slugify.js`. Issues
are synthetic, but handle them exactly like real ones: the point is to watch
the normal pipeline run.

## Task routing

| When the task involves… | Read first | Key rules |
|---|---|---|
| `src/` or `test/` | `SDLC.md`, `CODE_REVIEW.md` | Keep changes minimal; every behavior change gets a `node:test` case. |
| `demo/` scripts | `README.md` | These drive the experiment. Agent runs never edit them. |
| `.ai/` pipeline config | `SDLC.md` | `.ai/trackers/github.md` is pinned to the skills commit under test; do not edit it. |

## Validation

```bash
npm test
```
