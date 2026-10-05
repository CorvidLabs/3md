---
change: limit-github-token-to-contents-read-in-the-ui-trust-and-cargo-publish-workflows
artifact: design
---

# Design

Each flagged workflow gets one workflow-level block:

```yaml
permissions:
  contents: read
```

Workflow scope is enough because each file has a single job and no job needs a broader token. A later job that posts comments, writes packages, or publishes Pages must add its own job-level block rather than widening this default.

`contents: read` allows checkout and public release downloads. It does not allow the job token to push, open pull requests, or write checks. Publish secrets stay separate from `GITHUB_TOKEN`.

The workflow-v2 baseline is a cutoff marker. It does not change canonical specs. Changes created after the cutoff use `change review` and `change finalize`. Changes already accepted under workflow v1 stay on that evidence.
