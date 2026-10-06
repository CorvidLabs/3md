import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

let manager = FileManager.default
let repository = URL(fileURLWithPath: "/private/tmp/3md-composition-intake-20261005")
let fixture = URL(fileURLWithPath: "/private/tmp/3md-linked-host-probe-" + UUID().uuidString)
try manager.createDirectory(at: fixture, withIntermediateDirectories: true)
let project = fixture.appendingPathComponent("project")
try manager.copyItem(at: repository.appendingPathComponent("Examples/LinkedVillage"), to: project)
let executable = repository.appendingPathComponent(".build/debug/threemd-interchange")

func run(_ name: String, root: String = "scene.3md", folder: URL = project, output: URL, success: Bool) throws {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = executable
    process.arguments = ["--bundle", root, "--folder", folder.path, "--output", output.path]
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let response = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard (process.terminationStatus == 0) == success else {
        throw NSError(domain: name, code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(decoding: response, as: UTF8.self)])
    }
    print("PASS \(name), exit \(process.terminationStatus): \(String(decoding: response, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))")
}

let textOutput = fixture.appendingPathComponent("portable.3md")
try run("text bundle", output: textOutput, success: true)
try run("binary bundle", output: fixture.appendingPathComponent("portable.3mdb"), success: true)
let original = try Data(contentsOf: textOutput)
try run("refuse existing output", output: textOutput, success: false)
guard try Data(contentsOf: textOutput) == original else { throw NSError(domain: "output changed", code: 1) }
try run("root directory", root: project.appendingPathComponent("scene.3md").path.dropFirst().description, folder: URL(fileURLWithPath: "/"), output: fixture.appendingPathComponent("from-root.3md"), success: true)

let outside = fixture.appendingPathComponent("outside.3md")
try Data("---\n3md: 1.0\naxis: space\n---\n\n@plane z=0\noutside\n".utf8).write(to: outside)
let rootURL = project.appendingPathComponent("scene.3md")
let rootBytes = try Data(contentsOf: rootURL)
try manager.removeItem(at: rootURL)
try manager.createSymbolicLink(at: rootURL, withDestinationURL: outside)
try run("refuse source symlink", output: fixture.appendingPathComponent("symlink.3md"), success: false)
try manager.removeItem(at: rootURL)
guard mkfifo(rootURL.path, 0o600) == 0 else { throw NSError(domain: "mkfifo", code: Int(errno)) }
try run("refuse FIFO without blocking", output: fixture.appendingPathComponent("fifo.3md"), success: false)
try manager.removeItem(at: rootURL)
try rootBytes.write(to: rootURL)

let existingDirectory = fixture.appendingPathComponent("existing.3md")
try manager.createDirectory(at: existingDirectory, withIntermediateDirectories: false)
let marker = existingDirectory.appendingPathComponent("keep")
try Data("preserve".utf8).write(to: marker)
try run("refuse output directory", output: existingDirectory, success: false)
guard try Data(contentsOf: marker) == Data("preserve".utf8) else { throw NSError(domain: "marker changed", code: 1) }
let outputLink = fixture.appendingPathComponent("existing-link.3md")
try manager.createSymbolicLink(at: outputLink, withDestinationURL: outside)
let outsideBytes = try Data(contentsOf: outside)
try run("refuse output symlink", output: outputLink, success: false)
guard try Data(contentsOf: outside) == outsideBytes else { throw NSError(domain: "outside changed", code: 1) }
print("Artifacts retained: \(fixture.path)")
