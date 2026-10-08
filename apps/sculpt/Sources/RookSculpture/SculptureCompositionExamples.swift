/// A small deterministic scene demonstrating repeated and nested model references.
public enum SculptureCompositionExamples {
    public static func courtyard() throws -> SculptureComposition {
        SculptureGenerationProbe.record("courtyard-of-courtyards")
        let starters = SculptureExamples.compositionStarters
        let tile = try SculptureTileSize(width: 24, height: 24, depth: 24)
        let garden = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [Array("TG".utf8), Array("GT".utf8)],
            tileSize: tile,
            bindings: [
                try SculptureModelBinding(glyph: 84, modelID: "tree"),
                try SculptureModelBinding(glyph: 71, modelID: "gate"),
            ]
        )
        let courtyard = try SculptureTileMap(
            width: 3,
            height: 1,
            layers: [Array("CCC".utf8), Array("C.C".utf8), Array("CCC".utf8)],
            tileSize: SculptureTileSize(width: 48, height: 24, depth: 48),
            bindings: [try SculptureModelBinding(glyph: 67, modelID: "garden")]
        )
        return try SculptureComposition(
            title: "Courtyard of courtyards",
            rootID: "root",
            models: [
                "root": .tiles(courtyard),
                "garden": .tiles(garden),
                "tree": .sculpture(starters[2].sculpture),
                "gate": .sculpture(starters[0].sculpture),
            ]
        )
    }
}
