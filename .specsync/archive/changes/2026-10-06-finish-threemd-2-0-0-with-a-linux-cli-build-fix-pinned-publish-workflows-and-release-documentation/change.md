---
id: finish-threemd-2-0-0-with-a-linux-cli-build-fix-pinned-publish-workflows-and-release-documentation
state: archived
type: operations
base_commit: 87edafb2f47b4d73e47441ae754ad955b6d49f44
---

# Finish ThreeMD 2.0.0 with a Linux CLI build fix, pinned publish workflows and release documentation

## Intent

Finish ThreeMD 2.0.0 with a Linux CLI build fix, pinned publish workflows and release documentation

## Affected Canonical Specs

- `ThreeMDCLI`
- `ThreeMD`
- `ThreeMDElement`

## Acceptance Criteria

- The full Swift package (including the threemd CLI) builds and its tests pass on Linux aarch64 in official Swift 6.0 and 6.3 containers at the release tip, with Rust, TypeScript and the nine-pair interchange also passing there and logs retained under docs/evidence/release-2.0.0/; CLI output is unchanged on macOS. publish.yml upgrades npm with npm@^11.5.1 instead of npm@latest, and cargo-publish.yml checks that the committed crate version equals the release tag instead of rewriting it, uses CARGO_REGISTRY_TOKEN, fails clearly when the secret is missing and refuses non-tag dispatch, with no permission changes. CHANGELOG, the release guide, README, SPEC and FILE-COMPOSITION status, EDITING-RELEASE, ROADMAP, package READMEs, the interchange README and the LinkedVillage README describe 2.0.0 as released on 2026-10-06, include linked file composition, cite the exact-tip verification and keep explicit limits (unverified Windows, emulated-only x86_64 Linux, soft unsigned provenance, Swift/Apple-only LZFSE, text-only element and VS Code, separate Sculpt adoption, follow-up parity hardening). AGENTS.md records the Finish 2.0.0 authority outside the managed block. Strict SpecSync and the pinned Trust 1.2.2 gate pass on the exact tip, and no human review or signature is claimed.

## No-spec Rationale

The CLI fix routes existing standard-error messages through FileHandle.standardError so Swift 6 builds on Linux; command behaviour and output are unchanged. The workflow edits pin the npm upgrade and replace a version rewrite with a tag/version check without changing permissions. The documentation states the 2.0.0 release, linked file composition and current verification evidence. ThreeMD, CLI and element contracts, public APIs, grammar, container and profile versions, fixtures, package versions and policies are unchanged.
