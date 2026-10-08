# Landed main verification

`main` at `ce0f872`, the PR39 squash, has the same tree as `ee51e54`, the resolved PR39 head. The complete pinned seven-step lane ran on `ee51e54` in a clean detached worktree on 2026-10-06, recorded in [verify-ee51e54.log](verify-ee51e54.log):

- Format check.
- 31 harness tests.
- 513 tests in 41 suites.
- hi 0.8.0 with 46 criteria and 53 retired.
- Strict SpecSync 6.0.0 with 5 specs, zero warnings, 77/77 files and 20,652/20,652 lines.
- Source boundaries and the release fixture.

Fledge reported 11 minutes 26 seconds; other lanes were running on the same machine. GitHub CI also passed on `main` at `ce0f872` (run 37546721569). The next main commit, `3f54a1b` (PR41), changed only `AGENTS.md`, `INTENT.md`, `README.md` and `docs/architecture.md`.

These are finite automated tests. They are not a human review, a GitHub approval or a signature.
