import Foundation
import CryptoKit

/// Coordinates reversible filesystem changes with the catalogue. Never overwrites a recovery path.
enum SafeMediaFileOperations {
    static func validate(_ url: URL, inside root: URL, allowMissing: Bool = false) throws {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/"), resolved.path != rootPath else {
            throw OperationError.unsafePath(url.path)
        }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw OperationError.unsafePath(url.path)
            }
        } catch let error as CocoaError where allowMissing && error.code == .fileReadNoSuchFile {
            return
        }
    }

    static func rename(from source: URL, to target: URL, commit: () throws -> Void) throws {
        try FileManager.default.moveItem(at: source, to: target)
        do {
            try commit()
        } catch {
            try restore(from: target, to: source, because: error)
        }
    }

    /// `trash` is injectable so tests exercise recovery without touching the user's Trash.
    static func trash(_ source: URL, trash: (URL) throws -> URL = moveToTrash, commit: () throws -> Void) throws {
        let recoveryURL = try trash(source)
        do {
            try commit()
        } catch {
            try restore(from: recoveryURL, to: source, because: error)
        }
    }

    private static func moveToTrash(_ source: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: source, resultingItemURL: &result)
        guard let result else { throw OperationError.recoveryRequired("System Trash", "The system did not return the recovery location.") }
        return result as URL
    }

    private static func restore(from recovery: URL, to original: URL, because failure: Error) throws {
        do {
            // moveItem fails when the original path has been occupied. Never replace that file.
            try FileManager.default.moveItem(at: recovery, to: original)
        } catch {
            throw OperationError.recoveryRequired(recovery.path, failure.localizedDescription)
        }
        throw failure
    }

    enum OperationError: LocalizedError {
        case unsafePath(String)
        case recoveryRequired(String, String)
        var errorDescription: String? {
            switch self {
            case .unsafePath(let path): return "The operation was stopped because this is not a regular file inside the selected source: \(path)"
            case .recoveryRequired(let path, let reason): return "The catalogue could not be updated. Your file is preserved at \(path). Restore or relink it before retrying. \(reason)"
            }
        }
    }
}

/// Streaming, cancellable hashing. A changing file must never become an exact-duplicate match.
enum MediaContentHasher {
    static func hash(_ url: URL) throws -> String {
        let before = try FileManager.default.attributesOfItem(atPath: url.path)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var bytesRead: Int64 = 0
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty else { break }
            bytesRead += Int64(data.count)
            hasher.update(data: data)
        }
        let after = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = before[.size] as? NSNumber, size.int64Value == bytesRead,
              size == after[.size] as? NSNumber,
              before[.modificationDate] as? Date == after[.modificationDate] as? Date,
              before[.systemFileNumber] as? NSNumber == after[.systemFileNumber] as? NSNumber else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "The file changed while it was being checked. Run duplicate detection again."])
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func hashInBackground(_ url: URL) async throws -> String {
        let task = Task.detached(priority: .utility) { try hash(url) }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    static func verifyDuplicate(_ url: URL, keeping keeper: URL, expectedHash: String) async throws {
        let keeperHash = try await hashInBackground(keeper)
        let duplicateHash = try await hashInBackground(url)
        guard keeperHash == expectedHash, duplicateHash == expectedHash else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "The duplicate or the copy to keep has changed. Nothing was moved to Trash. Run duplicate detection again."])
        }
    }
}
