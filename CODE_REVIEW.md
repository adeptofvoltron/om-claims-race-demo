# Code review

- Behavior changes in `src/` come with a `node:test` case in `test/`.
- `npm test` passes.
- No new runtime dependencies: the project runs on plain Node.js.
- Public API of `slugify(title)` stays backward compatible (see `BACKWARD_COMPATIBILITY.md`).
