# Workflow permissions archive correction

This additive note corrects the evidence-retention and delivery-history gaps in the records landed by PR59. It preserves the original archived records, including their timestamps, actors and cryptographic preimages. It does not claim that the original definition preceded the permission implementation or its first merge.

## Retained implementation evidence

The original implementation commit is now retained at `refs/heads/leif/evidence-workflow-permissions-777427d`:

- Commit: `777427d6c89dd55eead16a3d46e4e97894ef2a6f`
- Tree: `8858ce95114438865fbb981fcfb83c283f6302e9`
- Archive: [workflow permissions change](../../../.specsync/archive/changes/2026-10-05-limit-github-token-to-contents-read-in-the-ui-trust-and-cargo-publish-workflows/)
- [Original finalization record](../../../.specsync/archive/changes/2026-10-05-limit-github-token-to-contents-read-in-the-ui-trust-and-cargo-publish-workflows/finalization.json)
- [Original scoped review](../../../.specsync/archive/changes/2026-10-05-limit-github-token-to-contents-read-in-the-ui-trust-and-cargo-publish-workflows/review.json)

Before this repair, GitHub's commit API returned HTTP422 for the implementation pin. After publishing the retained ref, the same API resolves the exact commit and tree above. A fresh bare repository fetched only that named ref and independently resolved the same values. The original object was published without rebasing, amending or synthesizing a replacement commit.

Keep this evidence ref while the archive relies on it. It is a historical snapshot, not a feature branch to merge, a release tag, or the current product tree. Its existing generated Atlas blobs are part of that original snapshot; no new Atlas output was generated or staged by this repair.

To reproduce in a normal clone:

```text
git fetch origin refs/heads/leif/evidence-workflow-permissions-777427d:refs/remotes/origin/leif/evidence-workflow-permissions-777427d
git rev-parse refs/remotes/origin/leif/evidence-workflow-permissions-777427d
git rev-parse 777427d6c89dd55eead16a3d46e4e97894ef2a6f^{tree}
git show 777427d6c89dd55eead16a3d46e4e97894ef2a6f
```

## Actual delivery chronology

All timestamps below are UTC on 2026-10-05, which was the evening of October 4 in America/Denver.

| Event | Time | Evidence |
| --- | --- | --- |
| PR57 merged the workflow permissions | 01:01:12 | [PR57](https://github.com/CorvidLabs/3md/pull/57) |
| Later workflow-v2 definition created | 01:06:34 | Original archived state `created_at: 1791162394` |
| Definition approved | 01:07:03 | Original approvals `timestamp: 1791162423` |
| Scoped agent review recorded | 01:08:33 | Original review `timestamp: 1791162513` |
| Finalization recorded | 01:09:07 | Original finalization `timestamp: 1791162547` |
| PR59 merged the archive cleanup | 02:05:40 | [PR59](https://github.com/CorvidLabs/3md/pull/59) |

The old archived `testing.md` instruction to finalize on PR57 before merge was an unmet intended order. PR59 delivered retrospective lifecycle cleanup after PR57 had already merged. The original instruction remains historical; this note supplies the actual outcome. This sequence is not evidence of definition-first SDD for PR57.

The squash mappings are exact at the Git tree level:

| Published source | Landed squash | Shared tree |
| --- | --- | --- |
| `fb70a0c9c9ab41c93c882514b8af2ca760626fb2` | `a3486bd8bd614fa792f23a96f7b3449e6f99c9ae` | `a4d02e72b7e46648a010f05102f726b57212ab14` |
| `1d2fc3d7ca2079e8415524e8ce70d73bc747ec8b` | `8b09724fc390236f52c873761247166048aef67e` | `246d6b6590acef0fbd4f5256da72f1b8e0e77ad6` |

The retained implementation has lifecycle and generated-file differences from the landed tree. Its workflow and product files match the landed tree. Preserving it makes the original full review tree inspectable instead of substituting a later squash SHA into the old hashes.

## Scope and provenance

The change uses workflow-origin version 2, `no_spec_change: true`, and baseline cutoff `8712c686b91a54a972b1ffcb7512055513990d73`. The retained `.specsync/version` value `5.0.1` is adoption metadata; the writer and CI binary were SpecSync 6.0.0. No canonical spec was changed by PR57 or PR59.

The archived review is a `pass` claim from `agent:grok`. PR59 has no GitHub reviews recorded. A SpecSync review record is not a GitHub approval or authenticated independent human review.

PR59's native lane completed all seven steps. Its Trust provenance report found six commits without attestations or valid signatures and reported `soft-failed`. The existing `.trust.toml` soft policy allowed the degraded result. The signed requirements and reviewer/key restrictions in `.attest.json` remain unmet for those commits and unchanged. A passing Trust job is not a signed-provenance claim.

CHG-0001 and CHG-0003 were reopened because their exact `trust.yml` delivery input changed. All 37 archived delivery payload entries matched the landed `8b09724` tree; prior approvals, reopenings and verification attempts remain preserved. Reacceptance labels are recorded actor claims, not authentication evidence. CHG-0002's verification is unchanged.

The repair branch adds this note and its own lifecycle record. Original archive files, workflows, parser, format, conformance, canonical specs, and generated product bundles remain identical to `8b09724`. The existing checkout's untracked Atlas files and PR58 remain outside this repair.
