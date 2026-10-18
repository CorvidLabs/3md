---
change: add-gdscript-as-a-fourth-supported-threemd-language-a-godot-4-addon-that-parses-serializes-stores-composes-and-edits
artifact: plan
---

# Plan

1. Numeric core and NFC, because Godot's float parser is not correctly rounded and its strings are UTF-32.
2. Text parser and serializer, checked against `conformance/*.json`.
3. Kind 1 container, then kind 2 structured payload, checked against `conformance/structured/manifest.json`.
4. Composition, editing, and the file resolver, checked against the extension fixtures.
5. Game helper, planes-as-layers example, README, and the `fledge` task.
6. Interchange adapter. Protocol stays `3md-interchange-1`. Pair count goes from 9 to 16.
7. Trust verify. No publish, tag, or merge in this change.

The grammar, envelope, and profile stay as they are. Sculpt is out of scope. `element/dist` is not rebuilt.

## Approach

Implement the existing numeric/NFC, text, storage, composition/editing, helper and interchange stages in the numbered plan, preserving parity with the other three languages.

## Out of scope

The grammar, envelope and composition profile remain unchanged. Sculpt and element/dist rebuilds are outside this change; no publication, tag or merge is authorized by this plan.

## Steps

Follow the seven existing numbered steps above; retain the shared conformance checks and 16 writer/reader-pair target.

## Risks

Existing context records differences in Godot numeric conversion, NFC and integer division. LZFSE is explicitly unsupported; file access belongs only to the separate game helper.

## Constraints consulted

This format normalization uses this record's existing plan.md and context.md and the constraints answer sourced from those artifacts. It adds no human approval, completed-test claim or historical acceptance.
