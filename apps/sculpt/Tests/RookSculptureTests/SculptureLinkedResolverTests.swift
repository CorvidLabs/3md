import Foundation
import Testing
import ThreeMD

@testable import RookSculpture

#if canImport(CryptoKit)
import CryptoKit
#endif


struct SculptureLinkedResolverTests {
    @Test func resolvesOnlyReachableFilesIntoACompositionWithPathsAndDigests() async throws {
        let chair = try LinkedFixture.voxel("Chair", glyph: 64, width: 2)
        let table = try LinkedFixture.voxel("Table", glyph: 111, width: 2, height: 2, depth: 2)
        let tile = try SculptureTileSize(width: 2, height: 2, depth: 2)
        let root = try SculptureLinkedComposition(
            title: "Dining room",
            width: 2,
            height: 1,
            tileSize: tile,
            layers: [[65, 66]],
            files: [65: "../models/chair.3md", 66: "../models/./table.3md"],
            quarterTurns: [65: 1]
        )
        let files = [
            "scenes/main.3md": try SculptureLinkedCodec.encode(root),
            "models/chair.3md": SculptureCodec.encode(chair),
            "models/table.3md": try LinkedFixture.binaryVoxel(table),
            "models/unused.3md": try LinkedFixture.voxelData("Unused"),
        ]
        let project = LinkedTestProject(files)
        let resolution = try await project.resolve("scenes/main.3md")
        #expect(await project.reads == ["models/chair.3md", "models/table.3md"])
        let paths = ["models/chair.3md", "models/table.3md", "scenes/main.3md"]
        let ids = LinkedFixture.bundleIDs(paths)
        let chairID = try #require(ids["models/chair.3md"])
        let tableID = try #require(ids["models/table.3md"])
        let rootID = try #require(ids["scenes/main.3md"])
        let expected = try SculptureComposition(
            title: "Dining room",
            rootID: rootID,
            models: [
                rootID: .tiles(
                    try SculptureTileMap(
                        width: 2,
                        height: 1,
                        layers: [[65, 66]],
                        tileSize: tile,
                        bindings: [
                            .init(glyph: 65, modelID: chairID, quarterTurns: 1), .init(glyph: 66, modelID: tableID),
                        ]
                    )
                ),
                chairID: .sculpture(chair),
                tableID: .sculpture(table),
            ]
        )
        #expect(resolution.composition == expected)
        #expect(resolution.scene == .composition(expected))
        #expect(resolution.rootPath == "scenes/main.3md")
        #expect(resolution.resolvedPaths == paths)
        #expect(resolution.modelPaths == [chairID: "models/chair.3md", tableID: "models/table.3md", rootID: paths[2]])
        for path in paths {
            let data = try #require(files[path])
            #if canImport(CryptoKit)
            let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #else
            let hex = SculptureSHA256.hex(data)
            #endif
            #expect(resolution.digests[path] == hex)
        }
        #expect(Set(resolution.digests.keys) == Set(paths))
        let normalized = try await SculptureLinkedResolver.resolve(
            rootPath: "scenes/./main.3md",
            rootData: try #require(files["scenes/main.3md"]),
            read: { path, maximum in try await project.read(path, maximumBytes: maximum) }
        )
        #expect(normalized == resolution)
    }

    @Test func theRootCanBeReadThroughTheSameReader() async throws {
        let project = LinkedTestProject([
            "scenes/root.3md": try LinkedFixture.linkedData(files: ["#": "../leaf.3md"]),
            "leaf.3md": try LinkedFixture.voxelData(),
        ])
        let reader: SculptureLinkedReader = { path, maximum in try await project.read(path, maximumBytes: maximum) }
        let resolution = try await SculptureLinkedResolver.resolve(rootPath: "scenes/./root.3md", read: reader)
        #expect(await project.reads == ["scenes/root.3md", "leaf.3md"])
        #expect(resolution == (try await project.resolve("scenes/root.3md")))
        await #expect(throws: SculptureLinkedError.file(path: "gone.3md", reason: "is not in the project folder.")) {
            try await SculptureLinkedResolver.resolve(rootPath: "gone.3md", read: reader)
        }
        await #expect(throws: SculptureLinkedError.outsideProject) {
            try await SculptureLinkedResolver.resolve(rootPath: "../root.3md", read: reader)
        }
    }

    @Test func aSharedChildIsReadOnceAcrossGlyphsAndNestedLinkedRoots() async throws {
        let project = LinkedTestProject([
            "root.3md": try LinkedFixture.linkedData(files: ["A": "leaf.3md", "B": "leaf.3md", "C": "rooms/sub.3md"]),
            "rooms/sub.3md": try LinkedFixture.linkedData("Sub room", files: ["D": "../leaf.3md"]),
            "leaf.3md": try LinkedFixture.voxelData(),
        ])
        let resolution = try await project.resolve("root.3md")
        #expect(await project.reads == ["leaf.3md", "rooms/sub.3md"])
        let ids = LinkedFixture.bundleIDs(["leaf.3md", "rooms/sub.3md", "root.3md"])
        let leafID = try #require(ids["leaf.3md"])
        let subID = try #require(ids["rooms/sub.3md"])
        let rootID = try #require(ids["root.3md"])
        #expect(resolution.composition.models.count == 3)
        guard case .tiles(let rootMap)? = resolution.composition.models[rootID],
            case .tiles(let subMap)? = resolution.composition.models[subID]
        else {
            Issue.record("Expected linked tile maps")
            return
        }
        #expect(rootMap.bindings.map(\.modelID) == [leafID, leafID, subID])
        #expect(subMap.bindings.map(\.modelID) == [leafID])
        #expect(try resolution.composition.expanded().layers == [[35, 35, 35]])
    }

    @Test func missingFilesAndReaderFailuresNameTheProjectPath() async throws {
        let rootData = try LinkedFixture.linkedData(files: ["#": "rooms/gone.3md"])
        let missing = LinkedTestProject(["root.3md": rootData])
        await #expect(throws: SculptureLinkedError.missingFile(path: "rooms/gone.3md", linkedFrom: "root.3md")) {
            try await missing.resolve("root.3md")
        }
        let failures: [(any Error & Sendable, SculptureLinkedError)] = [
            (POSIXError(.ENOENT), .missingFile(path: "rooms/gone.3md", linkedFrom: "root.3md")),
            (POSIXError(.EACCES), .file(path: "rooms/gone.3md", reason: "could not be read: Permission denied.")),
            (CocoaError(.fileReadNoPermission), .file(path: "rooms/gone.3md", reason: "could not be read.")),
            (
                SculptureLinkedError.file(path: "rooms/gone.3md", reason: "is a symbolic link."),
                .file(path: "rooms/gone.3md", reason: "is a symbolic link.")
            ),
        ]
        for (thrown, expected) in failures {
            await #expect(throws: expected) {
                try await SculptureLinkedResolver.resolve(
                    rootPath: "root.3md",
                    rootData: rootData,
                    read: { _, _ in throw thrown }
                )
            }
        }
    }

    @Test func cyclesAreReportedAsChainsOfProjectPaths() async throws {
        let chain = LinkedTestProject([
            "root.3md": try LinkedFixture.linkedData(files: ["A": "a.3md"]),
            "a.3md": try LinkedFixture.linkedData("A", files: ["B": "nested/b.3md"]),
            "nested/b.3md": try LinkedFixture.linkedData("B", files: ["C": "../a.3md"]),
        ])
        await #expect(throws: SculptureLinkedError.cycle(["a.3md", "nested/b.3md", "a.3md"])) {
            try await chain.resolve("root.3md")
        }
        let itself = LinkedTestProject(["root.3md": try LinkedFixture.linkedData(files: ["A": "./root.3md"])])
        await #expect(throws: SculptureLinkedError.cycle(["root.3md", "root.3md"])) {
            try await itself.resolve("root.3md")
        }
        #expect(
            SculptureLinkedError.cycle(["a.3md", "nested/b.3md", "a.3md"]).localizedDescription
                == "Linked files form a cycle: a.3md → nested/b.3md → a.3md."
        )
    }

    @Test func invalidAndEscapingPathsAreRefusedNamingTheLinkingFile() async throws {
        for link in ["../../outside.3md", "/absolute.3md", "models//leaf.3md", "C:\\leaf.3md", "models/", ".."] {
            let project = LinkedTestProject([
                "scenes/root.3md": try LinkedFixture.linkedData(files: ["#": link])
            ])
            await #expect(throws: SculptureLinkedError.invalidPath(link: link, linkedFrom: "scenes/root.3md")) {
                try await project.resolve("scenes/root.3md")
            }
            #expect(await project.reads.isEmpty)
        }
        let root = try LinkedFixture.linkedData(files: ["#": "leaf.3md"])
        for rootPath in ["../root.3md", "/root.3md", "", ".", "scenes/.."] {
            await #expect(throws: SculptureLinkedError.outsideProject) {
                try await SculptureLinkedResolver.resolve(rootPath: rootPath, rootData: root, read: { _, _ in Data() })
            }
        }
    }

    @Test func aRootInsideTheProjectWhosePathCannotBeRepresentedIsNamedNotCalledOutside() async throws {
        let root = try LinkedFixture.linkedData(files: ["#": "leaf.3md"])
        // Finder shows a POSIX colon as "/". Backslashes and control characters are legal in macOS names too.
        let cases = [
            ("a:b.3md", "a colon, which Finder shows as \"/\""),
            ("dir\\x/root.3md", "a backslash"),
            ("scenes/\u{7}root.3md", "a control character"),
        ]
        for (rootPath, character) in cases {
            for useReader in [false, true] {
                do {
                    if useReader {
                        _ = try await SculptureLinkedResolver.resolve(rootPath: rootPath, read: { _, _ in root })
                    } else {
                        _ = try await SculptureLinkedResolver.resolve(
                            rootPath: rootPath,
                            rootData: root,
                            read: { _, _ in Data() }
                        )
                    }
                    Issue.record("\(rootPath) resolved")
                } catch let SculptureLinkedError.file(path, reason) {
                    #expect(path == rootPath)
                    #expect(reason.contains("containing \(character)") && reason.hasSuffix("Rename it."))
                    #expect(!reason.contains("not inside the chosen project folder"))
                }
            }
        }
        // A root that stays inside the project but is malformed is invalid, not outside.
        for rootPath in ["scenes//root.3md", "scenes/"] {
            await #expect(throws: SculptureLinkedError.file(path: rootPath, reason: "is not a valid project path.")) {
                try await SculptureLinkedResolver.resolve(rootPath: rootPath, rootData: root, read: { _, _ in Data() })
            }
        }
    }

    @Test func nestedLinkOccurrencesBeyondThreeMDsLimitNameTheRootWithoutPortableSaveAdvice() async throws {
        // Eleven files on one path, each linking the next under four characters with one placed: 40 links at depth
        // 11 pass every interim cap, but ThreeMD counts every ledger entry along every path and the root reaches
        // more than its 1,000,000 nested occurrences.
        var files = ["leaf.3md": try LinkedFixture.voxelData()]
        for level in 0..<10 {
            let next = level == 9 ? "leaf.3md" : "c\(level + 1).3md"
            files["c\(level).3md"] = try LinkedFixture.linkedData(
                "Level \(level)",
                files: ["A": next, "B": next, "C": next, "D": next],
                placed: "A"
            )
        }
        let project = LinkedTestProject(files)
        do {
            _ = try await project.resolve("c0.3md")
            Issue.record("The chain resolved")
        } catch let SculptureLinkedError.file(path, reason) {
            #expect(path == "c0.3md")
            #expect(reason.contains("1,000,000 nested link occurrences"))
            #expect(!reason.contains("portable ThreeMD capacity") && !reason.contains("existing Sculpt format"))
        }
        #expect(await project.reads.count == 10, "Each file is read once before ThreeMD refuses the graph.")
    }

    @Test func eachUnsupportedChildKindIsRefusedByNameAndContent() async throws {
        let voxel = try LinkedFixture.voxel(width: 2)
        let native = try SculptureComposition(
            title: "Native",
            rootID: "root",
            models: [
                "root": .tiles(
                    try SculptureTileMap(
                        width: 1,
                        height: 1,
                        layers: [[65]],
                        tileSize: .init(width: 2, height: 1, depth: 1),
                        bindings: [.init(glyph: 65, modelID: "leaf")]
                    )
                ),
                "leaf": .sculpture(voxel),
            ]
        )
        let portable = try SculptureThreeMDCodec.capture(.composition(native))
        let linkedDocument = try DocumentStorageCodec.decode(LinkedFixture.linkedData(files: ["#": "leaf.3md"]))
        var ledgerVoxel = SculptureCodec.document(for: voxel).metadata
        ledgerVoxel["3md-files"] = "{\"#\":\"leaf.3md\"}"
        let bundleProject = LinkedTestProject([
            "bundle-root.3md": try LinkedFixture.linkedData(files: ["#": "leaf.3md"]),
            "leaf.3md": try LinkedFixture.voxelData(),
        ])
        let bundled = try await bundleProject.resolve("bundle-root.3md")
        let bundle = try SculptureLinkedBundle.encode(bundled, format: .readable)
        var cases: [(Data, SculptureLinkedFileKind)] = [
            (try SculptureBinaryCodec.encode(voxel), .compactStorage)
        ]
        #if canImport(Compression)
        cases.append((try LinkedFixture.binaryVoxel(voxel, compression: .lzfse), .compressedBinary))
        #endif
        cases += [
            (
                try DocumentStorageCodec.encode(linkedDocument, format: .binary(compression: .none)),
                .binaryLinkedComposition
            ),
            (try SculptureCompositionCodec.encode(native), .composition),
            (try SculptureWorldCodec.encode(SculptureWorld(title: "World", library: native, instances: [])), .world),
            (try SculptureThreeMDCodec.encode(portable), .compositionProfile),
            (try SculptureThreeMDCodec.encode(portable, format: .binary(compression: .none)), .compositionProfile),
            (bundle, .compositionProfile),
            (Data("# Notes\n\nPlain Markdown.\n".utf8), .markdown),
            (Data("---\ntitle: Notes\n---\nHello\n".utf8), .markdown),
            (try LinkedFixture.document(metadata: ["scene-schema": "other"], planes: []), .markdown),
            (try LinkedFixture.document(metadata: [:], planes: [Plane(z: 0, body: "Hello")]), .markdown),
            (
                try LinkedFixture.document(metadata: ledgerVoxel, planes: SculptureCodec.document(for: voxel).planes),
                .ledgerOutsideLinkedComposition
            ),
            (try LinkedFixture.document(metadata: ["3md-files": "{}"], planes: []), .ledgerOutsideLinkedComposition),
        ]
        for (data, kind) in cases {
            let project = LinkedTestProject([
                "root.3md": try LinkedFixture.linkedData(files: ["#": "kinds/child.3md"], tile: 2),
                "kinds/child.3md": data,
            ])
            await #expect(throws: SculptureLinkedError.unsupportedChild(path: "kinds/child.3md", kind: kind)) {
                try await project.resolve("root.3md")
            }
        }
        let message = SculptureLinkedError.unsupportedChild(path: "kinds/child.3md", kind: .compactStorage)
        #expect(message.localizedDescription.hasPrefix("kinds/child.3md is a Sculpt compact 3mdb file."))
    }

    @Test func rootsThatAreNotReadableLinkedCompositionsAreRefusedByName() async throws {
        let linked = try DocumentStorageCodec.decode(LinkedFixture.linkedData(files: ["#": "leaf.3md"]))
        let cases: [(Data, String)] = [
            (try LinkedFixture.voxelData(), "is a voxel model, not a linked composition."),
            (
                try DocumentStorageCodec.encode(linked, format: .binary(compression: .none)),
                SculptureLinkedError.binaryLinkedRoot.localizedDescription
            ),
            (
                try SculptureBinaryCodec.encode(LinkedFixture.voxel()),
                "is a Sculpt compact 3mdb file, not a linked composition."
            ),
        ]
        for (data, reason) in cases {
            await #expect(throws: SculptureLinkedError.file(path: "root.3md", reason: reason)) {
                try await SculptureLinkedResolver.resolve(
                    rootPath: "root.3md",
                    rootData: data,
                    read: { _, _ in Data() }
                )
            }
        }
    }

    @Test func malformedChildrenAndOversizedModelsNameTheirFilesWithoutBundleIDs() async throws {
        let malformedVoxel = Data(
            "---\n3md: 1.0\naxis: space\nscene-schema: ascii-sculpture-1\nwidth: 2\nheight: 1\n---\n".utf8
        )
        let malformedLinked = try LinkedFixture.document(
            metadata: ["scene-schema": "ascii-linked-composition-1", "3md-files": "{}"],
            planes: []
        )
        for (name, data) in [("bad-voxel.3md", malformedVoxel), ("bad-linked.3md", malformedLinked)] {
            let project = LinkedTestProject(["root.3md": try LinkedFixture.linkedData(files: ["#": name]), name: data])
            do {
                _ = try await project.resolve("root.3md")
                Issue.record("\(name) was accepted")
            } catch SculptureLinkedError.file(let path, let reason) {
                #expect(path == name && !reason.isEmpty)
            }
        }
        let large = LinkedTestProject([
            "root.3md": try LinkedFixture.linkedData(files: ["#": "big.3md"], turns: ["#": 1]),
            "big.3md": try LinkedFixture.voxelData("Big", size: 2),
        ])
        do {
            _ = try await large.resolve("root.3md")
            Issue.record("An oversized child was accepted")
        } catch SculptureLinkedError.file(let path, let reason) {
            #expect(path == "big.3md")
            #expect(!reason.contains("file-0"))
        }
    }

    @Test func fileCountCapHoldsAtSixtyFourAndRefusesTheNextFile() async throws {
        let glyphs = Array((UInt8(33)...UInt8(126)).filter { $0 != Sculpture.empty })
        for count in [63, 64] {
            var files: [String: Data] = [:]
            var ledger: [UInt8: String] = [:]
            for (index, glyph) in glyphs.prefix(count).enumerated() {
                let path = "leaves/leaf-\(index).3md"
                ledger[glyph] = path
                files[path] = try LinkedFixture.voxelData("Leaf \(index)")
            }
            let root = try SculptureLinkedComposition(
                title: "Many leaves",
                width: count,
                height: 1,
                tileSize: .init(width: 1, height: 1, depth: 1),
                layers: [Array(glyphs.prefix(count))],
                files: ledger
            )
            files["root.3md"] = try SculptureLinkedCodec.encode(root)
            let project = LinkedTestProject(files)
            if count == 63 {
                let resolution = try await project.resolve("root.3md")
                #expect(resolution.resolvedPaths.count == SculptureLinkedResolver.maximumFiles)
                #expect(resolution.composition.models.count == 64)
            } else {
                await #expect(throws: SculptureLinkedError.limit(kind: .files, maximum: 64, path: "leaves/leaf-63.3md"))
                {
                    try await project.resolve("root.3md")
                }
                #expect(await project.reads.count == 63)
            }
        }
    }

    @Test func linkCapHoldsAtFiveHundredTwelveLedgerEntries() async throws {
        let glyphs = Array((UInt8(33)...UInt8(126)).filter { $0 != Sculpture.empty })
        for last in [86, 87] {
            var files: [String: Data] = ["leaf.3md": try LinkedFixture.voxelData()]
            var rootLedger: [UInt8: String] = [:]
            for index in 0..<6 {
                let path = "sub-\(index).3md"
                rootLedger[glyphs[index]] = path
                let count = index == 5 ? last : 84
                let sub = try SculptureLinkedComposition(
                    title: "Sub \(index)",
                    width: 1,
                    height: 1,
                    tileSize: .init(width: 1, height: 1, depth: 1),
                    layers: [[glyphs[0]]],
                    files: Dictionary(uniqueKeysWithValues: glyphs.prefix(count).map { ($0, "leaf.3md") })
                )
                files[path] = try SculptureLinkedCodec.encode(sub)
            }
            let root = try SculptureLinkedComposition(
                title: "Many links",
                width: 6,
                height: 1,
                tileSize: .init(width: 1, height: 1, depth: 1),
                layers: [Array(glyphs.prefix(6))],
                files: rootLedger
            )
            files["root.3md"] = try SculptureLinkedCodec.encode(root)
            let project = LinkedTestProject(files)
            if last == 86 {
                let resolution = try await project.resolve("root.3md")
                #expect(resolution.resolvedPaths.count == 8)
            } else {
                await #expect(throws: SculptureLinkedError.limit(kind: .links, maximum: 512, path: "sub-5.3md")) {
                    try await project.resolve("root.3md")
                }
            }
        }
    }

    @Test func depthCapHoldsAtSixteenFilesOnOnePath() async throws {
        for length in [16, 17] {
            var files: [String: Data] = [:]
            for level in 1..<length {
                files["level-\(level).3md"] = try LinkedFixture.linkedData(
                    "Level \(level)",
                    files: ["#": "level-\(level + 1).3md"]
                )
            }
            files["level-\(length).3md"] = try LinkedFixture.voxelData()
            let project = LinkedTestProject(files)
            if length == 16 {
                let resolution = try await project.resolve("level-1.3md")
                #expect(resolution.resolvedPaths.count == SculptureLinkedResolver.maximumDepth)
                #expect(try resolution.composition.expanded().layers == [[35]])
            } else {
                await #expect(throws: SculptureLinkedError.limit(kind: .depth, maximum: 16, path: "level-17.3md")) {
                    try await project.resolve("level-1.3md")
                }
            }
        }
    }

    @Test func depthCapCountsAnAlreadyResolvedSubtreeReachedLater() async throws {
        let project = LinkedTestProject([
            "root.3md": try LinkedFixture.linkedData(files: ["!": "c1.3md", "#": "s1.3md"]),
            "c1.3md": try LinkedFixture.linkedData("C1", files: ["#": "c2.3md"]),
            "c2.3md": try LinkedFixture.voxelData(),
            "s1.3md": try LinkedFixture.linkedData("S1", files: ["#": "s2.3md"]),
            "s2.3md": try LinkedFixture.linkedData("S2", files: ["#": "c1.3md"]),
        ])
        var limits = SculptureLinkedLimits.standard
        limits.depth = 4
        await #expect(throws: SculptureLinkedError.limit(kind: .depth, maximum: 4, path: "c1.3md")) {
            try await project.resolve("root.3md", limits: limits)
        }
        limits.depth = 5
        #expect(try await project.resolve("root.3md", limits: limits).resolvedPaths.count == 5)
    }

    @Test func pathAndComponentCapsHoldAtTheirLimits() async throws {
        let directories = ["a", "b", "c", "d"].map { String(repeating: $0, count: 250) }.joined(separator: "/") + "/"
        let atLimit = directories + String(repeating: "x", count: 16) + ".3md"
        let beyond = directories + String(repeating: "x", count: 17) + ".3md"
        #expect(atLimit.utf8.count == 1_024 && beyond.utf8.count == 1_025)
        let component = String(repeating: "y", count: 251) + ".3md"
        let longComponent = String(repeating: "y", count: 252) + ".3md"
        #expect(component.utf8.count == 255)
        for (link, expected) in [
            (atLimit, nil), (component, nil), ("dir/" + component, nil),
            (beyond, SculptureLinkedError.limit(kind: .pathBytes, maximum: 1_024, path: "root.3md")),
            (longComponent, .limit(kind: .componentBytes, maximum: 255, path: "root.3md")),
            (longComponent + "/leaf.3md", .limit(kind: .componentBytes, maximum: 255, path: "root.3md")),
        ] as [(String, SculptureLinkedError?)] {
            let project = LinkedTestProject([
                "root.3md": try LinkedFixture.linkedData(files: ["#": link]),
                link: try LinkedFixture.voxelData(),
            ])
            if let expected {
                await #expect(throws: expected) { try await project.resolve("root.3md") }
            } else {
                #expect(try await project.resolve("root.3md").resolvedPaths.contains(link))
            }
        }
        // The normalized path is capped too: a short link from a deep file can exceed it.
        let deepRoot = directories + "root.3md"
        let deep = LinkedTestProject([deepRoot: try LinkedFixture.linkedData(files: ["#": "leaf-with-a-long-name.3md"])]
        )
        await #expect(throws: SculptureLinkedError.limit(kind: .pathBytes, maximum: 1_024, path: deepRoot)) {
            try await deep.resolve(deepRoot)
        }
        let longRoot = String(repeating: "r/", count: 512) + "x.3md"
        await #expect(throws: SculptureLinkedError.limit(kind: .pathBytes, maximum: 1_024, path: longRoot)) {
            try await SculptureLinkedResolver.resolve(rootPath: longRoot, rootData: Data(), read: { _, _ in Data() })
        }
    }

    @Test func definitionByteBudgetHoldsAtItsLimitAndBoundsEachRead() async throws {
        let root = try LinkedFixture.linkedData(files: ["#": "leaf.3md"])
        let leaf = try LinkedFixture.voxelData()
        let project = LinkedTestProject(["root.3md": root, "leaf.3md": leaf])
        var limits = SculptureLinkedLimits.standard
        limits.definitionBytes = root.count + leaf.count
        #expect(try await project.resolve("root.3md", limits: limits).resolvedPaths == ["leaf.3md", "root.3md"])
        limits.definitionBytes -= 1
        await #expect(
            throws: SculptureLinkedError.limit(
                kind: .definitionBytes,
                maximum: limits.definitionBytes,
                path: "leaf.3md"
            )
        ) {
            try await project.resolve("root.3md", limits: limits)
        }
        limits.definitionBytes = root.count - 1
        await #expect(
            throws: SculptureLinkedError.limit(kind: .definitionBytes, maximum: root.count - 1, path: "root.3md")
        ) {
            try await project.resolve("root.3md", limits: limits)
        }
        let requested = LinkedRequestLog()
        await #expect(
            throws: SculptureLinkedError.limit(kind: .definitionBytes, maximum: 16 * 1_048_576, path: "leaf.3md")
        ) {
            try await SculptureLinkedResolver.resolve(
                rootPath: "root.3md",
                rootData: root,
                read: { _, maximum in
                    await requested.record(maximum)
                    return Data(count: maximum + 1)
                }
            )
        }
        #expect(await requested.values == [SculptureLinkedResolver.maximumDefinitionBytes - root.count])
    }

    @Test func rawLedgerCapHoldsAtOneHundredTwentyEightKiB() async throws {
        let base = try DocumentStorageCodec.decode(LinkedFixture.linkedData(files: ["#": "leaf.3md"]))
        for (padding, accepted) in [(131_072 - 16, true), (131_072 - 15, false)] {
            var metadata = base.metadata
            metadata["3md-files"] = "{\"#\":" + String(repeating: " ", count: padding) + "\"leaf.3md\"}"
            #expect(metadata["3md-files"]?.utf8.count == (accepted ? 131_072 : 131_073))
            for rootIsParent in [true, false] {
                let linked = try LinkedFixture.document(metadata: metadata, planes: base.planes)
                let files: [String: Data] =
                    rootIsParent
                    ? ["root.3md": linked, "leaf.3md": try LinkedFixture.voxelData()]
                    : [
                        "root.3md": try LinkedFixture.linkedData(files: ["#": "sub.3md"]), "sub.3md": linked,
                        "leaf.3md": try LinkedFixture.voxelData(),
                    ]
                let project = LinkedTestProject(files)
                if accepted {
                    #expect(try await project.resolve("root.3md").resolvedPaths.contains("leaf.3md"))
                } else {
                    let path = rootIsParent ? "root.3md" : "sub.3md"
                    await #expect(throws: SculptureLinkedError.limit(kind: .ledgerBytes, maximum: 131_072, path: path))
                    {
                        try await project.resolve("root.3md")
                    }
                }
            }
        }
    }

    @Test func cancellationIsHonoredBetweenFiles() async throws {
        let rootData = try LinkedFixture.linkedData(files: ["A": "a.3md", "B": "b.3md"])
        let project = LinkedTestProject([
            "root.3md": rootData, "a.3md": try LinkedFixture.voxelData(), "b.3md": try LinkedFixture.voxelData(),
        ])
        let task = Task {
            try await SculptureLinkedResolver.resolve(
                rootPath: "root.3md",
                rootData: rootData,
                read: { path, maximum in
                    let data = try await project.read(path, maximumBytes: maximum)
                    withUnsafeCurrentTask { $0?.cancel() }
                    return data
                }
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await project.reads == ["a.3md"])
        let cancelled = LinkedTestProject(project.files)
        let early = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cancelled.resolve("root.3md")
        }
        await #expect(throws: CancellationError.self) { try await early.value }
        #expect(await cancelled.reads.isEmpty)
    }

    @Test func linksAreNormalizedToNFCBeforeReading() async throws {
        // Swift String equality is canonical, so these checks compare Unicode scalars.
        let decomposed = "mode\u{0300}les/te\u{0302}te.3md"
        let composed = decomposed.precomposedStringWithCanonicalMapping
        #expect(!composed.unicodeScalars.elementsEqual(decomposed.unicodeScalars))
        let project = LinkedTestProject([
            "root.3md": try LinkedFixture.linkedData(files: ["#": decomposed]),
            composed: try LinkedFixture.voxelData(),
        ])
        let resolution = try await project.resolve("root.3md")
        let reads = await project.reads
        #expect(reads.count == 1 && reads.first?.unicodeScalars.elementsEqual(composed.unicodeScalars) == true)
        #expect(resolution.resolvedPaths.first?.unicodeScalars.elementsEqual(composed.unicodeScalars) == true)
        #expect(resolution.modelPaths.values.contains { $0.unicodeScalars.elementsEqual(composed.unicodeScalars) })
    }
}

private actor LinkedRequestLog {
    fileprivate private(set) var values: [Int] = []

    fileprivate func record(_ value: Int) { values.append(value) }
}
