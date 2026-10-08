import Foundation
import RookSculpture
import Testing

@Test func commandsEncodeAsFlatTaggedObjectsAndRoundTrip() throws {
    let commands: [SculptureCommand] = [
        .paint(x: 2, y: 3, z: 0, glyph: "@"),
        .erase(x: 2, y: 3, z: 0),
        .fill(x: 1, y: 1, z: 0, glyph: "+"),
        .clearSlice(z: 0),
        .rotateSlice(z: 0, quarterTurns: 2),
        .rename(title: "A \"quoted\" title"),
    ]
    let actions = ["paint", "erase", "fill", "clearSlice", "rotateSlice", "rename"]
    for (command, action) in zip(commands, actions) {
        let data = try JSONEncoder().encode(command)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["action"] as? String == action)
        #expect(object[action] == nil)
        #expect(try JSONDecoder().decode(SculptureCommand.self, from: data) == command)
    }
    let batch = try SculptureCommandBatch(commands: commands)
    #expect(try JSONDecoder().decode(SculptureCommandBatch.self, from: JSONEncoder().encode(batch)) == batch)
}

@Test func strictCommandDecodingRejectsUnknownIrrelevantMissingAndWrongFields() {
    let sources = [
        #"{"action":"launch","title":"Wrong scope"}"#,
        #"{"action":"rename","title":"OK","z":0}"#,
        #"{"action":"erase","x":0,"y":0,"z":0,"glyph":"@"}"#,
        #"{"action":"clearSlice","z":0,"ignored":null}"#,
        ##"{"action":"paint","x":0,"y":0,"glyph":"#"}"##,
        ##"{"action":"paint","x":"0","y":0,"z":0,"glyph":"#"}"##,
        ##"{"action":"paint","x":0.5,"y":0,"z":0,"glyph":"#"}"##,
        #"{"action":"fill","x":0,"y":0,"z":0,"glyph":35}"#,
        #"{"action":null}"#,
    ]
    for source in sources {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(SculptureCommand.self, from: Data(source.utf8)) }
    }
    #expect(throws: SculptureCommandError.unexpectedFields(["extra", "z"])) {
        try JSONDecoder().decode(
            SculptureCommand.self,
            from: Data(#"{"action":"rename","title":"OK","z":0,"extra":true}"#.utf8)
        )
    }
}

@Test func batchVersionAndCommandCountAreRequiredAndBounded() throws {
    #expect(throws: SculptureCommandError.unsupportedVersion(2)) {
        try SculptureCommandBatch(version: 2, commands: [.clearSlice(z: 0)])
    }
    #expect(throws: SculptureCommandError.invalidCommandCount(0)) { try SculptureCommandBatch(commands: []) }
    #expect(throws: SculptureCommandError.invalidCommandCount(257)) {
        try SculptureCommandBatch(commands: Array(repeating: .clearSlice(z: 0), count: 257))
    }
    let limit = try SculptureCommandBatch(commands: Array(repeating: .clearSlice(z: 0), count: 256))
    #expect(limit.commands.count == SculptureCommandBatch.maximumCommands)
    for source in [
        #"{"version":2,"commands":[{"action":"clearSlice","z":0}]}"#,
        #"{"version":1,"commands":[]}"#,
        #"{"commands":[{"action":"clearSlice","z":0}]}"#,
        #"{"version":1,"commands":[{"action":"clearSlice","z":0}],"ignore":true}"#,
    ] {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SculptureCommandBatch.self, from: Data(source.utf8))
        }
    }
}

@Test func paintEraseAndEmptyGlyphUseExactValidatedCoordinates() throws {
    let source = Sculpture.blank()
    let cell = SculptureCell(x: 2, y: 3, z: 0)
    let painted = try SculptureCommandEngine.apply(.paint(x: cell.x, y: cell.y, z: cell.z, glyph: "@"), to: source)
    #expect(painted.glyph(at: cell) == 64)
    #expect(painted.occupiedCount == 1)
    #expect(source.occupiedCount == 0)
    #expect(try SculptureCommandEngine.apply(.erase(x: cell.x, y: cell.y, z: cell.z), to: painted) == source)
    #expect(
        try SculptureCommandEngine.apply(.paint(x: cell.x, y: cell.y, z: cell.z, glyph: "."), to: painted) == source
    )
    #expect(
        try SculptureCommandEngine.apply(.paint(x: cell.x, y: cell.y, z: cell.z, glyph: "@"), to: painted) == painted
    )
}

@Test func invalidCellsAndGlyphsThrowRatherThanSilentlyIgnoreOrFallback() {
    let source = Sculpture.blank()
    let invalidCommands: [SculptureCommand] = [
        .paint(x: -1, y: 0, z: 0, glyph: "#"),
        .paint(x: 16, y: 0, z: 0, glyph: "#"),
        .erase(x: 0, y: Int.min, z: 0),
        .erase(x: 0, y: Int.max, z: 0),
        .fill(x: 0, y: 0, z: 1, glyph: "#"),
        .fill(x: Int.min, y: 0, z: 0, glyph: "#"),
        .clearSlice(z: -1),
        .rotateSlice(z: Int.max, quarterTurns: 1),
    ]
    for command in invalidCommands {
        #expect(throws: SculptureCommandError.self) { try SculptureCommandEngine.apply(command, to: source) }
    }
    for glyph in ["", "##", " ", "!", "é", "🪶", "\n"] {
        #expect(throws: SculptureCommandError.invalidGlyph(glyph)) {
            try SculptureCommandEngine.apply(.paint(x: 0, y: 0, z: 0, glyph: glyph), to: source)
        }
        #expect(throws: SculptureCommandError.invalidGlyph(glyph)) {
            try SculptureCommandEngine.apply(.fill(x: 0, y: 0, z: 0, glyph: glyph), to: source)
        }
    }
    #expect(source.occupiedCount == 0)
}

@Test func fillVisitsOnlyFourConnectedMatchingCellsOnItsOwnSlice() throws {
    let rows = ["##...", "#.#..", "..#..", ".....", "....."]
    let layer = rows.flatMap { Array($0.utf8) }
    let source = try Sculpture(title: "Islands", width: 5, height: 5, layers: [layer, layer])
    let result = try SculptureCommandEngine.apply(.fill(x: 0, y: 0, z: 0, glyph: "+"), to: source)
    for cell in [SculptureCell(x: 0, y: 0, z: 0), SculptureCell(x: 1, y: 0, z: 0), SculptureCell(x: 0, y: 1, z: 0)] {
        #expect(result.glyph(at: cell) == 43)
    }
    #expect(result.glyph(at: SculptureCell(x: 2, y: 1, z: 0)) == 35)
    #expect(result.glyph(at: SculptureCell(x: 2, y: 2, z: 0)) == 35)
    #expect(result.layers[1] == source.layers[1])
    #expect(result.occupiedCount == source.occupiedCount)
    #expect(source.layers[0] == layer)
    #expect(try SculptureCommandEngine.apply(.fill(x: 0, y: 0, z: 0, glyph: "+"), to: result) == result)
}

@Test func fillCanPaintOrEraseEmptyRegionsWithoutCrossingABarrier() throws {
    let layer = Array((Array(repeating: "..#..", count: 5).joined()).utf8)
    let source = try Sculpture(title: "Barrier", width: 5, height: 5, layers: [layer])
    let filled = try SculptureCommandEngine.apply(.fill(x: 0, y: 0, z: 0, glyph: "o"), to: source)
    #expect(filled.occupiedCount == 15)
    for y in 0..<5 {
        #expect(filled.glyph(at: SculptureCell(x: 1, y: y, z: 0)) == 111)
        #expect(filled.glyph(at: SculptureCell(x: 2, y: y, z: 0)) == 35)
        #expect(filled.glyph(at: SculptureCell(x: 3, y: y, z: 0)) == Sculpture.empty)
    }
    #expect(try SculptureCommandEngine.apply(.fill(x: 0, y: 0, z: 0, glyph: "."), to: filled) == source)
}

@Test func clearingOneSliceLeavesOtherLayersAndTitleIntact() throws {
    var source = Sculpture.orb()
    source.paint(SculptureCell(x: 0, y: 0, z: 0), glyph: 35)
    let result = try SculptureCommandEngine.apply(.clearSlice(z: 0), to: source)
    #expect(result.layers[0].allSatisfy { $0 == Sculpture.empty })
    #expect(Array(result.layers.dropFirst()) == Array(source.layers.dropFirst()))
    #expect(result.title == source.title)
    #expect(source.glyph(at: SculptureCell(x: 0, y: 0, z: 0)) == 35)
}

@Test func rotationIsClockwiseBoundedAndRejectsRectangularSlices() throws {
    let source = try Sculpture(title: "Turn", width: 3, height: 3, layers: [Array("#........".utf8)])
    let once = try SculptureCommandEngine.apply(.rotateSlice(z: 0, quarterTurns: 1), to: source)
    #expect(once.glyph(at: SculptureCell(x: 2, y: 0, z: 0)) == 35)
    let twice = try SculptureCommandEngine.apply(.rotateSlice(z: 0, quarterTurns: 2), to: source)
    #expect(twice.glyph(at: SculptureCell(x: 2, y: 2, z: 0)) == 35)
    let thrice = try SculptureCommandEngine.apply(.rotateSlice(z: 0, quarterTurns: 3), to: source)
    #expect(thrice.glyph(at: SculptureCell(x: 0, y: 2, z: 0)) == 35)
    for turns in [0, -1, 4, Int.max] {
        #expect(throws: SculptureCommandError.invalidRotation(turns)) {
            try SculptureCommandEngine.apply(.rotateSlice(z: 0, quarterTurns: turns), to: source)
        }
    }
    let rectangular = try Sculpture(title: "Rectangle", width: 2, height: 3, layers: [Array("#.....".utf8)])
    #expect(throws: SculptureError.squareLayerRequired) {
        try SculptureCommandEngine.apply(.rotateSlice(z: 0, quarterTurns: 1), to: rectangular)
    }
}

@Test func renamePreservesGeometryAndRejectsInvalidTitles() throws {
    let source = Sculpture.orb()
    let result = try SculptureCommandEngine.apply(.rename(title: "My studio"), to: source)
    #expect(result.title == "My studio")
    #expect(result.layers == source.layers)
    for title in ["", "Line\nBreak", "Café", String(repeating: "A", count: 81)] {
        #expect(throws: SculptureError.invalidTitle) {
            try SculptureCommandEngine.apply(.rename(title: title), to: source)
        }
    }
    #expect(source.title == "Character orb")
}

@Test func batchesApplyInOrderAndFailAtomicallyWithoutChangingTheirSource() throws {
    let source = Sculpture.blank()
    let batch = try SculptureCommandBatch(commands: [
        .paint(x: 1, y: 2, z: 0, glyph: "@"),
        .rotateSlice(z: 0, quarterTurns: 1),
        .rename(title: "Agent edit"),
    ])
    let result = try SculptureCommandEngine.apply(batch, to: source)
    #expect(result.title == "Agent edit")
    #expect(result.glyph(at: SculptureCell(x: 13, y: 1, z: 0)) == 64)
    #expect(try SculptureCommandEngine.apply(batch, to: source) == result)
    let failing = try SculptureCommandBatch(commands: batch.commands + [.paint(x: 16, y: 0, z: 0, glyph: "#")])
    #expect(throws: SculptureCommandError.self) { try SculptureCommandEngine.apply(failing, to: source) }
    #expect(source == Sculpture.blank())
    let badTitle = try SculptureCommandBatch(commands: batch.commands + [.rename(title: "")])
    #expect(throws: SculptureError.invalidTitle) { try SculptureCommandEngine.apply(badTitle, to: source) }
    #expect(source == Sculpture.blank())
}

@Test func inspectionIsCodableAndDescribesTheDocumentCoordinateSystem() throws {
    let source = Sculpture.orb()
    let result = SculptureCommandEngine.inspect(source)
    #expect(result.version == 1)
    #expect(result.title == source.title)
    #expect(result.width == 16 && result.height == 16 && result.depth == 16)
    #expect(result.occupiedCount == 608)
    #expect(result.palette == ["#", "@", "*", "+", "o", "x", ":", "=", "-"])
    #expect(result.emptyGlyph == ".")
    #expect(result.coordinateBase == 0)
    #expect(result.axes["y"] == "row, top to bottom")
    #expect(try JSONDecoder().decode(SculptureInspection.self, from: JSONEncoder().encode(result)) == result)
    #expect(source == Sculpture.orb())
}
