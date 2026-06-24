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
    guard let path = arguments.first else {
        fputs("usage: threemd validate <file>\n", stderr)
        exit(1)
    }
    let source = readFile(at: path)
    let parser = Parser()
    do {
        _ = try parser.parse(source)
        print("ok")
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

/// Prints version, axis, title, plane count, and each plane's z and label.
private func runInfo(arguments: [String]) {
    guard let path = arguments.first else {
        fputs("usage: threemd info <file>\n", stderr)
        exit(1)
    }
    let source = readFile(at: path)
    let parser = Parser()
    let document: Document
    do {
        document = try parser.parse(source)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }

    print("version: \(document.version)")
    print("axis:    \(document.axis.rawValue)")
    print("title:   \(document.title ?? "(none)")")
    print("planes:  \(document.planes.count)")

    for plane in document.planes {
        let label = plane.label.map { " label=\($0)" } ?? ""
        print("  z=\(formatZ(plane.z))\(label)")
    }
}

/// Renders the document to HTML and prints it to stdout.
private func runHTML(arguments: [String]) {
    guard let path = arguments.first else {
        fputs("usage: threemd html <file>\n", stderr)
        exit(1)
    }
    let source = readFile(at: path)
    let parser = Parser()
    let document: Document
    do {
        document = try parser.parse(source)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }

    print(HTMLRenderer().render(document), terminator: "")
}


// MARK: - Helpers

/// Reads the file at the given path, exiting on failure.
private func readFile(at path: String) -> String {
    let url = URL(fileURLWithPath: path)
    guard let source = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("threemd: cannot read file '\(path)'\n", stderr)
        exit(1)
    }
    return source
}

/// Formats a `Double` z position using integer form when the value is whole.
private func formatZ(_ value: Double) -> String {
    guard value == value.rounded(), abs(value) < 1e15 else { return String(value) }
    return String(Int(value))
}

/// Prints usage information to stdout.
private func printUsage() {
    print(
        """
        Usage: threemd <subcommand> <file>

        Subcommands:
          validate <file>   Parse a .3md file; exit non-zero and print error on failure, else print "ok".
          info <file>       Print version, axis, title, plane count, and each plane's z and label.
          html <file>       Render the document to HTML and print to stdout.
        """
    )
}
