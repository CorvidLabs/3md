import Foundation
import ThreeMD

/// Shared host-supplied file inputs, exercised by each public language adapter.
struct FileInterchangeCase {
    let id: String
    let bytes: Data
    let expectedError: String?
}

@available(macOS 10.15, *)
enum FileInterchangeCases {
    private struct Input: Encodable {
        let rootPath: String
        let files: [Source]
    }
    private struct Source: Encodable {
        let path: String
        let bytesHex: String
    }

    static func make() throws -> [FileInterchangeCase] {
        let leaf = document(
            "Child",
            body: "## Tree\nPreserve **Markdown**.",
            metadata: [
                "3md-id": "child", "owner": "human",
            ]
        )
        let leafBytes = try DocumentStorageCodec.encode(leaf, format: .text)
        let binaryLeaf = try DocumentStorageCodec.encode(leaf, format: .binary(compression: .none))
        var result: [FileInterchangeCase] = []

        func add(_ id: String, root: String = "root.3md", sources: [(String, Data)], error: String? = nil) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let bytes = try encoder.encode(
                Input(rootPath: root, files: sources.map { Source(path: $0.0, bytesHex: $0.1.hex) })
            )
            result.append(.init(id: "files-" + id, bytes: bytes, expectedError: error))
        }
        func parent(_ ledger: String) throws -> Data {
            try DocumentStorageCodec.encode(
                document("Parent", body: "112", metadata: ["3md-files": ledger]),
                format: .text
            )
        }

        try add("plain-no-ledger", sources: [("root.3md", leafBytes)])
        try add(
            "repeated-child",
            sources: [("root.3md", parent(#"{"1":"tree.3md","2":"./tree.3md"}"#)), ("tree.3md", leafBytes)]
        )
        try add("binary-child", sources: [("root.3md", parent(#"{"1":"child.bin"}"#)), ("child.bin", binaryLeaf)])
        try add(
            "nested-parent-relative",
            sources: [
                ("root.3md", parent(#"{"1":"models/group.3md"}"#)),
                ("models/group.3md", parent(#"{"2":"../tree.3md"}"#)), ("tree.3md", leafBytes),
            ]
        )
        try add(
            "distinct-basename",
            sources: [
                ("root.3md", parent(#"{"1":"a/tree.3md","2":"b/tree.3md"}"#)),
                ("a/tree.3md", leafBytes),
                ("b/tree.3md", DocumentStorageCodec.encode(document("Other", body: "Stone"), format: .text)),
            ]
        )
        try add(
            "unicode-nfc",
            sources: [
                ("root.3md", parent("{\"1\":\"café.3md\",\"2\":\"😀.3md\",\"3\":\"\\ue000.3md\"}")),
                ("cafe\u{0301}.3md", leafBytes), ("😀.3md", leafBytes), ("\u{E000}.3md", leafBytes),
            ]
        )
        try add(
            "combining-mark-path-separator",
            root: "a/\u{0301}owner.3md",
            sources: [
                ("a/\u{0301}owner.3md", parent(#"{"1":"child.3md"}"#)), ("a/child.3md", leafBytes),
            ]
        )
        try add(
            "absolute-combining-separator",
            sources: [
                ("root.3md", parent("{\"1\":\"/\u{0301}tree.3md\"}"))
            ],
            error: "filePath"
        )
        let nestedGraph = try DocumentComposition(
            rootID: "nested",
            entries: [
                .init(
                    id: "nested",
                    document: document("Nested", body: "1", metadata: ["3md-id": "nested-document"]),
                    references: [
                        .init(
                            targetID: "child",
                            attributes: ["glyph": "1", "3md-id": "existing-edge", "opaque": "keep"]
                        )
                    ]
                ),
                .init(id: "child", document: leaf),
                .init(id: "unused", document: document("Unused", body: "Retained")),
            ]
        )
        let nestedText = try DocumentCompositionCodec.encode(nestedGraph)
        let nestedBinary = try DocumentStorageCodec.encode(
            DocumentCompositionCodec.document(for: nestedGraph),
            format: .binary(compression: .none)
        )
        for (name, data) in [("text", nestedText), ("binary", nestedBinary)] {
            try add(
                "bundle-child-" + name,
                sources: [("root.3md", parent(#"{"1":"nested.3md"}"#)), ("nested.3md", data)]
            )
        }
        try add("unreachable-malformed-source", sources: [("root.3md", leafBytes), ("ignored", Data([0xff]))])
        try add("missing-child", sources: [("root.3md", parent(#"{"1":"missing.3md"}"#))], error: "missingFile")
        try add("missing-root", sources: [("other.3md", leafBytes)], error: "missingFile")
        try add(
            "file-cycle",
            sources: [
                ("root.3md", parent(#"{"1":"child.3md"}"#)), ("child.3md", parent(#"{"2":"root.3md"}"#)),
            ],
            error: "cycle"
        )
        try add(
            "unused-bundle-file-cycle",
            sources: [
                ("root.3md", parent(#"{"1":"nested.3md"}"#)),
                (
                    "nested.3md",
                    DocumentCompositionCodec.encode(
                        DocumentComposition(
                            rootID: "main",
                            entries: [
                                .init(id: "main", document: leaf),
                                .init(
                                    id: "unused",
                                    document: document(
                                        "Unused",
                                        body: "x",
                                        metadata: ["3md-files": #"{"1":"root.3md"}"#]
                                    )
                                ),
                            ]
                        )
                    )
                ),
            ],
            error: "cycle"
        )
        for (name, path) in [
            ("escape", "../tree.3md"), ("absolute", "/tree.3md"), ("backslash", "a\\tree.3md"),
            ("url", "https://example.com/a"), ("empty-segment", "a//tree.3md"), ("trailing-slash", "a/"),
            ("control", "bad\nname"),
        ] {
            let ledger = String(decoding: try JSONEncoder().encode(["1": path]), as: UTF8.self)
            try add(
                "invalid-path-" + name,
                sources: [("root.3md", parent(ledger)), ("tree.3md", leafBytes)],
                error: "filePath"
            )
        }
        for (name, ledger) in [
            ("duplicate-key", #"{"1":"a","1":"b"}"#), ("escaped-duplicate", #"{"1":"a","\u0031":"b"}"#),
            ("nonstring", #"{"1":12}"#), ("array", #"["a"]"#), ("empty-glyph", #"{"":"a"}"#),
            ("unicode-glyph", #"{"☃":"a"}"#), ("multichar-glyph", #"{"12":"a"}"#),
            ("trailing-json", #"{"1":"a"} false"#), ("space-glyph", #"{" ":"a"}"#),
        ] {
            try add("invalid-ledger-" + name, sources: [("root.3md", parent(ledger))], error: "fileLedger")
        }
        try add(
            "duplicate-source-alias",
            sources: [("root.3md", leafBytes), ("./root.3md", leafBytes)],
            error: "filePath"
        )
        try add(
            "duplicate-source-nfc",
            sources: [("root.3md", leafBytes), ("café.3md", leafBytes), ("cafe\u{0301}.3md", leafBytes)],
            error: "filePath"
        )
        return result
    }

    private static func document(_ title: String, body: String, metadata: [String: String] = [:]) -> Document {
        Document(
            version: "1.1",
            axis: .space,
            title: title,
            metadata: metadata,
            planes: [
                Plane(z: 0, attributes: ["3md-id": "page"], body: body)
            ]
        )
    }
}
