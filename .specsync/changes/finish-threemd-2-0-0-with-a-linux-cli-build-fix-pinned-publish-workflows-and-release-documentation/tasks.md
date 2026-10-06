---
change: finish-threemd-2-0-0-with-a-linux-cli-build-fix-pinned-publish-workflows-and-release-documentation
artifact: tasks
---

# Tasks

- [ ] Record definition approval (agent:claude acting on Leif's scope approval).
- [ ] Route CLI standard-error writes through FileHandle.standardError.
- [ ] Pin the npm upgrade in publish.yml to npm@^11.5.1.
- [ ] Replace the cargo-publish version rewrite with a tag/version check, CARGO_REGISTRY_TOKEN and non-tag refusal.
- [ ] Run Linux aarch64 container suites and interchange; retain logs.
- [ ] Update release documentation and regenerate docs.3md and web/docs.3md.
- [ ] Strict SpecSync and pinned Trust 1.2.2 on the exact tip.
- [ ] Scoped review and finalization on the delivery PR.
