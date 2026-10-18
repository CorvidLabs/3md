---
change: retire-the-superseded-threemd-2-1-documentation-workspace-as-an-unchanged-historical-snapshot
artifact: testing
---

# Testing

Require SHA-256 equality for every moved file and identical original state/approval bytes. Compare all tracked source and canonical spec bytes before/after. Assert exactly the selected workspace leaves the active roster and all other packages remain. Run canonical strict check, scoped strict verification and active strict audit. The policy failure must remain visible; retirement is not an audit exemption. Negative controls reject missing, altered or extra snapshot files and any claimed archived/accepted state conversion. No human review or acceptance is supplied by these tests.
