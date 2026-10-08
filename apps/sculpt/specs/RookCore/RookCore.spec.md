---
module: RookCore
version: 2
status: active
files:
  - Sources/RookCore/AppAppearance.swift
db_tables: []
depends_on: []
---

# RookCore

## Purpose

Appearance values for the base Mac app. The only stored choice is `rook.appearance`. Unknown or missing stored text means system. Intent: SHELL-5, LOCAL-1.

## Public API

### Exported Symbols

| Symbol | Role |
| --- | --- |
| `AppAppearance` | System, light, or dark. |
| `system` | Follow the Mac appearance. |
| `light` | Light appearance. |
| `dark` | Dark appearance. |
| `title` | Short label for the choice. |
| `init` | `init(storedValue:)` defaults unknown or missing text to system. |

## Invariants

1. `AppAppearance` is `Sendable`. Its raw values are `system`, `light`, and `dark`.
2. `init(storedValue:)` returns `.system` for nil, empty, and any other string.
3. This module does not import AppKit, RookApp, RookSculpture, or RookRendering. It does not store a sculpture, notes, or the camera, and it does not open a network connection.

## Behavioral Examples

- A missing stored value and the string `nope` both become `.system`.
- `.light.title` is a non-empty label a settings control can show.

## Error Cases

There is no throwing API. Unrecognized stored text is system, not a crash and not a guessed custom theme.

## Dependencies

Swift standard library only. No package dependencies.

## Change Log

- Version 1: appearance choice for the one-window app. No review or finalization is claimed.
- Version 2: appearance stays the whole module after the sculpture slice. No review or finalization is claimed.
