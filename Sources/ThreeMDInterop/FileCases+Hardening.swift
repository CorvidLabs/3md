import Foundation
import ThreeMD

/// Shared cases for caller limits, refusal order, path grammar, ledger escapes, cycles and discovery ceilings.
@available(macOS 10.15, *)
extension FileInterchangeCases {
    internal static func hardeningCases(leaf: Document, leafBytes: Data) throws -> [FileInterchangeCase] {
        var result: [FileInterchangeCase] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        func add(
            _ id: String,
            root: String = "root.3md",
            sources: [(String, Data)],
            limits: JSONValue? = nil,
            documentLimits: JSONValue? = nil,
            error: String? = nil
        ) throws {
            let input = Input(
                rootPath: root,
                files: sources.map { Source(path: $0.0, bytesHex: $0.1.hex) },
                limits: limits,
                documentLimits: documentLimits
            )
            result.append(.init(id: "files-" + id, bytes: try encoder.encode(input), expectedError: error))
        }
        func addRaw(_ id: String, json: String, error: String? = nil) {
            result.append(.init(id: "files-" + id, bytes: Data(json.utf8), expectedError: error))
        }
        func values(_ fields: [String: Double]) -> JSONValue { .object(fields.mapValues(JSONValue.number)) }
        func text(_ title: String, body: String = "1", ledger: String? = nil) throws -> Data {
            try DocumentStorageCodec.encode(
                document(title, body: body, metadata: ledger.map { ["3md-files": $0] } ?? [:]),
                format: .text
            )
        }
        func ledgerJSON(_ fields: [String: String]) throws -> String {
            String(decoding: try encoder.encode(fields), as: UTF8.self)
        }
        func bundle(_ graph: DocumentComposition) throws -> Data { try DocumentCompositionCodec.encode(graph) }

        let other = try text("Other", body: "Stone")
        let twoLeaves = try text("Parent", body: "12", ledger: #"{"1":"leaf.3md","2":"leaf.3md"}"#)
        let oneLeaf = try text("Parent", body: "1", ledger: #"{"1":"leaf.3md"}"#)
        let nested = try DocumentComposition(
            rootID: "nested",
            entries: [
                .init(
                    id: "nested",
                    document: document("Nested", body: "1"),
                    references: [.init(targetID: "child", attributes: ["glyph": "1"])]
                ),
                .init(id: "child", document: leaf),
                .init(id: "unused", document: document("Unused", body: "Retained")),
            ]
        )
        let disconnected = try DocumentComposition(
            rootID: "r",
            entries: [
                .init(id: "r", document: leaf),
                .init(id: "u", document: document("Unused", body: "1", metadata: ["3md-files": #"{"1":"x.3md"}"#])),
            ]
        )
        let cachedDepth: [(String, Data)] = [
            ("root.3md", try text("Root", body: "12", ledger: #"{"1":"short.3md","2":"long.3md"}"#)),
            ("short.3md", try text("Short", ledger: #"{"1":"leaf.3md"}"#)),
            ("long.3md", try text("Long", body: "12", ledger: #"{"1":"short.3md","2":"short.3md"}"#)),
            ("leaf.3md", leafBytes),
        ]

        // Lowered caller limits. Original supplied path bytes are charged before any path is validated.
        try add(
            "limits-path-bytes-over-profile",
            sources: [("root.3md", leafBytes)],
            limits: values(["maximumProfileBytes": 15]),
            error: "fileLimit"
        )
        try add(
            "limits-path-bytes-precede-invalid-path",
            root: "/root.3md",
            sources: [("/root.3md", leafBytes)],
            limits: values(["maximumProfileBytes": 17]),
            error: "fileLimit"
        )
        try add(
            "limits-invalid-path-within-path-bytes",
            root: "/root.3md",
            sources: [("/root.3md", leafBytes)],
            limits: values(["maximumProfileBytes": 18]),
            error: "filePath"
        )
        try add(
            "limits-encoded-bytes-over-profile",
            sources: [("root.3md", oneLeaf), ("leaf.3md", leafBytes)],
            limits: values(["maximumProfileBytes": Double(oneLeaf.count + leafBytes.count - 1)]),
            error: "fileLimit"
        )
        try add(
            "limits-source-count-over-definitions",
            sources: [("root.3md", leafBytes), ("a.3md", leafBytes), ("b.3md", leafBytes)],
            limits: values(["maximumDefinitions": 2]),
            error: "fileLimit"
        )
        try add(
            "limits-depth-2-disconnected-ledger",
            sources: [
                ("root.3md", try text("Parent", body: "12", ledger: #"{"1":"bundle.3md","2":"bundle.3md"}"#)),
                ("bundle.3md", try bundle(disconnected)), ("x.3md", leafBytes),
            ],
            limits: values(["maximumDepth": 2])
        )
        try add(
            "limits-depth-3-cached-path",
            sources: cachedDepth,
            limits: values(["maximumDepth": 3]),
            error: "depthExceeded"
        )
        try add(
            "limits-depth-4-cached-path",
            sources: cachedDepth,
            limits: values(["maximumDepth": 4])
        )
        try add(
            "limits-missing-file-precedes-final-depth",
            sources: [
                cachedDepth[0], cachedDepth[1],
                ("long.3md", try text("Long", body: "12", ledger: #"{"1":"short.3md","2":"missing.3md"}"#)),
                cachedDepth[3],
            ],
            limits: values(["maximumDepth": 3]),
            error: "missingFile"
        )
        try add(
            "limits-references-1",
            sources: [("root.3md", twoLeaves), ("leaf.3md", leafBytes)],
            limits: values(["maximumReferences": 1]),
            error: "tooManyReferences"
        )
        try add(
            "limits-reference-attributes-1",
            sources: [("root.3md", oneLeaf), ("leaf.3md", leafBytes)],
            limits: values(["maximumReferenceAttributes": 1]),
            error: "referenceAttributesExceeded"
        )
        try add(
            "limits-traversal-occurrences-2",
            sources: [("root.3md", twoLeaves), ("leaf.3md", leafBytes)],
            limits: values(["maximumTraversalOccurrences": 2]),
            error: "traversalOccurrencesExceeded"
        )
        try add(
            "limits-definitions-2-nested-bundle",
            sources: [
                ("root.3md", try text("Parent", ledger: #"{"1":"nested.3md"}"#)), ("nested.3md", try bundle(nested)),
            ],
            limits: values(["maximumDefinitions": 2]),
            error: "tooManyDefinitions"
        )
        try add(
            "limits-profile-bytes-exceeded",
            sources: [("root.3md", leafBytes)],
            limits: values(["maximumProfileBytes": Double(leafBytes.count + 10)]),
            error: "profileBytesExceeded"
        )
        try add(
            "document-limits-lowered-success",
            sources: [("root.3md", oneLeaf), ("leaf.3md", leafBytes)],
            documentLimits: values(["maximumRecordBytes": 512, "maximumPlanes": 1])
        )
        try add(
            "document-limits-planes",
            sources: [
                (
                    "root.3md",
                    try DocumentStorageCodec.encode(
                        Document(
                            version: "1.1",
                            axis: .space,
                            planes: [Plane(z: 0, body: "A"), Plane(z: 1, body: "B")]
                        )
                    )
                )
            ],
            documentLimits: values(["maximumPlanes": 1]),
            error: "tooManyPlanes"
        )
        try add(
            "limits-empty-objects",
            sources: [("root.3md", oneLeaf), ("leaf.3md", leafBytes)],
            limits: .object([:]),
            documentLimits: .object([:])
        )

        // Limit objects: names and integral JSON numbers are protocol shape; ranges are library policy.
        let leafHex = leafBytes.hex
        addRaw(
            "limits-integral-number-forms",
            json: #"{"files":[{"bytesHex":"\#(leafHex)","path":"root.3md"}],"limits":{"#
                + #""maximumDefinitions":1.0,"maximumDepth":6.4e1,"maximumReferences":-0},"rootPath":"root.3md"}"#
        )
        for (name, limits, documentLimits, error) in [
            ("limits-invalid-zero-depth", values(["maximumDepth": 0]), nil, "invalidLimits"),
            ("limits-invalid-negative", values(["maximumReferences": -1]), nil, "invalidLimits"),
            ("limits-invalid-above-ceiling", values(["maximumDefinitions": 1_025]), nil, "invalidLimits"),
            (
                "limits-invalid-largest-safe-integer", values(["maximumDepth": 9_007_199_254_740_991]), nil,
                "invalidLimits"
            ),
            ("document-limits-invalid-zero-planes", nil, values(["maximumPlanes": 0]), "invalidLimits"),
            (
                "document-limits-invalid-above-ceiling", nil, values(["maximumEncodedBytes": 67_108_865]),
                "invalidLimits"
            ),
            ("limits-unknown-name", values(["maximumDepth": 2, "maximumPlanes": 1]), nil, "adapterFailure"),
            ("document-limits-unknown-name", nil, values(["maximumDepth": 2]), "adapterFailure"),
            ("limits-fractional", values(["maximumDepth": 1.5]), nil, "adapterFailure"),
            ("limits-unsafe-integer", values(["maximumDepth": 9_007_199_254_740_992]), nil, "adapterFailure"),
            ("limits-string-value", .object(["maximumDepth": .string("2")]), nil, "adapterFailure"),
            ("limits-boolean-value", .object(["maximumDepth": .bool(true)]), nil, "adapterFailure"),
            ("document-limits-null-value", nil, .object(["maximumPlanes": .null]), "adapterFailure"),
            ("limits-null-object", JSONValue.null, nil, "adapterFailure"),
            ("limits-array-object", .array([.number(2)]), nil, "adapterFailure"),
            ("document-limits-string-object", nil, .string("standard"), "adapterFailure"),
        ] as [(String, JSONValue?, JSONValue?, String)] {
            try add(
                name,
                sources: [("root.3md", leafBytes)],
                limits: limits,
                documentLimits: documentLimits,
                error: error
            )
        }
        // Shape precedes the standard count ceiling; values follow it and per-file hex, then precede paths.
        let manySources = JSONValue.array(
            (0..<1_025).map { .object(["path": .string("file-\($0)"), "bytesHex": .string("")]) }
        )
        for (name, limits, error) in [
            ("limits-shape-precedes-count", JSONValue.object(["unknown": .number(1)]), "adapterFailure"),
            ("limits-value-follows-count", values(["maximumDepth": 0]), "fileLimit"),
        ] {
            let input = JSONValue.object(["rootPath": .string("root"), "files": manySources, "limits": limits])
            result.append(.init(id: "files-" + name, bytes: try encoder.encode(input), expectedError: error))
        }
        addRaw(
            "limits-value-follows-invalid-hex",
            json: #"{"files":[{"bytesHex":"zz","path":"root.3md"}],"limits":{"maximumDepth":0},"rootPath":"root.3md"}"#,
            error: "adapterFailure"
        )
        try add(
            "limits-value-precedes-path-grammar",
            root: "/root.3md",
            sources: [("/root.3md", leafBytes)],
            limits: values(["maximumDepth": 0]),
            error: "invalidLimits"
        )
        try add(
            "limits-value-precedes-library-count",
            sources: [("root.3md", leafBytes), ("a.3md", leafBytes), ("b.3md", leafBytes)],
            limits: values(["maximumDefinitions": 2]),
            documentLimits: values(["maximumLines": 0]),
            error: "invalidLimits"
        )

        // A cached subtree is charged at its later, deeper occurrence against the fixed discovery ceiling.
        func chain(_ prefix: String, count: Int, last: String?) throws -> [(String, Data)] {
            try (1...count).map { index in
                let next = index < count ? "\(prefix)\(index + 1)" : last
                let graph = try DocumentComposition(
                    rootID: "r",
                    entries: [
                        .init(id: "r", document: leaf),
                        .init(
                            id: "u",
                            document: document(
                                "Unused",
                                body: "1",
                                metadata: next.map { ["3md-files": "{\"1\":\"\($0)\"}"] } ?? [:]
                            )
                        ),
                    ]
                )
                return ("\(prefix)\(index)", try bundle(graph))
            }
        }
        let ceilingRoot = ("root.3md", try text("Root", body: "12", ledger: #"{"1":"a1","2":"b1"}"#))
        let longChain = try chain("a", count: 40, last: nil)
        try add(
            "cached-subtree-exceeds-discovery-ceiling",
            sources: [ceilingRoot] + longChain + chain("b", count: 30, last: "a1"),
            error: "depthExceeded"
        )
        try add(
            "cached-subtree-reaches-discovery-ceiling",
            sources: [ceilingRoot] + longChain + chain("b", count: 23, last: "a1")
        )

        // Root and supplied-but-unreachable paths obey the same grammar as ledger targets.
        for (name, path) in [
            ("absolute", "/root.3md"), ("dot", "."), ("escape", "../root.3md"), ("empty", ""),
            ("backslash", "a\\b.3md"), ("colon", "a:b.3md"), ("delete", "a\u{7F}b.3md"), ("nul", "a\u{0}b.3md"),
        ] {
            try add("invalid-root-path-" + name, root: path, sources: [("root.3md", leafBytes)], error: "filePath")
            try add(
                "invalid-unreachable-path-" + name,
                sources: [("root.3md", leafBytes), (path, leafBytes)],
                error: "filePath"
            )
        }
        try add(
            "percent-literal-path",
            sources: [
                ("root.3md", try text("Parent", ledger: #"{"1":"%2e%2e/leaf.3md"}"#)), ("%2e%2e/leaf.3md", leafBytes),
            ]
        )
        try add(
            "case-distinct-paths",
            sources: [
                ("root.3md", try text("Parent", body: "12", ledger: #"{"1":"Leaf.3md","2":"leaf.3md"}"#)),
                ("Leaf.3md", other), ("leaf.3md", leafBytes),
            ]
        )

        // JSON escapes decode before path grammar applies.
        try add(
            "ledger-escaped-control",
            sources: [("root.3md", try text("Parent", ledger: #"{"1":"a\u0001b.3md"}"#)), ("a.3md", leafBytes)],
            error: "filePath"
        )
        try add(
            "ledger-escaped-slash-same-file",
            sources: [
                (
                    "root.3md",
                    try text("Parent", body: "12", ledger: #"{"1":"models\/leaf.3md","2":"models/leaf.3md"}"#)
                ),
                ("models/leaf.3md", leafBytes),
            ]
        )
        try add(
            "ledger-escaped-backslash",
            sources: [
                ("root.3md", try text("Parent", ledger: #"{"1":"models\\leaf.3md"}"#)), ("models/leaf.3md", leafBytes),
            ],
            error: "filePath"
        )
        try add(
            "ledger-escaped-surrogate-pair",
            sources: [("root.3md", try text("Parent", ledger: #"{"1":"😀.3md"}"#)), ("😀.3md", leafBytes)]
        )
        try add(
            "ledger-lone-surrogate-key",
            sources: [("root.3md", try text("Parent", ledger: #"{"\ud800":"leaf.3md"}"#)), ("leaf.3md", leafBytes)],
            error: "fileLedger"
        )

        // Refusals follow discovery order: entry ID, then glyph, each target resolved and visited in turn.
        try add(
            "order-missing-before-invalid-path",
            sources: [("root.3md", try text("Parent", body: "ab", ledger: #"{"a":"missing.3md","b":"/x.3md"}"#))],
            error: "missingFile"
        )
        try add(
            "order-invalid-path-before-missing",
            sources: [("root.3md", try text("Parent", body: "ab", ledger: #"{"a":"/x.3md","b":"missing.3md"}"#))],
            error: "filePath"
        )
        for (name, first, second, error) in [
            ("order-entry-id-before-glyph-missing", "missing.3md", "/x.3md", "missingFile"),
            ("order-entry-id-before-glyph-path", "/x.3md", "missing.3md", "filePath"),
        ] {
            let graph = try DocumentComposition(
                rootID: "m",
                entries: [
                    .init(id: "m", document: leaf),
                    .init(
                        id: "a",
                        document: document("A", body: "z", metadata: ["3md-files": try ledgerJSON(["z": first])])
                    ),
                    .init(
                        id: "b",
                        document: document("B", body: "a", metadata: ["3md-files": try ledgerJSON(["a": second])])
                    ),
                ]
            )
            try add(name, sources: [("root.3md", try bundle(graph))], error: error)
        }

        // Existing graph edges stay first; ledger edges follow, and embedded ledgers resolve from their bundle file.
        let edgesThenLedger = try DocumentComposition(
            rootID: "m",
            entries: [
                .init(
                    id: "m",
                    document: document("Main", body: "12", metadata: ["3md-files": #"{"2":"leaf.3md"}"#]),
                    references: [.init(targetID: "c", attributes: ["glyph": "1", "opaque": "keep"])]
                ),
                .init(id: "c", document: document("Kept", body: "Existing")),
            ]
        )
        try add(
            "existing-edges-then-ledger-edges",
            sources: [("root.3md", try bundle(edgesThenLedger)), ("leaf.3md", leafBytes)]
        )
        let embeddedLedger = try DocumentComposition(
            rootID: "m",
            entries: [
                .init(id: "m", document: document("Group", body: "2", metadata: ["3md-files": #"{"2":"leaf.3md"}"#]))
            ]
        )
        try add(
            "embedded-ledger-relative-to-bundle-folder",
            sources: [
                ("root.3md", try text("Parent", ledger: #"{"1":"models/group.3md"}"#)),
                ("models/group.3md", try bundle(embeddedLedger)), ("models/leaf.3md", leafBytes),
            ]
        )
        // Resolver output is an ordinary bundle; its glyph and source-file attributes are opaque when rebundled.
        let first = try DocumentFileComposition.resolve(
            rootPath: "root.3md",
            sources: [
                .init(
                    path: "root.3md",
                    data: try text("Parent", body: "12", ledger: #"{"1":"models/leaf.3md","2":"models/leaf.3md"}"#)
                ),
                .init(path: "models/leaf.3md", data: leafBytes),
            ]
        )
        try add(
            "rebundle-resolver-output",
            sources: [
                ("root.3md", try text("Parent", ledger: #"{"1":"archive/bundle.3md"}"#)),
                ("archive/bundle.3md", try bundle(first.composition)),
            ]
        )

        // Self and alias cycles compare normalized paths.
        try add("self-cycle", sources: [("root.3md", try text("Parent", ledger: #"{"1":"root.3md"}"#))], error: "cycle")
        try add(
            "self-cycle-dot-alias",
            sources: [("root.3md", try text("Parent", ledger: #"{"1":"./root.3md"}"#))],
            error: "cycle"
        )
        try add(
            "alias-cycle-parent-segment",
            sources: [
                ("root.3md", try text("Parent", ledger: #"{"1":"models/child.3md"}"#)),
                ("models/child.3md", try text("Child", ledger: #"{"1":"../root.3md"}"#)),
            ],
            error: "cycle"
        )
        try add(
            "alias-cycle-folder-parent-segment",
            sources: [
                ("root.3md", try text("Parent", ledger: #"{"1":"child.3md"}"#)),
                ("child.3md", try text("Child", ledger: #"{"1":"models/../root.3md"}"#)),
            ],
            error: "cycle"
        )

        // glyph (5) + "1" (1) + source-file (11) + NFC path bytes must fit the reference attribute byte bound.
        // Decomposed spellings are supplied; the bound counts the normalized two-byte é. A success exactly at
        // the standard 16,384-byte bound cannot pass this gate's identity adoption, which adds a 3md-id
        // attribute, so the exact bound is pinned under a lowered 1,000-byte policy (983 and 984 path bytes).
        for (name, repeated, padding, bound, error) in [
            ("at-lowered-bound", 400, 172, 1_000, nil),
            ("over-lowered-bound", 400, 173, 1_000, "referenceAttributesExceeded"),
            ("over-standard-bound", 8_000, 357, nil, "referenceAttributesExceeded"),
        ] as [(String, Int, Int, Double?, String?)] {
            let path =
                "models/" + String(repeating: "e\u{301}", count: repeated) + String(repeating: "a", count: padding)
                + ".3md"
            try add(
                "source-file-attribute-" + name,
                sources: [("root.3md", try text("Parent", ledger: try ledgerJSON(["1": path]))), (path, leafBytes)],
                limits: bound.map { values(["maximumReferenceAttributeBytes": $0]) },
                error: error
            )
        }

        // A long owner path with many ledger references. Each owner is normalized once per discovered file, so
        // references do not repeat work proportional to the 1 MiB owner name; the output stays small.
        let glyphs = (33...126).map { String(UnicodeScalar(UInt8($0))) }
        let ownerLedger = try ledgerJSON(Dictionary(uniqueKeysWithValues: glyphs.map { ($0, "leaf.3md") }))
        let ownerEntries = (0..<3).map { index in
            DocumentEntry(
                id: "e\(index)",
                document: document("Entry \(index)", body: "!", metadata: ["3md-files": ownerLedger]),
                references: [.init(targetID: "s", attributes: ["role": "shared"])]
            )
        }
        let ownerGraph = try DocumentComposition(
            rootID: "m",
            entries: ownerEntries + [
                .init(
                    id: "m",
                    document: document("Main", body: "Owner"),
                    references: ownerEntries.map { .init(targetID: $0.id, attributes: [:]) }
                ),
                .init(id: "s", document: document("Shared", body: "Shared")),
            ]
        )
        let ownerPath = "owner/" + String(repeating: "\u{E9}", count: 524_288) + ".3md"
        try add(
            "long-owner-path-many-references",
            root: ownerPath,
            sources: [(ownerPath, try bundle(ownerGraph)), ("owner/leaf.3md", leafBytes)]
        )
        return result
    }
}
