import Foundation

let directory = URL(fileURLWithPath: "/private/tmp/sculpt-cross-language-20261005")
let url = directory.appendingPathComponent("conformance/interchange/manifest.json")
guard var catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
    var cases = catalog["cases"] as? [[String: Any]]
else { throw CocoaError(.fileReadCorruptFile) }
for (name, kind) in [("portable-voxel", "document"), ("portable-composition", "composition"), ("portable-world", "composition")] {
    let path = "conformance/sculpt-fixtures/\(name)"
    cases.append([
        "id": "sculpt-\(name)", "kind": kind, "sourceFile": path + ".3md",
        "canonicalFile": path + ".3md", "binaryFile": path + ".3mdb", "formats": ["canonical", "binary"],
    ])
}
catalog["cases"] = cases
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
