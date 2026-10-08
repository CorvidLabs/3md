import Foundation

enum SourceBoundaries {
    static let productTargets = ["RookApp", "RookCore", "RookSculpture", "RookRendering"]
    private static let toolingTargets: Set<String> = ["RookTool", "RookTooling", "RookVerification"]
    private static let forbiddenTokens = [
        "URLSession", "NWConnection", "NWBrowser", "CKContainer", "/bin/sh", "/bin/bash",
        "Process\\s*\\(", "popen\\s*\\(",
    ]
    /// The only stored defaults key a product source may name.
    internal static let allowedDefaultsKey = "rook.appearance"
    /// The entitlement keys the app holds, each set to true, and no others.
    internal static let requiredEntitlements = [
        "com.apple.security.app-sandbox", "com.apple.security.files.user-selected.read-write",
    ]
    /// File watcher and security-scoped bookmark APIs, matched literally with the most specific spelling first.
    /// `BookmarkData` covers the CoreFoundation bookmark functions, such as `CFURLCreateBookmarkData`.
    /// Starting and stopping access to a user-selected URL stays allowed.
    internal static let watcherAndBookmarkTokens = [
        "FSEventStream", "FSEvents", "DispatchSource.makeFileSystemObjectSource", "makeFileSystemObjectSource",
        "DispatchSourceFileSystemObject", "EVFILT_VNODE", "NSFilePresenter", "NSFileCoordinator",
        "resolvingBookmarkData", "writeBookmarkData", "bookmarkData", "BookmarkData",
    ]
    /// Defaults store APIs, matched literally with the most specific spelling first.
    /// Product sources reach stored defaults only through `@AppStorage("rook.appearance")`.
    internal static let defaultsStoreTokens = [
        "NSUbiquitousKeyValueStore", "NSUserDefaults", "UserDefaults", "CFPreferences",
    ]
    /// Calls whose first unlabeled argument is a stored key.
    private static let storageWrapperPattern = "\\b(?:AppStorage|SceneStorage)\\s*(?:<[^<>()]*>)?\\s*\\("
    /// UserDefaults accessors whose `forKey:` argument is a stored key.
    private static let defaultsAccessorPattern =
        "(?<![A-Za-z0-9_])(?:set|setValue|object|string|stringArray|array|dictionary|data|bool|integer|float"
        + "|double|url|value|removeObject)\\s*\\("

    static func validateSources(in root: URL) throws {
        for target in productTargets {
            let directory = root.appendingPathComponent("Sources/\(target)")
            try requireFile(directory)
            guard
                let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey]
                )
            else { throw ToolingError.missingFile(directory.path) }

            for case let file as URL in enumerator where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                let tokens =
                    forbiddenTokens + libraryFence(for: target)
                    + toolingTargets.sorted().map { "import\\s+\($0)\\b" }
                for token in tokens where text.range(of: token, options: .regularExpression) != nil {
                    throw ToolingError.forbiddenSource(path: file.path, token: token)
                }
                if let token = watcherAndBookmarkTokens.first(where: { text.contains($0) }) {
                    throw ToolingError.forbiddenSource(path: file.path, token: token)
                }
                if let key = try disallowedDefaultsKey(in: text) {
                    throw ToolingError.storedDefaultsKey(path: file.path, key: key)
                }
                if let token = defaultsStoreTokens.first(where: { text.contains($0) }) {
                    throw ToolingError.forbiddenSource(path: file.path, token: token)
                }
            }
        }
    }

    /// Requires `App/Rook.entitlements` to hold exactly the required keys, each a Boolean true.
    /// - Parameter root: The repository root.
    internal static func validateEntitlements(in root: URL) throws {
        let file = root.appendingPathComponent("App/Rook.entitlements")
        try requireFile(file)
        try validateEntitlements(Data(contentsOf: file), path: file.path)
    }

    /// Requires an entitlements property list to hold exactly the required keys, each a Boolean true.
    /// - Parameters:
    ///   - data: The property list bytes.
    ///   - path: The file named in a refusal.
    internal static func validateEntitlements(_ data: Data, path: String) throws {
        let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil)
        guard let values = propertyList as? [String: Any] else { throw ToolingError.invalidEntitlements(path) }
        if let key = values.keys.sorted().first(where: { !requiredEntitlements.contains($0) }) {
            throw ToolingError.unexpectedEntitlement(path: path, key: key)
        }
        if let key = requiredEntitlements.first(where: { !isBooleanTrue(values[$0]) }) {
            throw ToolingError.requiredEntitlement(path: path, key: key)
        }
    }

    /// Returns the first stored defaults key in a product source other than `rook.appearance`.
    ///
    /// AppStorage and SceneStorage keys must be the literal `"rook.appearance"`. A defaults accessor with a
    /// literal `forKey:` argument must name `rook.appearance`. This check does not resolve other keys, such as a
    /// named constant; `validateSources` refuses every defaults store API by name instead.
    /// - Parameter text: Swift source text.
    /// - Returns: The refused key as written, or nil when the source names no other key.
    internal static func disallowedDefaultsKey(in text: String) throws -> String? {
        let units = Array(text.utf16)
        for start in try callStarts(matching: storageWrapperPattern, in: text) {
            guard let arguments = callArguments(in: units, from: start) else { return "<unreadable>" }
            guard let key = arguments.map({ labeled($0) }).first(where: { $0.label == nil && !$0.value.isEmpty })
            else { return "<missing>" }
            let literal = literalContents(key.value)
            guard literal == allowedDefaultsKey else { return literal ?? key.value }
        }
        for start in try callStarts(matching: defaultsAccessorPattern, in: text) {
            for argument in callArguments(in: units, from: start) ?? [] {
                let parts = labeled(argument)
                guard parts.label == "forKey", let key = literalContents(parts.value), key != allowedDefaultsKey
                else { continue }
                return key
            }
        }
        return nil
    }

    private static func isBooleanTrue(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID() && number.boolValue
    }

    /// Returns the UTF-16 offset just after each match's opening parenthesis.
    private static func callStarts(matching pattern: String, in text: String) throws -> [Int] {
        let expression = try NSRegularExpression(pattern: pattern)
        return expression.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
            .map { NSMaxRange($0.range) }
    }

    /// Splits the top-level arguments of a call, skipping nested brackets and string contents.
    /// - Returns: The trimmed arguments, or nil when the call does not close.
    private static func callArguments(in units: [UInt16], from start: Int) -> [String]? {
        var arguments: [String] = []
        var argumentStart = start
        var depth = 0
        var inString = false
        var escaped = false
        for index in start..<units.count {
            let unit = units[index]
            let scalar = unit < 0x80 ? Unicode.Scalar(UInt8(truncatingIfNeeded: unit)) : Unicode.Scalar(UInt8(0))
            if inString {
                if escaped {
                    escaped = false
                } else if scalar == "\\" {
                    escaped = true
                } else if scalar == "\"" {
                    inString = false
                }
                continue
            }
            switch scalar {
            case "\"":
                inString = true
            case "(", "[", "{":
                depth += 1
            case ")", "]", "}":
                if depth > 0 {
                    depth -= 1
                } else {
                    guard scalar == ")" else { return nil }
                    arguments.append(trimmed(units[argumentStart..<index]))
                    return arguments
                }
            case "," where depth == 0:
                arguments.append(trimmed(units[argumentStart..<index]))
                argumentStart = index + 1
            default:
                break
            }
        }
        return nil
    }

    private static func trimmed(_ units: ArraySlice<UInt16>) -> String {
        String(decoding: units, as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Separates an argument label from its value when the argument has one.
    private static func labeled(_ argument: String) -> (label: String?, value: String) {
        let label = argument.prefix { $0 == "_" || $0.isLetter || $0.isNumber }
        let rest = argument.dropFirst(label.count).drop { $0.isWhitespace }
        guard !label.isEmpty, rest.first == ":" else { return (nil, argument) }
        return (String(label), String(rest.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Returns the contents of a single-line string literal without interpolation, as written.
    private static func literalContents(_ value: String) -> String? {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\""), !value.hasPrefix("\"\"\"")
        else { return nil }
        let contents = value.dropFirst().dropLast()
        var escaped = false
        for character in contents {
            if escaped {
                guard character != "(" else { return nil }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" || character.isNewline {
                return nil
            }
        }
        return escaped ? nil : String(contents)
    }

    static func validatePackage(_ data: Data) throws {
        guard let package = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let targets = package["targets"] as? [[String: Any]]
        else { throw ToolingError.invalidPackageDescription }

        let graph = try targets.reduce(into: [String: Set<String>]()) { graph, target in
            guard let name = target["name"] as? String,
                let dependencies = target["dependencies"] as? [[String: Any]]
            else { throw ToolingError.invalidPackageDescription }
            graph[name] = Set(
                try dependencies.map { dependency in
                    guard
                        let values = ["byName", "target", "product"]
                            .compactMap({ dependency[$0] as? [Any] }).first,
                        let name = values.first as? String
                    else { throw ToolingError.invalidPackageDescription }
                    return name
                }
            )
        }

        for product in productTargets {
            guard graph[product] != nil else { throw ToolingError.invalidPackageDescription }
            var remaining = [product]
            var visited: Set<String> = []
            while let target = remaining.popLast() {
                guard visited.insert(target).inserted else { continue }
                guard !toolingTargets.contains(target) else { throw ToolingError.toolingDependency(target: product) }
                remaining.append(contentsOf: graph[target] ?? [])
            }
        }
        try validateFeatureGraph(graph)
    }

    private static func libraryFence(for target: String) -> [String] {
        switch target {
        case "RookCore":
            [
                "NSPasteboard", "NSWorkspace", "import\\s+RookApp\\b", "import\\s+RookSculpture\\b",
                "import\\s+RookRendering\\b",
            ]
        case "RookSculpture":
            ["import\\s+RookApp\\b", "import\\s+RookCore\\b", "import\\s+RookRendering\\b"]
        case "RookRendering":
            ["import\\s+RookApp\\b", "import\\s+RookCore\\b"]
        default:
            []
        }
    }

    private static func validateFeatureGraph(_ graph: [String: Set<String>]) throws {
        guard graph["RookCore"]?.isEmpty == true else { throw ToolingError.invalidPackageDescription }
        guard let appDependencies = graph["RookApp"],
            Set<String>(["RookCore", "RookSculpture", "RookRendering"]).isSubset(of: appDependencies)
        else { throw ToolingError.invalidPackageDescription }
        guard let sculptureDependencies = graph["RookSculpture"],
            sculptureDependencies.isDisjoint(with: ["RookApp", "RookCore", "RookRendering"])
        else { throw ToolingError.invalidPackageDescription }
        guard let renderingDependencies = graph["RookRendering"],
            renderingDependencies.contains("RookSculpture"),
            renderingDependencies.isDisjoint(with: ["RookApp", "RookCore"])
        else { throw ToolingError.invalidPackageDescription }
    }

    static func validateFileInventory(_ data: Data) throws {
        guard let inventory = String(data: data, encoding: .utf8) else {
            throw ToolingError.invalidFileInventory
        }
        let excludedDirectories: Set<String> = [".git", ".build", ".swiftpm"]
        for path in inventory.split(separator: "\0").map(String.init) {
            let components = path.split(separator: "/").map(String.init)
            guard Set(components).isDisjoint(with: excludedDirectories) else { continue }
            if ["py", "sh", "metal"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) {
                throw ToolingError.nonSwiftProgram(path)
            }
        }
    }
}

enum ReleaseFixture {
    static let markers = ["Development fixture", "rook.development.pro-fixture"]

    static func validate(_ executable: Data) throws {
        for marker in markers where executable.range(of: Data(marker.utf8)) != nil {
            throw ToolingError.releaseMarker(marker)
        }
    }
}
