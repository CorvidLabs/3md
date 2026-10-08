import Compression
import CryptoKit
import Darwin
import Foundation

/// A release-only development experiment. Its raw LZFSE payload is not a Sculpt or ThreeMD file.
internal enum SculptureVolumeStudy {
    static let denseEdge = 1_024
    static let denseBytes = 1_073_741_824
    static let chunkBytes = 1_048_576
    static let reserveBytes: UInt64 = 512 * 1_024 * 1_024
    private static let endMarker = Data([0x62, 0x76, 0x78, 0x24])

    static func run(arguments: [String], workingDirectory: URL) throws -> Data {
        let output = try outputDirectory(arguments)
        #if DEBUG
        throw StudyError.releaseRequired
        #else
        _ = workingDirectory
        let receipt = try measure(edge: denseEdge, output: output)
        return try json(receipt)
        #endif
    }

    static func outputDirectory(_ arguments: [String]) throws -> URL {
        guard arguments.count == 3, arguments[0] == "--output", arguments[1].hasPrefix("/"),
            !arguments[1].utf8.contains(0), arguments[2] == "--dense-1024"
        else { throw StudyError.usage }
        let output = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
        guard output.path != "/" else { throw StudyError.usage }
        return output
    }

    /// The reduced-size seam exercises the identical buffers, codec and guards without a GiB CI allocation.
    static func measure(
        edge: Int,
        output: URL,
        minimumFreeReserveBytes: UInt64 = reserveBytes,
        memory: () -> MemorySample = memorySnapshot,
        progress: @Sendable (String) -> Void = stderrProgress
    ) throws -> Receipt {
        try Task.checkCancellation()
        guard (1...denseEdge).contains(edge) else { throw StudyError.invalidSize }
        #if DEBUG
        guard edge <= 64 else { throw StudyError.releaseRequired }
        #endif
        let byteCount = edge * edge * edge
        let beforeGuard = memory()
        try guardResources(payloadBytes: byteCount, reserve: minimumFreeReserveBytes, memory: beforeGuard)
        let directory = try StudyDirectory(output: output)
        var allocation: UnsafeMutableRawPointer?
        defer { if let allocation { free(allocation) } }
        var phases: [Phase] = []
        allocation = try phase("allocate", phases: &phases, memory: memory, progress: progress) {
            try Task.checkCancellation()
            guard let buffer = malloc(byteCount) else { throw StudyError.allocationFailed }
            return buffer
        }
        guard let buffer = allocation else { throw StudyError.allocationFailed }
        try phase("fill", phases: &phases, memory: memory, progress: progress) {
            try initialize(buffer, edge: edge, byteCount: byteCount)
        }
        let rawSHA = try phase("hash", phases: &phases, memory: memory, progress: progress) {
            try hash(buffer, byteCount: byteCount)
        }
        let artifactName = "dense-\(edge).voxels.lzfse"
        let encoded = try phase("encode", phases: &phases, memory: memory, progress: progress) {
            let file = try directory.createFile(artifactName)
            defer { try? file.close() }
            return try encode(buffer, byteCount: byteCount, file: file)
        }
        let decoded = try phase("decode-verify", phases: &phases, memory: memory, progress: progress) {
            let file = try directory.readFile(artifactName)
            defer { try? file.close() }
            return try verify(file, expected: buffer, byteCount: byteCount, encoded: encoded)
        }
        guard decoded.bytes == byteCount, decoded.sha256 == rawSHA else { throw StudyError.rawDigestMismatch }
        try phase("release", phases: &phases, memory: memory, progress: progress) {
            free(buffer)
            allocation = nil
        }
        let receipt = Receipt(
            edge: edge,
            rawBytes: byteCount,
            initializedBytes: byteCount,
            decodedBytes: decoded.bytes,
            rawSHA256: rawSHA,
            decodedSHA256: decoded.sha256,
            artifact: artifactName,
            encodedBytes: encoded.bytes,
            encodedSHA256: encoded.sha256,
            decoderReadBufferBytes: decoded.readBufferBytes,
            decoderReadCalls: decoded.readCalls,
            decoderMaximumReadBytes: decoded.maximumReadBytes,
            minimumFreeReserveBytes: minimumFreeReserveBytes,
            memoryBeforeGuard: beforeGuard,
            environment: environment(),
            phases: phases
        )
        try Task.checkCancellation()
        let receiptFile = try directory.createFile("receipt.json")
        defer { try? receiptFile.close() }
        try receiptFile.write(contentsOf: json(receipt))
        try receiptFile.synchronize()
        try receiptFile.close()
        try Task.checkCancellation()
        try directory.publish()
        progress("complete: \(byteCount) initialized, hashed and verified bytes; \(encoded.bytes) LZFSE bytes")
        return receipt
    }

    static func guardResources(payloadBytes: Int, reserve: UInt64, memory: MemorySample) throws {
        guard payloadBytes > 0 else { throw StudyError.invalidSize }
        let (required, overflow) = UInt64(payloadBytes).addingReportingOverflow(reserve)
        guard !overflow else { throw StudyError.invalidSize }
        guard let freeBytes = memory.systemFreeBytes else { throw StudyError.memoryUnavailable }
        guard freeBytes >= required else { throw StudyError.insufficientMemory(required, freeBytes) }
        if let processRemaining = memory.processLimitRemainingBytes, processRemaining < required {
            throw StudyError.insufficientProcessMemory(required, processRemaining)
        }
    }

    /// All IO stays relative to opened directories. Cleanup removes only entries with recorded identities.
    private final class StudyDirectory {
        private let parentDescriptor: Int32
        private let descriptor: Int32
        private let parent: URL
        private let parentIdentity: FileIdentity
        private let stagingName: String
        private let outputName: String
        private let identity: FileIdentity
        private var files: [String: FileIdentity] = [:]
        private var published = false

        init(output: URL) throws {
            let parent = output.deletingLastPathComponent().resolvingSymlinksInPath()
            let parentDescriptor = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard parentDescriptor >= 0 else { throw StudyError.outputParentRequired }
            var stagingDescriptor: Int32 = -1
            var stagingIdentity: FileIdentity?
            let stagingName = ".volume-study-\(UUID()).tmp"
            do {
                var parentInformation = stat()
                guard fstat(parentDescriptor, &parentInformation) == 0 else { throw StudyError.outputParentRequired }
                let outputName = output.lastPathComponent
                guard !outputName.isEmpty, outputName != ".", outputName != "..",
                    !outputName.utf8.contains(0), !outputName.contains("/")
                else { throw StudyError.usage }
                var existing = stat()
                if fstatat(parentDescriptor, outputName, &existing, AT_SYMLINK_NOFOLLOW) == 0 {
                    throw StudyError.outputExists
                }
                guard errno == ENOENT else { throw StudyError.fileIO(String(cString: strerror(errno))) }
                guard mkdirat(parentDescriptor, stagingName, mode_t(0o700)) == 0 else {
                    throw StudyError.fileIO(String(cString: strerror(errno)))
                }
                var created = stat()
                guard fstatat(parentDescriptor, stagingName, &created, AT_SYMLINK_NOFOLLOW) == 0,
                    created.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
                else { throw StudyError.stagingChanged }
                stagingIdentity = FileIdentity(created)
                stagingDescriptor = openat(
                    parentDescriptor,
                    stagingName,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
                var opened = stat()
                guard stagingDescriptor >= 0, fstat(stagingDescriptor, &opened) == 0,
                    FileIdentity(opened) == stagingIdentity
                else { throw StudyError.stagingChanged }
                self.parentDescriptor = parentDescriptor
                descriptor = stagingDescriptor
                self.parent = parent
                parentIdentity = FileIdentity(parentInformation)
                self.stagingName = stagingName
                self.outputName = outputName
                identity = FileIdentity(opened)
            } catch {
                if let stagingIdentity, Self.matches(parentDescriptor, name: stagingName, identity: stagingIdentity) {
                    _ = unlinkat(parentDescriptor, stagingName, AT_REMOVEDIR)
                }
                if stagingDescriptor >= 0 { Darwin.close(stagingDescriptor) }
                Darwin.close(parentDescriptor)
                throw error
            }
        }

        func createFile(_ name: String) throws -> FileHandle {
            try checkIdentity()
            let fileDescriptor = openat(
                descriptor,
                name,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
            guard fileDescriptor >= 0 else { throw StudyError.fileIO(String(cString: strerror(errno))) }
            var information = stat()
            guard fstat(fileDescriptor, &information) == 0 else {
                Darwin.close(fileDescriptor)
                throw StudyError.fileIO(String(cString: strerror(errno)))
            }
            files[name] = FileIdentity(information)
            return FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
        }

        func readFile(_ name: String) throws -> FileHandle {
            try checkIdentity()
            let fileDescriptor = openat(descriptor, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard fileDescriptor >= 0 else { throw StudyError.fileIO(String(cString: strerror(errno))) }
            var information = stat()
            guard fstat(fileDescriptor, &information) == 0, FileIdentity(information) == files[name] else {
                Darwin.close(fileDescriptor)
                throw StudyError.stagingChanged
            }
            return FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
        }

        func publish() throws {
            try checkIdentity()
            for (name, identity) in files {
                guard Self.matches(descriptor, name: name, identity: identity) else { throw StudyError.stagingChanged }
            }
            // An existing or racing destination, including a symbolic link, is never replaced.
            guard renameatx_np(parentDescriptor, stagingName, parentDescriptor, outputName, UInt32(RENAME_EXCL)) == 0
            else { throw StudyError.publicationFailed(String(cString: strerror(errno))) }
            published = true
        }

        private func checkIdentity() throws {
            var information = stat()
            guard stat(parent.path, &information) == 0, FileIdentity(information) == parentIdentity,
                Self.matches(parentDescriptor, name: stagingName, identity: identity)
            else { throw StudyError.stagingChanged }
        }

        private static func matches(_ directory: Int32, name: String, identity: FileIdentity) -> Bool {
            var information = stat()
            return fstatat(directory, name, &information, AT_SYMLINK_NOFOLLOW) == 0
                && FileIdentity(information) == identity
        }

        deinit {
            if !published {
                for (name, identity) in files where Self.matches(descriptor, name: name, identity: identity) {
                    _ = unlinkat(descriptor, name, 0)
                }
                if Self.matches(parentDescriptor, name: stagingName, identity: identity) {
                    _ = unlinkat(parentDescriptor, stagingName, AT_REMOVEDIR)
                }
            }
            Darwin.close(descriptor)
            Darwin.close(parentDescriptor)
        }
    }

    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let kind: mode_t
        init(_ information: stat) {
            device = information.st_dev
            inode = information.st_ino
            kind = information.st_mode & mode_t(S_IFMT)
        }
    }

    private static func initialize(_ buffer: UnsafeMutableRawPointer, edge: Int, byteCount: Int) throws {
        var offset = 0
        var checkpoint = 0
        while offset < byteCount {
            if offset >= checkpoint {
                try Task.checkCancellation()
                checkpoint = offset + 65_536
            }
            let x = offset % edge
            let y = (offset / edge) % edge
            let z = offset / (edge * edge)
            let value = 1 + ((x / 32) * 17 + (y / 32) * 31 + (z / 32) * 47) % 254
            let length = min(32 - x % 32, edge - x, byteCount - offset)
            // Every byte receives a nonzero store. This is neither an untouched reservation nor shared zero pages.
            memset(buffer.advanced(by: offset), Int32(value), length)
            offset += length
        }
        try Task.checkCancellation()
    }

    private static func hash(_ buffer: UnsafeRawPointer, byteCount: Int) throws -> String {
        var hash = SHA256()
        var offset = 0
        while offset < byteCount {
            try Task.checkCancellation()
            let length = min(chunkBytes, byteCount - offset)
            hash.update(bufferPointer: UnsafeRawBufferPointer(start: buffer.advanced(by: offset), count: length))
            offset += length
        }
        return hex(hash.finalize())
    }

    static func encode(_ input: UnsafeRawPointer, byteCount: Int, output: URL) throws -> Encoded {
        try Task.checkCancellation()
        guard (1...denseBytes).contains(byteCount) else { throw StudyError.invalidSize }
        let descriptor = Darwin.open(output.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw StudyError.fileIO(String(cString: strerror(errno))) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        return try encode(input, byteCount: byteCount, file: file)
    }

    private static func encode(_ input: UnsafeRawPointer, byteCount: Int, file: FileHandle) throws -> Encoded {
        try Task.checkCancellation()
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkBytes)
        defer { destination.deallocate() }
        var stream = compression_stream(
            dst_ptr: destination,
            dst_size: 0,
            src_ptr: input.assumingMemoryBound(to: UInt8.self),
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_LZFSE) == COMPRESSION_STATUS_OK
        else {
            throw StudyError.compressionFailed
        }
        defer { compression_stream_destroy(&stream) }
        var provided = 0
        var written = 0
        var fileHash = SHA256()
        let maximumOutput = byteCount + byteCount / 16 + chunkBytes
        while true {
            try Task.checkCancellation()
            if stream.src_size == 0, provided < byteCount {
                let length = min(chunkBytes, byteCount - provided)
                stream.src_ptr = input.advanced(by: provided).assumingMemoryBound(to: UInt8.self)
                stream.src_size = length
                provided += length
            }
            stream.dst_ptr = destination
            stream.dst_size = chunkBytes
            let previous = stream.src_size
            let status = compression_stream_process(
                &stream,
                provided == byteCount ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            )
            let produced = chunkBytes - stream.dst_size
            guard produced <= maximumOutput - written else { throw StudyError.encodedLimit }
            if produced > 0 {
                let bytes = UnsafeRawBufferPointer(start: destination, count: produced)
                fileHash.update(bufferPointer: bytes)
                try file.write(contentsOf: Data(bytes))
                written += produced
            }
            switch status {
            case COMPRESSION_STATUS_END:
                guard provided == byteCount, stream.src_size == 0, written > endMarker.count else {
                    throw StudyError.compressionFailed
                }
                try Task.checkCancellation()
                try file.synchronize()
                return Encoded(bytes: written, sha256: hex(fileHash.finalize()))
            case COMPRESSION_STATUS_OK:
                guard produced > 0 || stream.src_size < previous else { throw StudyError.compressionFailed }
            default: throw StudyError.compressionFailed
            }
        }
    }

    /// Reads only fixed-size chunks; each decoded byte is compared with the still-live original dense buffer.
    static func verify(_ input: URL, expected: UnsafeRawPointer, byteCount: Int, encoded: Encoded) throws -> Decoded {
        try Task.checkCancellation()
        guard (1...denseBytes).contains(byteCount) else { throw StudyError.invalidSize }
        let descriptor = Darwin.open(input.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw StudyError.fileIO(String(cString: strerror(errno))) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        return try verify(file, expected: expected, byteCount: byteCount, encoded: encoded)
    }

    private static func verify(
        _ file: FileHandle,
        expected: UnsafeRawPointer,
        byteCount: Int,
        encoded: Encoded
    ) throws -> Decoded {
        try Task.checkCancellation()
        var information = stat()
        guard fstat(file.fileDescriptor, &information) == 0, information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
            information.st_size == encoded.bytes, encoded.bytes > endMarker.count
        else { throw StudyError.corruptPayload }
        let reader = ReadBuffer(descriptor: file.fileDescriptor)
        try reader.seek(encoded.bytes - endMarker.count)
        let tailCount = try reader.read(upToCount: endMarker.count)
        guard reader.isEndMarker(count: tailCount) else { throw StudyError.corruptPayload }
        try reader.seek(0)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkBytes)
        defer { destination.deallocate() }
        var stream = compression_stream(
            dst_ptr: destination,
            dst_size: 0,
            src_ptr: UnsafePointer(destination),
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZFSE) == COMPRESSION_STATUS_OK
        else {
            throw StudyError.compressionFailed
        }
        defer { compression_stream_destroy(&stream) }
        var count = 0
        var rawHash = SHA256()
        var fileHash = SHA256()
        var remainingPrefix = encoded.bytes - endMarker.count
        var ended = false
        func consume(_ inputCount: Int, final: Bool) throws {
            fileHash.update(bufferPointer: UnsafeRawBufferPointer(start: reader.bytes, count: inputCount))
            stream.src_ptr = UnsafePointer(reader.bytes)
            stream.src_size = inputCount
            while true {
                try Task.checkCancellation()
                stream.dst_ptr = destination
                stream.dst_size = chunkBytes
                let previous = stream.src_size
                let status = compression_stream_process(
                    &stream,
                    final ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
                )
                let produced = chunkBytes - stream.dst_size
                guard produced <= byteCount - count else { throw StudyError.decodedLength }
                if produced > 0 {
                    guard memcmp(destination, expected.advanced(by: count), produced) == 0 else {
                        throw StudyError.rawBytesMismatch
                    }
                    rawHash.update(bufferPointer: UnsafeRawBufferPointer(start: destination, count: produced))
                    count += produced
                }
                switch status {
                case COMPRESSION_STATUS_END:
                    guard final, remainingPrefix == 0, stream.src_size == 0 else { throw StudyError.trailingStream }
                    ended = true
                    return
                case COMPRESSION_STATUS_OK:
                    // Drain read-ahead output before the withheld final marker. END in the prefix rejects concatenation.
                    if stream.src_size == 0, produced == 0, !final { return }
                    guard produced > 0 || stream.src_size < previous else { throw StudyError.corruptPayload }
                default: throw StudyError.corruptPayload
                }
            }
        }
        while remainingPrefix > 0 {
            try Task.checkCancellation()
            let readCount = try reader.read(upToCount: min(chunkBytes, remainingPrefix))
            guard readCount > 0 else { throw StudyError.corruptPayload }
            remainingPrefix -= readCount
            try consume(readCount, final: false)
        }
        let finalCount = try reader.read(upToCount: endMarker.count)
        guard reader.isEndMarker(count: finalCount) else { throw StudyError.corruptPayload }
        try consume(finalCount, final: true)
        guard ended, count == byteCount else { throw StudyError.decodedLength }
        guard try reader.read(upToCount: 1) == 0 else { throw StudyError.trailingStream }
        guard hex(fileHash.finalize()) == encoded.sha256 else { throw StudyError.encodedDigestMismatch }
        try Task.checkCancellation()
        return Decoded(
            bytes: count,
            sha256: hex(rawHash.finalize()),
            readBufferBytes: chunkBytes,
            readCalls: reader.readCalls,
            maximumReadBytes: reader.maximumReadBytes
        )
    }

    /// One reusable POSIX read allocation avoids Foundation's autoreleased NSData chunk lifetime.
    /// The compression stream consumes each chunk fully before this buffer is overwritten.
    private final class ReadBuffer {
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkBytes)
        private let descriptor: Int32
        private(set) var readCalls = 0
        private(set) var maximumReadBytes = 0

        init(descriptor: Int32) { self.descriptor = descriptor }
        deinit { bytes.deallocate() }

        func seek(_ offset: Int) throws {
            guard lseek(descriptor, off_t(offset), SEEK_SET) == off_t(offset) else {
                throw StudyError.fileIO(String(cString: strerror(errno)))
            }
        }

        func read(upToCount count: Int) throws -> Int {
            guard (1...chunkBytes).contains(count) else { throw StudyError.invalidSize }
            while true {
                try Task.checkCancellation()
                let readCount = Darwin.read(descriptor, bytes, count)
                if readCount < 0 {
                    if errno == EINTR { continue }
                    throw StudyError.fileIO(String(cString: strerror(errno)))
                }
                readCalls += 1
                maximumReadBytes = max(maximumReadBytes, readCount)
                return readCount
            }
        }

        func isEndMarker(count: Int) -> Bool {
            guard count == endMarker.count else { return false }
            return endMarker.withUnsafeBytes { marker in
                guard let base = marker.baseAddress else { return false }
                return memcmp(bytes, base, count) == 0
            }
        }
    }

    private static func phase<T>(
        _ name: String,
        phases: inout [Phase],
        memory: () -> MemorySample,
        progress: @Sendable (String) -> Void,
        operation: () throws -> T
    ) throws -> T {
        progress("\(name): starting")
        try Task.checkCancellation()
        let before = memory()
        let clock = ContinuousClock()
        let start = clock.now
        let result = try operation()
        let elapsed = start.duration(to: clock.now).components
        let after = memory()
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        phases.append(Phase(name: name, elapsedSeconds: seconds, memoryBefore: before, memoryAfter: after))
        progress("\(name): \(seconds) seconds")
        return result
    }

    static func memorySnapshot() -> MemorySample {
        var task = task_vm_info_data_t()
        let capacity = MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(capacity)
        let result = withUnsafeMutablePointer(to: &task) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        func supported<T>(_ key: KeyPath<task_vm_info_data_t, T>) -> Bool {
            guard result == KERN_SUCCESS, let offset = MemoryLayout<task_vm_info_data_t>.offset(of: key) else {
                return false
            }
            return offset + MemoryLayout<T>.size <= Int(count) * MemoryLayout<integer_t>.size
        }
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var pageSize: vm_size_t = 0
        var statistics = vm_statistics64_data_t()
        let hostCapacity = MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        var hostCount = mach_msg_type_number_t(hostCapacity)
        let pageResult = host_page_size(host, &pageSize)
        let hostResult = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: hostCapacity) {
                host_statistics64(host, HOST_VM_INFO64, $0, &hostCount)
            }
        }
        let systemFree: UInt64? =
            pageResult == KERN_SUCCESS && hostResult == KERN_SUCCESS
            ? UInt64(statistics.free_count) * UInt64(pageSize) : nil
        let limit =
            supported(\.limit_bytes_remaining) && task.limit_bytes_remaining > 0
                && task.limit_bytes_remaining != UInt64.max
            ? task.limit_bytes_remaining : nil
        return MemorySample(
            systemFreeBytes: systemFree,
            residentBytes: supported(\.resident_size) ? task.resident_size : nil,
            residentPeakBytes: supported(\.resident_size_peak) ? task.resident_size_peak : nil,
            physicalFootprintBytes: supported(\.phys_footprint) ? task.phys_footprint : nil,
            physicalFootprintPeakBytes: supported(\.ledger_phys_footprint_peak) && task.ledger_phys_footprint_peak > 0
                ? UInt64(task.ledger_phys_footprint_peak) : nil,
            processLimitRemainingBytes: limit
        )
    }

    private static func environment() -> Environment {
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif
        #if DEBUG
        let optimization = "debug (-Onone), reduced test only"
        #else
        let optimization = "release (-O)"
        #endif
        return Environment(
            os: ProcessInfo.processInfo.operatingSystemVersionString,
            hardwareModel: sysctlString("hw.model"),
            cpu: sysctlString("machdep.cpu.brand_string"),
            architecture: architecture,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            logicalProcessors: ProcessInfo.processInfo.activeProcessorCount,
            expectedCompiler: "Swift 6.3.3",
            compilerVersionSource: "Repository pin; verify the build invocation.",
            optimization: optimization
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, (1...4_096).contains(size) else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func stderrProgress(_ message: String) {
        FileHandle.standardError.write(Data("volume-study \(message)\n".utf8))
    }

    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
    private static func json(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(10)
        return data
    }

    struct Encoded: Sendable { let bytes: Int; let sha256: String }
    struct Decoded: Sendable {
        let bytes: Int
        let sha256: String
        let readBufferBytes: Int
        let readCalls: Int
        let maximumReadBytes: Int
    }
    struct Phase: Codable, Sendable {
        let name: String
        let elapsedSeconds: Double
        let memoryBefore: MemorySample
        let memoryAfter: MemorySample
    }
    struct MemorySample: Codable, Sendable {
        let systemFreeBytes: UInt64?
        let residentBytes: UInt64?
        let residentPeakBytes: UInt64?
        let physicalFootprintBytes: UInt64?
        let physicalFootprintPeakBytes: UInt64?
        let processLimitRemainingBytes: UInt64?

        private enum CodingKeys: String, CodingKey {
            case systemFreeBytes, residentBytes, residentPeakBytes, physicalFootprintBytes
            case physicalFootprintPeakBytes, processLimitRemainingBytes
        }
        func encode(to encoder: any Encoder) throws {
            var fields = encoder.container(keyedBy: CodingKeys.self)
            try fields.encode(systemFreeBytes, forKey: .systemFreeBytes)
            try fields.encode(residentBytes, forKey: .residentBytes)
            try fields.encode(residentPeakBytes, forKey: .residentPeakBytes)
            try fields.encode(physicalFootprintBytes, forKey: .physicalFootprintBytes)
            try fields.encode(physicalFootprintPeakBytes, forKey: .physicalFootprintPeakBytes)
            try fields.encode(processLimitRemainingBytes, forKey: .processLimitRemainingBytes)
        }
    }
    struct Environment: Codable, Sendable {
        let os: String
        let hardwareModel: String?
        let cpu: String?
        let architecture: String
        let physicalMemoryBytes: UInt64
        let logicalProcessors: Int
        let expectedCompiler: String
        let compilerVersionSource: String
        let optimization: String
    }
    struct Receipt: Encodable, Sendable {
        let schema = "sculpt-dense-volume-study-1"
        let experimentalFormat = "Raw byte volume compressed with Apple LZFSE; not a Sculpt or ThreeMD container."
        let pattern = "nonzero-blocks-1: index=x+edge*(y+edge*z); byte=1+((x/32)*17+(y/32)*31+(z/32)*47)%254"
        let memoryMethod =
            "TASK_VM_INFO process counters and HOST_VM_INFO64 free_count*pageSize; speculative pages are already included."
        let limitations = [
            "Free memory is an instantaneous system snapshot, not an allocation guarantee; unavailable process limits are null.",
            "Every byte is stored nonzero, hashed and compared after decode. macOS can compress or swap dirty pages; this does not pin one GiB in RAM.",
            "Kernel resident and physical footprint peaks cover the process lifetime, not only this study; phase snapshots can miss transient peaks.",
            "Release calls free to relinquish buffer ownership. Allocator caching and kernel accounting can retain resident or footprint bytes afterward; this does not establish an immediate one-GiB OS memory reduction.",
            "Encode includes streaming SHA256, file writes and synchronization. Decode includes reads, SHA256 and comparison, not decompression alone.",
            "This probe does not raise production editing limits, create an editable 1024-cubed scene, or establish on-screen FPS.",
        ]
        let edge: Int
        let rawBytes: Int
        let initializedBytes: Int
        let decodedBytes: Int
        let rawSHA256: String
        let decodedSHA256: String
        let artifact: String
        let encodedBytes: Int
        let encodedSHA256: String
        let decoderReadBufferBytes: Int
        let decoderReadCalls: Int
        let decoderMaximumReadBytes: Int
        let minimumFreeReserveBytes: UInt64
        let memoryBeforeGuard: MemorySample
        let environment: Environment
        let phases: [Phase]
    }
    enum StudyError: LocalizedError {
        case usage, releaseRequired, invalidSize, memoryUnavailable, allocationFailed, outputExists,
            outputParentRequired, stagingChanged
        case insufficientMemory(UInt64, UInt64), insufficientProcessMemory(UInt64, UInt64)
        case publicationFailed(String), fileIO(String), compressionFailed, encodedLimit
        case corruptPayload, decodedLength, trailingStream, rawBytesMismatch, encodedDigestMismatch, rawDigestMismatch

        var errorDescription: String? {
            switch self {
            case .usage: "Usage: RookTool volume-study --output /absolute/new-directory --dense-1024"
            case .releaseRequired:
                "The dense 1024-cubed CLI requires a release build. Debug tests are limited to 64-cubed."
            case .invalidSize: "The experimental volume size is invalid."
            case .memoryUnavailable: "Cannot measure free memory; refusing dense allocation."
            case .allocationFailed: "The dense buffer allocation failed."
            case .outputExists: "Choose a new output directory; existing entries are never replaced."
            case .outputParentRequired: "The output directory's parent must already exist."
            case .stagingChanged:
                "The study's staging directory or files changed during preparation; publication was refused."
            case .insufficientMemory(let required, let available):
                "Dense allocation requires \(required) free bytes including reserve; only \(available) system free bytes were measured."
            case .insufficientProcessMemory(let required, let available):
                "Dense allocation requires \(required) bytes including reserve; the kernel reports only \(available) process-limit bytes remaining."
            case .publicationFailed(let message): "Could not publish the new study directory: \(message)"
            case .fileIO(let message): "Could not read or write the experimental payload: \(message)"
            case .compressionFailed: "The streaming LZFSE encoder failed or stopped making progress."
            case .encodedLimit: "The streaming encoder exceeded its output ceiling."
            case .corruptPayload: "The LZFSE payload is corrupt, truncated, or stopped making progress."
            case .decodedLength: "The decoded byte count differs from the exact expected volume size."
            case .trailingStream: "The payload contains trailing bytes or an earlier LZFSE stream."
            case .rawBytesMismatch: "A decoded byte differs from the original dense buffer."
            case .encodedDigestMismatch: "The compressed file SHA256 differs from the encoder's digest."
            case .rawDigestMismatch: "The decoded SHA256 differs from the full dense-buffer digest."
            }
        }
    }
}
