/// Sparse placement examples with no allocation for the empty distance between models.
public enum SculptureWorldExamples {
    public static func wideWorld() throws -> SculptureWorld {
        SculptureGenerationProbe.record("gardens-wide-world")
        let library = try SculptureCompositionExamples.courtyard()
        let positions: [(String, Int64, Int64)] = [
            ("garden-origin", 0, 0),
            ("garden-neighbor", 96, 0),
            ("garden-distant", 512, 256),
            ("garden-trillion", 1_000_000_000_000, -1_000_000_000_000),
        ]
        let instances = try positions.map { id, x, z in
            try SculptureWorldInstance(
                id: id,
                modelID: "garden",
                origin: SculptureWorldPoint(x: x, y: 0, z: z)
            )
        }
        return try SculptureWorld(title: "Gardens without a boundary", library: library, instances: instances)
    }
}
