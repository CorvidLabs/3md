@preconcurrency import Foundation

// MARK: - Document + Cross-Plane Links

extension Document {
    /// Extracts all cross-plane links from every plane body in source order.
    ///
    /// Links within each body are returned left to right. A link whose target
    /// is not a finite decimal (for example `[[z=abc]]`) is ignored entirely.
    /// A link that names a non-existent plane is still returned, with
    /// `targetExists` set to `false`.
    ///
    /// - Returns: Cross-plane links in document order.
    public func links() -> [CrossPlaneLink] {
        let knownZ: Set<Double> = Set(planes.map(\.z))
        var result: [CrossPlaneLink] = []

        for plane in planes {
            let extracted = extractLinks(from: plane.body, sourceZ: plane.z, knownZ: knownZ)
            result.append(contentsOf: extracted)
        }

        return result
    }

    /// Returns only links whose target plane does not exist.
    ///
    /// - Returns: Dangling cross-plane links in document order.
    public func danglingLinks() -> [CrossPlaneLink] {
        links().filter { !$0.targetExists }
    }

    /// Returns a compact directed graph of cross-plane references.
    ///
    /// Multiple links with the same source and target collapse into one edge
    /// with an incremented count. The returned edges preserve the first time
    /// each source-target pair appears in the document.
    ///
    /// - Returns: Cross-plane graph edges in first encounter order.
    public func linkGraph() -> [CrossPlaneLinkEdge] {
        var order: [(sourceZ: Double, targetZ: Double)] = []
        var counts: [LinkGraphKey: Int] = [:]
        var existence: [LinkGraphKey: Bool] = [:]

        for link in links() {
            let key = LinkGraphKey(sourceZ: link.sourceZ, targetZ: link.targetZ)
            if counts[key] == nil {
                order.append((sourceZ: link.sourceZ, targetZ: link.targetZ))
                existence[key] = link.targetExists
            }
            counts[key, default: 0] += 1
        }

        return order.map { item in
            let key = LinkGraphKey(sourceZ: item.sourceZ, targetZ: item.targetZ)
            return CrossPlaneLinkEdge(
                sourceZ: item.sourceZ,
                targetZ: item.targetZ,
                targetExists: existence[key] ?? false,
                count: counts[key] ?? 0
            )
        }
    }

    // MARK: - Private Helpers

    /// Hashable key for a source-target pair in the cross-plane link graph.
    private struct LinkGraphKey: Hashable {
        /// Source plane Z position.
        let sourceZ: Double
        /// Target plane Z position.
        let targetZ: Double
    }

    /// Scans a single body string for `[[z=...]]` patterns and returns records.
    private func extractLinks(
        from body: String,
        sourceZ: Double,
        knownZ: Set<Double>
    ) -> [CrossPlaneLink] {
        guard !body.isEmpty else { return [] }

        var result: [CrossPlaneLink] = []
        let pattern = #"\[\[z=([^\]|]+)(?:\|([^\]]*))?\]\]"#

        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [])
        else { return [] }

        let range = NSRange(body.startIndex..., in: body)
        let matches = regex.matches(in: body, options: [], range: range)

        for match in matches {
            guard
                let targetRange = Range(match.range(at: 1), in: body),
                let targetZ = parseFiniteDecimalInLink(String(body[targetRange]))
            else { continue }

            let text: String?
            if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound,
                let textRange = Range(match.range(at: 2), in: body)
            {
                text = String(body[textRange])
            } else {
                text = nil
            }

            result.append(
                CrossPlaneLink(
                    sourceZ: sourceZ,
                    targetZ: targetZ,
                    text: text,
                    targetExists: knownZ.contains(targetZ)
                )
            )
        }

        return result
    }

    /// Validates and parses a finite decimal from a link target capture group.
    ///
    /// Applies the same grammar as the `z` attribute parser: optional sign,
    /// digits with an optional fraction, and an optional exponent. Hex, `inf`,
    /// `nan`, and overflow to infinity are all rejected.
    private func parseFiniteDecimalInLink(_ raw: String) -> Double? {
        let pattern = #"^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$"#
        guard raw.range(of: pattern, options: .regularExpression) != nil else { return nil }
        guard let value = Double(raw), value.isFinite else { return nil }
        return value
    }
}
