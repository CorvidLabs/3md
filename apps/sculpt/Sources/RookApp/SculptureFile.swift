import RookSculpture
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let sculpture = UTType(exportedAs: "labs.corvid.rook.sculpture", conformingTo: .plainText)
    static let compactSculpture = UTType(exportedAs: "labs.corvid.rook.compact-sculpture", conformingTo: .data)
    static let sculptureMesh = UTType(filenameExtension: "obj") ?? .data
}

internal struct SculptureFile: FileDocument {
    static let readableContentTypes: [UTType] = [.sculpture, .compactSculpture, .plainText]
    var sculpture: Sculpture

    init(_ sculpture: Sculpture) { self.sculpture = sculpture }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw SculptureError.invalidGrid }
        sculpture = try SculptureDocumentCodec.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let format: SculptureStorageFormat = configuration.contentType == .compactSculpture ? .compact : .readable
        return FileWrapper(regularFileWithContents: try SculptureDocumentCodec.encode(sculpture, format: format))
    }
}

internal struct SculptureExport: FileDocument {
    static let readableContentTypes: [UTType] = [
        .sculpture, .compactSculpture, .png, .plainText, .gif, .mpeg4Movie, .sculptureMesh,
    ]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
