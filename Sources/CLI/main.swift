import Foundation
import ThreeMD

// MARK: - Entry Point

let arguments = CommandLine.arguments.dropFirst()

guard let subcommand = arguments.first else {
    printUsage()
    exit(1)
}

let remainingArguments = Array(arguments.dropFirst())

switch subcommand {
case "validate":
    runValidate(arguments: remainingArguments)
case "info":
    runInfo(arguments: remainingArguments)
case "html":
    runHTML(arguments: remainingArguments)
case "links":
    runLinks(arguments: remainingArguments)
case "check-links":
    runCheckLinks(arguments: remainingArguments)
case "--help", "-h", "help":
    printUsage()
    exit(0)
default:
    fputs("threemd: unknown subcommand '\(subcommand)'\n", stderr)
    printUsage()
    exit(1)
}


// MARK: - Subcommands

/// Parses a file and exits non-zero with the error on failure, or prints "ok".
private func runValidate(arguments: [String]) {
    let fileArguments = parseFileArguments(arguments, usage: "usage: threemd validate [--json] <file>")
    let source = readFile(at: fileArguments.path)
    let parser = Parser()
    do {
        _ = try parser.parse(source)
        if fileArguments.json {
            printJSON(ValidateOutput(ok: true, error: nil))
        } else {
            print("ok")
        }
    } catch {
        if fileArguments.json {
            printJSON(ValidateOutput(ok: false, error: ErrorOutput(error)))
        } else {
            fputs("\(error.localizedDescription)\n", stderr)
        }
        exit(1)
    }
}

/// Prints version, axis, title, plane count, and each plane's z and label.
private func runInfo(arguments: [String]) {
    let fileArguments = parseFileArguments(arguments, usage: "usage: threemd info [--json] <file>")
    let document = parseDocument(at: fileArguments.path, json: fileArguments.json)

    if fileArguments.json {
        printJSON(
            InfoOutput(
                document: document,
                planeCount: document.planes.count,
                linkCount: document.links().count,
                danglingLinkCount: document.danglingLinks().count,
                graph: document.linkGraph()
            )
        )
        return
    }

    print("version: \(document.version)")
    print("axis:    \(document.axis.rawValue)")
    print("title:   \(document.title ?? "(none)")")
    print("planes:  \(document.planes.count)")

    for plane in document.planes {
        var parts = ["z=\(formatZ(plane.z))"]
        if let label = plane.label { parts.append("label=\(label)") }
        if let x = plane.x { parts.append("x=\(formatZ(x))") }
        if let y = plane.y { parts.append("y=\(formatZ(y))") }
        for key in plane.attributes.keys.sorted() {
            if let value = plane.attributes[key] { parts.append("\(key)=\(value)") }
        }
        print("  " + parts.joined(separator: " "))
    }
}

/// Prints extracted cross-plane links and a compact graph summary.
private func runLinks(arguments: [String]) {
    let fileArguments = parseFileArguments(arguments, usage: "usage: threemd links [--json] <file>")
    let document = parseDocument(at: fileArguments.path, json: fileArguments.json)
    let links = document.links()
    let danglingLinks = links.filter { !$0.targetExists }
    let graph = document.linkGraph()

    if fileArguments.json {
        printJSON(LinksOutput(ok: danglingLinks.isEmpty, links: links, danglingLinks: danglingLinks, graph: graph))
        return
    }

    print("links: \(links.count)")
    print("dangling: \(danglingLinks.count)")
    for link in links {
        print(linkLine(link))
    }
}

/// Validates that all cross-plane links resolve to existing planes.
private func runCheckLinks(arguments: [String]) {
    let fileArguments = parseFileArguments(arguments, usage: "usage: threemd check-links [--json] <file>")
    let document = parseDocument(at: fileArguments.path, json: fileArguments.json)
    let links = document.links()
    let danglingLinks = document.danglingLinks()
    let graph = document.linkGraph()

    if fileArguments.json {
        printJSON(LinksOutput(ok: danglingLinks.isEmpty, links: links, danglingLinks: danglingLinks, graph: graph))
    } else if danglingLinks.isEmpty {
        print("ok")
    } else {
        fputs("dangling links: \(danglingLinks.count)\n", stderr)
        for link in danglingLinks {
            fputs(linkLine(link) + "\n", stderr)
        }
    }

    if !danglingLinks.isEmpty {
        exit(1)
    }
}

/// Renders the document to HTML and prints it to stdout.
private func runHTML(arguments: [String]) {
    let fileArguments = parseFileArguments(arguments, usage: "usage: threemd html <file>")
    let document = parseDocument(at: fileArguments.path, json: false)
    print(HTMLRenderer().render(document), terminator: "")
}


// MARK: - Helpers

/// Parsed common file command arguments.
private struct FileArguments {
    /// File path to read, or `-` for standard input.
    let path: String
    /// Whether the command should print JSON.
    let json: Bool
}

/// JSON payload for validation.
private struct ValidateOutput: Encodable {
    /// Whether parsing succeeded.
    let ok: Bool
    /// Error details when parsing failed.
    let error: ErrorOutput?
}

/// JSON payload for `info`.
private struct InfoOutput: Encodable {
    /// The parsed document.
    let document: Document
    /// Number of planes.
    let planeCount: Int
    /// Number of cross-plane links.
    let linkCount: Int
    /// Number of dangling cross-plane links.
    let danglingLinkCount: Int
    /// Compact cross-plane link graph.
    let graph: [CrossPlaneLinkEdge]
}

/// JSON payload for link inspection commands.
private struct LinksOutput: Encodable {
    /// Whether all links resolve.
    let ok: Bool
    /// All extracted links.
    let links: [CrossPlaneLink]
    /// Links whose target plane does not exist.
    let danglingLinks: [CrossPlaneLink]
    /// Compact cross-plane link graph.
    let graph: [CrossPlaneLinkEdge]
}

/// JSON-friendly error details.
private struct ErrorOutput: Encodable {
    /// Stable machine-readable error code.
    let code: String
    /// Human-readable message.
    let message: String
    /// 1-based source line when available.
    let line: Int?
    /// Case-specific detail when available.
    let detail: String?

    /// Creates error output from a thrown error.
    /// - Parameter error: The error to describe.
    init(_ error: Error) {
        if let parseError = error as? ParseError {
            self.code = parseError.code
            self.message = parseError.localizedDescription
            self.line = parseError.line
            self.detail = parseError.detail
        } else {
            self.code = "error"
            self.message = error.localizedDescription
            self.line = nil
            self.detail = nil
        }
    }
}

/// Parses common `[--json] <file>` arguments.
private func parseFileArguments(_ arguments: [String], usage: String) -> FileArguments {
    var json = false
    var paths: [String] = []

    for argument in arguments {
        if argument == "--json" {
            json = true
        } else {
            paths.append(argument)
        }
    }

    guard paths.count == 1, let path = paths.first else {
        fputs("\(usage)\n", stderr)
        exit(1)
    }

    return FileArguments(path: path, json: json)
}

/// Parses a 3md document from a path, exiting with an error on failure.
private func parseDocument(at path: String, json: Bool) -> Document {
    let source = readFile(at: path)
    let parser = Parser()
    do {
        return try parser.parse(source)
    } catch {
        if json {
            printJSON(ValidateOutput(ok: false, error: ErrorOutput(error)))
        } else {
            fputs("\(error.localizedDescription)\n", stderr)
        }
        exit(1)
    }
}

/// Reads the file at the given path, exiting on failure. A path of `-` reads
/// from standard input. Missing files and non-UTF-8 content give distinct errors.
private func readFile(at path: String) -> String {
    if path == "-" {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
    guard FileManager.default.fileExists(atPath: path) else {
        fputs("threemd: file not found: '\(path)'\n", stderr)
        exit(1)
    }
    guard let source = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
        fputs("threemd: cannot read '\(path)' (is it valid UTF-8?)\n", stderr)
        exit(1)
    }
    return source
}

/// Formats a `Double` z position using integer form when the value is whole.
private func formatZ(_ value: Double) -> String {
    guard value == value.rounded(), abs(value) < 1e15 else { return String(value) }
    return String(Int(value))
}

/// Formats one cross-plane link for human-readable CLI output.
private func linkLine(_ link: CrossPlaneLink) -> String {
    var parts = [
        "source=\(formatZ(link.sourceZ))",
        "target=\(formatZ(link.targetZ))",
        "status=\(link.targetExists ? "ok" : "dangling")",
    ]
    if let text = link.text {
        parts.append("text=\(text)")
    }
    return "  " + parts.joined(separator: " ")
}

/// Prints an encodable payload as pretty, sorted JSON.
private func printJSON<Payload: Encodable>(_ payload: Payload) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        let data = try encoder.encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            fputs("threemd: failed to encode JSON as UTF-8\n", stderr)
            exit(1)
        }
        print(string)
    } catch {
        fputs("threemd: failed to encode JSON: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

/// Prints usage information to stdout.
private func printUsage() {
    print(
        """
        Usage: threemd <subcommand> <file>

        A file of '-' reads from standard input.

        Subcommands:
          validate [--json] <file>    Parse a .3md file; exit non-zero and print error on failure, else print "ok".
          info [--json] <file>        Print document metadata, plane count, and each plane's attributes.
          links [--json] <file>       Print cross-plane links and graph edges.
          check-links [--json] <file> Exit non-zero when any cross-plane link is dangling.
          html <file>                 Render the document to HTML and print to stdout.
        """
    )
}
