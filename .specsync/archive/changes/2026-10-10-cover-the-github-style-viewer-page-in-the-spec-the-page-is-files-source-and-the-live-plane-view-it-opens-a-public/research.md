---
change: cover-the-github-style-viewer-page-in-the-spec-the-page-is-files-source-and-the-live-plane-view-it-opens-a-public
artifact: research
---

# Research

## Module boundary

`ThreeMDElement` owns `element/src/three-md.ts` and states that the element is text-only. Putting GitHub fetch, decode, and search into that spec would blur the boundary Leif already set. `ThreeMD` owns the parsers and `web/assets/three-md.js`. The page is a separate surface, so it gets `ThreeMDViewer`, the same way the CLI has `ThreeMDCLI` and Sculpt has its own spec.

## Host check

CodeQL rule `js/incomplete-url-substring-sanitization` flagged `address.includes("raw.githubusercontent.com")` in `web/github-source.test.ts`. A host name can sit anywhere in a URL string. The production parser already compared `URL.hostname`. The test now does the same. The alert instance on the old commit is fixed. The page still talks only to the public GitHub API and raw host. A private repo comes back as missing. A 403 or 429 is the rate limit.

## What stays put

The format is unchanged: text grammar 1.0, binary envelope 1, payload kinds 1 and 2. Kind 2 download uses the existing uncompressed encoder. LZFSE stays Swift and Apple only, and the page refuses it. No version bump and no tag move.
