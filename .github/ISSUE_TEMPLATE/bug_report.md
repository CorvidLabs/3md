---
name: Bug report
about: Something in a parser, the CLI, or the renderer behaves wrong
title: ""
labels: bug
---

**Which implementation**
Swift / TypeScript / Rust / CLI / VS Code extension (pick all that apply).

**A minimal .3md that reproduces it**

```
---
3md: 0.1
---
@plane z=0
...
```

**What happened**
The actual output or error.

**What you expected**
The output you expected, and the relevant SPEC.md section if you know it.

**Cross-implementation**
If you know whether the other parsers agree or disagree, say so. A divergence
between implementations is always a bug.
