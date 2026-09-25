import Foundation

public enum ArchiveRepositoryError: Error, Equatable, Sendable {
    case verificationFailed, rollbackFailed
}

/// Central bounded reader: do not trust a size attribute that can change before reading.
public enum ArchiveFileReader {
    public static func read(_ url: URL, maximumBytes: Int = Archive.maximumBytes) throws -> Data {
        guard maximumBytes >= 0, maximumBytes < Int.max else { throw LightPlanError.invalidNumber }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var result = Data()
        while true {
            try Task.checkCancellation()
            let count = min(64 * 1024, maximumBytes - result.count + 1)
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { return result }
            guard chunk.count <= maximumBytes - result.count else { throw LightPlanError.tooManyItems }
            result.append(chunk)
        }
    }
}

// Injectable filesystem boundary, internal to the core. Production uses only local Foundation I/O.
protocol ArchiveStorage: Sendable {
    func read(_ url: URL, bounded: Bool) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func remove(_ url: URL) throws
    func prepare(_ directory: URL) throws
}
struct LocalArchiveStorage: ArchiveStorage {
    func read(_ url: URL, bounded: Bool) throws -> Data {
        try bounded ? ArchiveFileReader.read(url) : Data(contentsOf: url, options: .mappedIfSafe)
    }
    func write(_ data: Data, to url: URL) throws {
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS) || os(visionOS)
        // Apply protection during the write to the live file AND rollback/migration originals.
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: url, options: options)
    }
    func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
    func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

/// Atomic writes with verified read-back and a preserved previous/migration/recovery original.
/// Single-writer ownership is provided by AppState. This is not a multi-process database.
public struct ArchiveRepository: Sendable {
    public let url: URL
    private let storage: any ArchiveStorage
    public init(url: URL) { self.init(url: url, storage: LocalArchiveStorage()) }
    init(url: URL, storage: any ArchiveStorage) { self.url = url; self.storage = storage }

    private func missing(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSCocoaErrorDomain &&
                [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)) ||
               (error.domain == NSPOSIXErrorDomain && error.code == 2)
    }
    private func bytesIfPresent(bounded: Bool) throws -> Data? {
        do { return try storage.read(url, bounded: bounded) }
        catch { if missing(error) { return nil }; throw error }
    }
    public func load() throws -> Archive {
        // Permission/protection errors are not an empty library.
        guard let data = try bytesIfPresent(bounded: true) else { return Archive(places: [], plans: []) }
        return try Archive.decode(data)
    }
    @discardableResult public func write(_ archive: Archive, allowRecovery: Bool = false) throws -> Archive {
        let data = try archive.encoded()
        let verified = try Archive.decode(data)
        try storage.prepare(url.deletingLastPathComponent())
        // Raw originals may be corrupt. They are copied without decoding during explicit recovery.
        let old = try bytesIfPresent(bounded: !allowRecovery)
        if let old {
            if !allowRecovery { _ = try Archive.decode(old) }
            if let legacy = try? Archive.decode(old), legacy.schemaVersion < Archive.currentSchemaVersion {
                try storage.write(old, to: url.deletingLastPathComponent()
                    .appendingPathComponent("archive-schema-\(legacy.schemaVersion)-\(UUID().uuidString).json"))
            }
            let name = allowRecovery ? "recovered-\(UUID().uuidString).json" : "archive-previous.json"
            try storage.write(old, to: url.deletingLastPathComponent().appendingPathComponent(name))
        }
        do {
            try storage.write(data, to: url)
            guard try storage.read(url, bounded: true) == data else { throw ArchiveRepositoryError.verificationFailed }
            return verified
        } catch {
            let failure = error
            do {
                if let old {
                    try storage.write(old, to: url)
                    guard try storage.read(url, bounded: false) == old else { throw ArchiveRepositoryError.rollbackFailed }
                } else {
                    do { try storage.remove(url) } catch { if !missing(error) { throw error } }
                }
            } catch { throw ArchiveRepositoryError.rollbackFailed }
            throw failure
        }
    }
    /// Explicit raw export must not decode, normalize or silently repair a damaged archive.
    public func originalBytes() throws -> Data { try storage.read(url, bounded: false) }
}
