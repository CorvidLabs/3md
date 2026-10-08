#!/usr/bin/env python3
"""Generate the Unicode 17.0 NFC tables used by the Godot addon.

Node and Bun normalize with Unicode 17. The tables are embedded in the addon so
the library does not read the filesystem. Run this when the Unicode pin changes.
"""

from __future__ import annotations

import base64
import json
import pathlib
import struct
import subprocess
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
DATA_GD = ROOT / "addons" / "threemd" / "nfc_data.gd"
VECTORS = ROOT / "tests" / "nfc_vectors.bin"
CACHE = pathlib.Path("/tmp/ucd-17.0.0")
UNICODE_VERSION = "17.0.0"
MAGIC = 0x3143464E


def fetch(name: str) -> str:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / name
    if not path.exists():
        url = f"https://www.unicode.org/Public/{UNICODE_VERSION}/ucd/{name}"
        urllib.request.urlretrieve(url, path)
    return path.read_text(encoding="utf-8")


def load_exclusions(text: str) -> set[int]:
    excluded: set[int] = set()
    for line in text.splitlines():
        body = line.split("#", 1)[0].strip()
        if not body:
            continue
        if ".." in body:
            start, end = body.split("..")
            for value in range(int(start, 16), int(end, 16) + 1):
                excluded.add(value)
        else:
            excluded.add(int(body, 16))
    return excluded


def load_unicode(text: str) -> tuple[dict[int, int], dict[int, tuple[int, ...]]]:
    combining: dict[int, int] = {}
    decompositions: dict[int, tuple[int, ...]] = {}
    for line in text.splitlines():
        fields = line.split(";")
        codepoint = int(fields[0], 16)
        combining_class = int(fields[3])
        if combining_class:
            combining[codepoint] = combining_class
        mapping = fields[5]
        if mapping and not mapping.startswith("<"):
            decompositions[codepoint] = tuple(int(part, 16) for part in mapping.split())
    return combining, decompositions


def build_composition(
    combining: dict[int, int],
    decompositions: dict[int, tuple[int, ...]],
    excluded: set[int],
) -> dict[tuple[int, int], int]:
    composed: dict[tuple[int, int], int] = {}
    for codepoint, parts in decompositions.items():
        if len(parts) != 2 or codepoint in excluded:
            continue
        if combining.get(parts[0], 0) != 0:
            continue
        pair = (parts[0], parts[1])
        previous = composed.get(pair)
        if previous is not None and previous != codepoint:
            raise SystemExit(f"composition collision {pair}: {previous:04X} {codepoint:04X}")
        composed[pair] = codepoint
    return composed


SBASE = 0xAC00
LBASE = 0x1100
VBASE = 0x1161
TBASE = 0x11A7
LCOUNT = 19
VCOUNT = 21
TCOUNT = 28
NCOUNT = VCOUNT * TCOUNT
SCOUNT = LCOUNT * NCOUNT


def hangul_parts(codepoint: int) -> list[int] | None:
    if not SBASE <= codepoint < SBASE + SCOUNT:
        return None
    index = codepoint - SBASE
    lead = LBASE + index // NCOUNT
    vowel = VBASE + (index % NCOUNT) // TCOUNT
    trail = TBASE + index % TCOUNT
    if trail == TBASE:
        return [lead, vowel]
    return [lead, vowel, trail]


def hangul_pair(left: int, right: int) -> int | None:
    if LBASE <= left < LBASE + LCOUNT and VBASE <= right < VBASE + VCOUNT:
        return SBASE + ((left - LBASE) * VCOUNT + (right - VBASE)) * TCOUNT
    if SBASE <= left < SBASE + SCOUNT and (left - SBASE) % TCOUNT == 0 and TBASE < right < TBASE + TCOUNT:
        return left + (right - TBASE)
    return None


def expand(
    codepoint: int,
    decompositions: dict[int, tuple[int, ...]],
    out: list[int],
) -> None:
    hangul = hangul_parts(codepoint)
    if hangul is not None:
        out.extend(hangul)
        return
    parts = decompositions.get(codepoint)
    if parts is None:
        out.append(codepoint)
        return
    for part in parts:
        expand(part, decompositions, out)


def reorder(chars: list[int], combining: dict[int, int]) -> None:
    changed = True
    while changed:
        changed = False
        for index in range(len(chars) - 1):
            right = combining.get(chars[index + 1], 0)
            if right > 0 and combining.get(chars[index], 0) > right:
                chars[index], chars[index + 1] = chars[index + 1], chars[index]
                changed = True


def nfc(
    sequence: list[int],
    combining: dict[int, int],
    decompositions: dict[int, tuple[int, ...]],
    composed: dict[tuple[int, int], int],
) -> list[int]:
    if sequence and all(codepoint < 128 for codepoint in sequence):
        return list(sequence)
    chars: list[int] = []
    for codepoint in sequence:
        expand(codepoint, decompositions, chars)
    reorder(chars, combining)
    if not chars:
        return []
    out = [chars[0]]
    starter = 0
    last = combining.get(chars[0], 0)
    if last != 0:
        last = 256
    for codepoint in chars[1:]:
        klass = combining.get(codepoint, 0)
        composite = None
        if last < klass or (last == 0 and klass == 0):
            composite = composed.get((out[starter], codepoint))
            if composite is None:
                composite = hangul_pair(out[starter], codepoint)
        if composite is not None:
            out[starter] = composite
        else:
            out.append(codepoint)
            if klass == 0:
                starter = len(out) - 1
                last = 0
            else:
                last = klass
    return out


def pack(
    combining: dict[int, int],
    decompositions: dict[int, tuple[int, ...]],
    composed: dict[tuple[int, int], int],
) -> bytes:
    blob = bytearray()
    blob += struct.pack("<I", MAGIC)
    blob += struct.pack("<I", len(combining))
    for codepoint, klass in sorted(combining.items()):
        blob += struct.pack("<II", codepoint, klass)
    blob += struct.pack("<I", len(decompositions))
    for codepoint, parts in sorted(decompositions.items()):
        blob += struct.pack("<II", codepoint, len(parts))
        blob += struct.pack("<" + "I" * len(parts), *parts)
    blob += struct.pack("<I", len(composed))
    for (left, right), value in sorted(composed.items()):
        blob += struct.pack("<III", left, right, value)
    return bytes(blob)


def node_changed(path: pathlib.Path) -> dict[int, list[int]]:
    script = r"""
const fs = require("fs");
const changed = [];
for (let cp = 0; cp <= 0x10FFFF; cp++) {
  if (cp >= 0xD800 && cp <= 0xDFFF) continue;
  const text = String.fromCodePoint(cp);
  const normal = text.normalize("NFC");
  if (normal !== text) changed.push([cp, [...normal].map((unit) => unit.codePointAt(0))]);
}
fs.writeFileSync(process.argv[2], JSON.stringify(changed));
"""
    runner = pathlib.Path("/tmp/nfc_oracle_singles.cjs")
    runner.write_text(script)
    subprocess.check_call(["node", str(runner), str(path)])
    rows = json.loads(path.read_text())
    return {int(codepoint): [int(part) for part in parts] for codepoint, parts in rows}


def node_sequences(sequences: list[list[int]]) -> list[list[int]]:
    source = pathlib.Path("/tmp/nfc_in.json")
    target = pathlib.Path("/tmp/nfc_out.json")
    source.write_text(json.dumps(sequences))
    script = r"""
const fs = require("fs");
const rows = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const out = rows.map((codes) => [...String.fromCodePoint(...codes).normalize("NFC")].map((unit) => unit.codePointAt(0)));
fs.writeFileSync(process.argv[3], JSON.stringify(out));
"""
    runner = pathlib.Path("/tmp/nfc_oracle_multi.cjs")
    runner.write_text(script)
    subprocess.check_call(["node", str(runner), str(source), str(target)])
    return json.loads(target.read_text())


def write_data(blob: bytes) -> None:
    encoded = base64.b64encode(blob).decode("ascii")
    DATA_GD.write_text(
        "class_name ThreeMDNFCData\n"
        "extends RefCounted\n\n"
        f"## Generated from Unicode {UNICODE_VERSION}. Do not edit.\n\n"
        f"const SIZE: int = {len(blob)}\n\n"
        f'const BLOB: String = "{encoded}"\n',
        encoding="utf-8",
    )


def write_vectors(rows: list[tuple[list[int], list[int]]]) -> None:
    blob = bytearray()
    blob += struct.pack("<I", len(rows))
    for source, normal in rows:
        blob += struct.pack("<I", len(source))
        if source:
            blob += struct.pack("<" + "I" * len(source), *source)
        blob += struct.pack("<I", len(normal))
        if normal:
            blob += struct.pack("<" + "I" * len(normal), *normal)
    VECTORS.write_bytes(blob)


def main() -> None:
    combining, decompositions = load_unicode(fetch("UnicodeData.txt"))
    excluded = load_exclusions(fetch("CompositionExclusions.txt"))
    # Singletons and non-starter decompositions are full composition exclusions.
    for codepoint, parts in decompositions.items():
        if len(parts) == 1 or combining.get(parts[0], 0) != 0:
            excluded.add(codepoint)
    composed = build_composition(combining, decompositions, excluded)
    print(f"ccc {len(combining)} decomp {len(decompositions)} pairs {len(composed)}")

    ours: dict[int, list[int]] = {}
    for codepoint in decompositions:
        normal = nfc([codepoint], combining, decompositions, composed)
        if normal != [codepoint]:
            ours[codepoint] = normal
    print(f"local singles {len(ours)}")
    oracle = node_changed(pathlib.Path("/tmp/nfc_node_singles.json"))
    print(f"node singles {len(oracle)}")
    if ours != oracle:
        mismatch = 0
        for codepoint in sorted(set(ours) | set(oracle)):
            if ours.get(codepoint) != oracle.get(codepoint):
                print(hex(codepoint), ours.get(codepoint), oracle.get(codepoint))
                mismatch += 1
                if mismatch >= 12:
                    break
        raise SystemExit(f"single-character NFC mismatches: {mismatch}")

    samples: list[list[int]] = [
        [0x0065, 0x0301],
        [0x212B],
        [0x1100, 0x1161],
        [0x1100, 0x1161, 0x11A8],
        hangul_parts(0xAC00) or [],
        hangul_parts(0xAC01) or [],
        [0x0041, 0x030A],
        [0x0061, 0x0306, 0x0301],
        [0x0061, 0x0323, 0x0302],
    ]
    for pair in composed:
        samples.append([pair[0], pair[1]])
    for index in range(SCOUNT):
        parts = hangul_parts(SBASE + index)
        if parts is not None:
            samples.append(parts)
    checked = node_sequences(samples)
    bad = 0
    for source, expected in zip(samples, checked):
        got = nfc(source, combining, decompositions, composed)
        if got != expected:
            print("MULTI", source, got, expected)
            bad += 1
            if bad >= 12:
                break
    if bad:
        raise SystemExit(f"multi-character NFC mismatches: {bad}")

    blob = pack(combining, decompositions, composed)
    write_data(blob)
    rows = [([codepoint], parts) for codepoint, parts in sorted(ours.items())]
    rows.extend((sample, nfc(sample, combining, decompositions, composed)) for sample in samples[:7])
    write_vectors(rows)
    print(f"wrote {DATA_GD} bytes {len(blob)} vectors {len(rows)}")


if __name__ == "__main__":
    main()
