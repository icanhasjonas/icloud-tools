import Foundation
import Darwin

private struct Discovered {
    let src: URL
    let dst: URL
    let size: Int64
    let needsDownload: Bool
}

struct FileOperation {
    static func execute(
        paths: [String],
        verb: FileVerb,
        allowDirectories: Bool,
        force: Bool,
        noClobber: Bool,
        ignoreMissing: Bool = false,
        dryRun: Bool = false,
        baselineTimeout: TimeInterval = Downloader.defaultBaselineTimeout,
        maxConcurrent: Int = Downloader.defaultMaxConcurrent,
        renderer: OpRenderer,
        operation: (FileManager, URL, URL) throws -> Void
    ) throws {
        let fm = FileManager.default
        let sources = paths.dropLast()
        let rawDest = paths.last!
        let destURL = PathResolver.resolve(rawDest)
        var destIsDir: ObjCBool = false
        var destExists = fm.fileExists(atPath: destURL.path, isDirectory: &destIsDir)

        // Trailing slash on dest means "treat as a directory". If it doesn't exist, create it
        // (parents must exist -- we don't mkdir -p beyond the final component; that catches typos).
        // If it exists but is a file, error -- can't put files inside a file.
        let destHasTrailingSlash = rawDest.hasSuffix("/")
        if destHasTrailingSlash && destExists && !destIsDir.boolValue {
            throw FileOperationError.destinationNotDirectoryPath(destURL.path)
        }
        if destHasTrailingSlash && !destExists {
            let parent = destURL.deletingLastPathComponent()
            guard fm.fileExists(atPath: parent.path) else {
                throw FileOperationError.destinationDirMissing(destURL.path)
            }
            try fm.createDirectory(at: destURL, withIntermediateDirectories: false)
            destExists = true
            destIsDir = true
        }

        if sources.count > 1 && (!destExists || !destIsDir.boolValue) {
            throw FileOperationError.destinationNotDirectory
        }

        if force && noClobber {
            throw FileOperationError.conflictingFlags
        }

        for source in sources {
            try processSource(
                source: source, verb: verb, allowDirectories: allowDirectories,
                force: force, noClobber: noClobber,
                ignoreMissing: ignoreMissing, dryRun: dryRun,
                baselineTimeout: baselineTimeout, maxConcurrent: maxConcurrent,
                destURL: destURL, destExists: destExists, destIsDir: destIsDir.boolValue,
                renderer: renderer, operation: operation
            )
        }
    }

    private static func processSource(
        source: String, verb: FileVerb, allowDirectories: Bool,
        force: Bool, noClobber: Bool,
        ignoreMissing: Bool, dryRun: Bool,
        baselineTimeout: TimeInterval, maxConcurrent: Int,
        destURL: URL, destExists: Bool, destIsDir: Bool,
        renderer: OpRenderer,
        operation: (FileManager, URL, URL) throws -> Void
    ) throws {
        let fm = FileManager.default
        let srcURL = PathResolver.resolve(source)
        var srcIsDir: ObjCBool = false

        guard fm.fileExists(atPath: srcURL.path, isDirectory: &srcIsDir) else {
            if ignoreMissing {
                try renderer.handle(.sourceMissing(src: srcURL))
                return
            }
            throw FileOperationError.sourceNotFound(srcURL.path)
        }

        if srcIsDir.boolValue && !allowDirectories {
            throw FileOperationError.directoryRequiresRecursive(srcURL.lastPathComponent)
        }

        let finalDest = destExists && destIsDir
            ? destURL.appendingPathComponent(srcURL.lastPathComponent)
            : destURL

        let previousRebase = renderer.rebase
        renderer.rebase = PathResolver.Rebase(srcURL)
        defer { renderer.rebase = previousRebase }

        try renderer.handle(.phaseStart(phase: .discover, totalFiles: nil))
        let discovered = try discover(srcURL: srcURL, finalDest: finalDest, isDir: srcIsDir.boolValue)
        for d in discovered {
            try renderer.handle(.discovered(src: d.src, dst: d.dst, size: d.size, needsDownload: d.needsDownload))
        }
        try renderer.handle(.phaseEnd(phase: .discover))

        var finalDestIsDir: ObjCBool = false
        let finalDestExists = fm.fileExists(atPath: finalDest.path, isDirectory: &finalDestIsDir)

        if finalDestExists {
            if srcIsDir.boolValue && !finalDestIsDir.boolValue {
                throw FileOperationError.typeMismatch(src: srcURL.path, dst: finalDest.path, reason: "source is a directory but destination is a file")
            }
            if !srcIsDir.boolValue && finalDestIsDir.boolValue {
                throw FileOperationError.typeMismatch(src: srcURL.path, dst: finalDest.path, reason: "source is a file but destination is a directory")
            }
        }

        if dryRun {
            for d in discovered {
                try renderer.handle(.opWouldDo(verb: verb, src: d.src, dst: d.dst, size: d.size))
            }
            return
        }

        // Fast path first: files that are already local have nothing to wait for.
        // Copy them now and show their completion, so the user sees progress instead
        // of staring at downloads for minutes.
        let readyNow = discovered.filter { !$0.needsDownload }
        let needsDL = discovered.filter { $0.needsDownload }

        var collectedErrors: [Error] = []

        if !readyNow.isEmpty {
            do {
                try performFiles(
                    discovered: readyNow, srcURL: srcURL, verb: verb,
                    force: force, noClobber: noClobber,
                    renderer: renderer, operation: operation
                )
            } catch {
                collectedErrors.append(error)
            }
        }

        if !needsDL.isEmpty {
            do {
                try interleaveDownloadAndCopy(
                    pending: needsDL, srcURL: srcURL, verb: verb,
                    force: force, noClobber: noClobber,
                    baselineTimeout: baselineTimeout, maxConcurrent: maxConcurrent,
                    renderer: renderer, operation: operation
                )
            } catch {
                collectedErrors.append(error)
            }
        }

        if let first = collectedErrors.first { throw first }
    }

    /// Download + copy interleaved: up to `maxConcurrent` downloads in flight at once; as
    /// each file's download completes (or times out), IMMEDIATELY run the per-file copy
    /// and emit opDone/opFail for that one file. User sees per-file completion without
    /// waiting for the entire download phase.
    private static func interleaveDownloadAndCopy(
        pending: [Discovered], srcURL: URL, verb: FileVerb,
        force: Bool, noClobber: Bool,
        baselineTimeout: TimeInterval, maxConcurrent: Int,
        renderer: OpRenderer, operation: (FileManager, URL, URL) throws -> Void
    ) throws {
        let fm = FileManager.default
        let cap = max(1, maxConcurrent)

        var queue = pending
        var inFlight: [String: (d: Discovered, file: ICloudFile, started: Date, deadline: Date)] = [:]
        var failedCount = 0

        func dispatchMore() throws {
            while inFlight.count < cap, !queue.isEmpty {
                let d = queue.removeFirst()
                let file: ICloudFile
                do {
                    file = try ICloudFile.from(url: d.src, checkPin: false)
                } catch {
                    try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: error))
                    failedCount += 1
                    continue
                }
                if file.status != .downloading {
                    try fm.startDownloadingUbiquitousItem(at: file.url)
                }
                try renderer.handle(.downloadStart(url: file.url, size: file.fileSize))
                let now = Date()
                let t = Downloader.timeoutFor(sizeBytes: file.fileSize, baseline: baselineTimeout)
                inFlight[file.url.path] = (d, file, now, now.addingTimeInterval(t))
            }
        }

        try dispatchMore()

        while !inFlight.isEmpty || !queue.isEmpty {
            for key in Array(inFlight.keys) {
                guard let entry = inFlight[key] else { continue }
                let fresh = URL(fileURLWithPath: key)
                let values = try fresh.resourceValues(forKeys: [
                    .ubiquitousItemDownloadingStatusKey,
                    .fileSizeKey,
                    .fileAllocatedSizeKey,
                ])
                let status = values.ubiquitousItemDownloadingStatus
                let fileSize = Int64(values.fileSize ?? 0)
                let allocated = Int64(values.fileAllocatedSize ?? 0)
                let stillDataless = fileSize > 0 && allocated == 0

                if (status == .current || status == .downloaded) && !stillDataless {
                    let elapsed = Date().timeIntervalSince(entry.started)
                    try renderer.handle(.downloadDone(url: entry.file.url, size: fileSize, elapsed: elapsed))
                    inFlight.removeValue(forKey: key)
                    do {
                        try performOneFile(
                            d: entry.d, verb: verb,
                            force: force, noClobber: noClobber,
                            renderer: renderer, operation: operation
                        )
                    } catch {
                        failedCount += 1
                    }
                } else if Date() > entry.deadline {
                    // Timeout is terminal: the file is still dataless. Copying now would
                    // emit a second opFail for the same file and double-count in the
                    // summary. Leave downloadFail as the sole signal; it ticks timedOut.
                    let err = DownloadError.timeout(entry.file.url.lastPathComponent)
                    try renderer.handle(.downloadFail(url: entry.file.url, error: err))
                    inFlight.removeValue(forKey: key)
                    failedCount += 1
                } else {
                    let elapsed = Date().timeIntervalSince(entry.started)
                    try renderer.handle(.downloadTick(url: entry.file.url, elapsed: elapsed))
                }
            }

            try dispatchMore()

            if !inFlight.isEmpty {
                Thread.sleep(forTimeInterval: 0.25)
            }
        }

        if failedCount > 0 {
            throw FileOperationError.partialFailure(sourcePath: srcURL.path, failedCount: failedCount)
        }
    }

    private static func discover(srcURL: URL, finalDest: URL, isDir: Bool) throws -> [Discovered] {
        if !isDir {
            let file = try ICloudFile.from(url: srcURL, checkPin: false)
            return [Discovered(
                src: srcURL, dst: finalDest,
                size: file.fileSize,
                needsDownload: Downloader.needsDownload(file)
            )]
        }

        let files = try Downloader.enumerate(srcURL)
        let srcRoot = srcURL.resolvingSymlinksInPath().pathComponents

        return try files.map { file in
            let fileComps = file.url.resolvingSymlinksInPath().pathComponents
            guard fileComps.count > srcRoot.count,
                  Array(fileComps.prefix(srcRoot.count)) == srcRoot
            else {
                throw FileOperationError.typeMismatch(
                    src: file.url.path,
                    dst: finalDest.path,
                    reason: "enumerated file not under source root (src=\(srcURL.path))"
                )
            }
            var dst = finalDest
            for c in fileComps.dropFirst(srcRoot.count) {
                dst = dst.appendingPathComponent(c)
            }
            return Discovered(
                src: file.url,
                dst: dst,
                size: file.fileSize,
                needsDownload: Downloader.needsDownload(file)
            )
        }
    }

    /// Per-file loop: for each Discovered, do the single-file op. Used for already-local
    /// files. For files that need downloading, use `performOneFile` via the interleaved
    /// download+copy path in `processSource`.
    private static func performFiles(
        discovered: [Discovered], srcURL: URL, verb: FileVerb,
        force: Bool, noClobber: Bool,
        renderer: OpRenderer, operation: (FileManager, URL, URL) throws -> Void
    ) throws {
        try renderer.handle(.phaseStart(phase: .operate, totalFiles: discovered.count))
        var failedCount = 0
        for d in discovered {
            do {
                try performOneFile(d: d, verb: verb, force: force, noClobber: noClobber,
                                   renderer: renderer, operation: operation)
            } catch {
                failedCount += 1
            }
        }
        try renderer.handle(.phaseEnd(phase: .operate))
        if failedCount > 0 {
            throw FileOperationError.partialFailure(sourcePath: srcURL.path, failedCount: failedCount)
        }
    }

    /// One file: create parent dir, conflict-check, run op, verify, emit. Errors are
    /// emitted as opFail and re-thrown so callers can count failures. On failure, any
    /// parent directories we created for this op are removed (bottom-up, only if empty)
    /// so we don't leave behind a skeleton of empty dirs.
    fileprivate static func performOneFile(
        d: Discovered, verb: FileVerb,
        force: Bool, noClobber: Bool,
        renderer: OpRenderer, operation: (FileManager, URL, URL) throws -> Void
    ) throws {
        let fm = FileManager.default
        let parentDir = d.dst.deletingLastPathComponent()
        let createdDirs = missingAncestors(of: parentDir, fm: fm)
        if !createdDirs.isEmpty {
            do {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: error))
                throw error
            }
        }
        var success = false
        defer {
            if !success { removeEmptyDirs(createdDirs, fm: fm) }
        }

        var targetIsDir: ObjCBool = false
        let targetExists = fm.fileExists(atPath: d.dst.path, isDirectory: &targetIsDir)

        if targetExists && targetIsDir.boolValue {
            let err = FileOperationError.typeMismatch(src: d.src.path, dst: d.dst.path, reason: "target path is a directory; will not delete directories")
            try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: err))
            throw err
        }

        if targetExists {
            if noClobber {
                try renderer.handle(.opSkipped(verb: verb, src: d.src, dst: d.dst, reason: "exists", size: d.size))
                success = true
                return
            }
            if !force {
                let err = FileOperationError.destinationExists(d.dst.path)
                try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: err))
                throw err
            }
            do {
                try replaceWithBackup(src: d.src, dst: d.dst, operation: operation)
            } catch let err {
                try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: err))
                throw err
            }
        } else {
            do {
                try operation(fm, d.src, d.dst)
            } catch let err {
                try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: err))
                throw err
            }
        }

        if let verifyErr = verifyOne(d: d) {
            try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: verifyErr))
            throw verifyErr
        }
        success = true
        try renderer.handle(.opDone(verb: verb, src: d.src, dst: d.dst, size: d.size))
    }

    /// Walks up from `dir` collecting ancestors that don't exist. Innermost first,
    /// outermost last -- matching the cleanup order we want on failure.
    private static func missingAncestors(of dir: URL, fm: FileManager) -> [URL] {
        var missing: [URL] = []
        var current = dir
        while !fm.fileExists(atPath: current.path) {
            missing.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return missing
    }

    /// Remove empty dirs bottom-up. Stops at the first non-empty dir so we never
    /// touch anything the user (or a concurrent sibling op) put there.
    private static func removeEmptyDirs(_ dirs: [URL], fm: FileManager) {
        for dir in dirs {
            let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? ["__nonempty__"]
            if contents.isEmpty {
                _ = try? fm.removeItem(at: dir)
            } else {
                break
            }
        }
    }


    private static func replaceWithBackup(
        src: URL, dst: URL,
        operation: (FileManager, URL, URL) throws -> Void
    ) throws {
        let fm = FileManager.default
        let backup = try makeBackup(of: dst)
        do {
            try operation(fm, src, dst)
            if unlink(backup.path) != 0 {
                let e = errno
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(e),
                    userInfo: [NSLocalizedDescriptionKey: "failed to remove backup \(backup.path): \(String(cString: strerror(e)))"])
            }
        } catch let opError {
            if rename(backup.path, dst.path) != 0 {
                let e = errno
                let restoreMsg = "\(String(cString: strerror(e))) (rename)"
                throw FileOperationError.restoreFailed(
                    backupPath: backup.path,
                    operationError: opError.localizedDescription,
                    restoreError: restoreMsg
                )
            }
            throw opError
        }
    }

    /// Backup via rename(2) only. Same directory, same filesystem -> atomic inode rename,
    /// no content inspection. Never use fm.moveItem here: on APFS it can engage clonefile
    /// semantics which, on iCloud-materialized files, produces a dataless backup and loses
    /// the original's bytes if restore is needed.
    private static func makeBackup(of target: URL) throws -> URL {
        let suffix = ".icloud-backup-\(ProcessInfo.processInfo.processIdentifier)-\(Int(Date().timeIntervalSince1970))-\(Int.random(in: 0...99999))"
        let backup = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent)\(suffix)")
        if rename(target.path, backup.path) != 0 {
            let e = errno
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(e),
                userInfo: [NSLocalizedDescriptionKey: "backup rename failed: \(String(cString: strerror(e))) (\(target.path) -> \(backup.path))"]
            )
        }
        return backup
    }

    private static func verifyOne(d: Discovered) -> Error? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: d.dst.path) else {
            return FileOperationError.verificationFailed(d.dst.path, reason: "destination missing after op")
        }
        guard d.size > 0 else { return nil }

        let fresh = URL(fileURLWithPath: d.dst.path)
        let logical: Int64
        let allocated: Int64
        do {
            let values = try fresh.resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey])
            logical = Int64(values.fileSize ?? 0)
            allocated = Int64(values.fileAllocatedSize ?? 0)
        } catch {
            return error
        }

        if logical != d.size {
            return FileOperationError.verificationFailed(d.dst.path, reason: "logical size mismatch: expected \(d.size), got \(logical)")
        }
        if allocated == 0 {
            return FileOperationError.verificationFailed(d.dst.path, reason: "dataless destination (logical=\(logical), allocated=0) - operation produced a placeholder, not real bytes")
        }
        return nil
    }

}

extension FileOperation {
    /// Byte-level copy of a single file. copyfile(3) with COPYFILE_ALL: data (forced, no
    /// clone) + xattr (tags, Finder comments, Spotlight) + stat + ACLs. Works across
    /// filesystems. Directories are never passed here -- callers enumerate children.
    static func safeCopy(from src: URL, to dst: URL) throws {
        if copyfile(src.path, dst.path, nil, copyfile_flags_t(COPYFILE_ALL)) != 0 {
            let saved = errno
            throw posixFail("copyfile", errno: saved, src: src, dst: dst)
        }
    }

    /// Move a single file. rename(2) first (atomic, same filesystem). On EXDEV
    /// (cross-filesystem), safeCopy + unlink source.
    static func safeMove(from src: URL, to dst: URL) throws {
        if rename(src.path, dst.path) == 0 { return }
        let renameErrno = errno
        if renameErrno != EXDEV {
            throw posixFail("rename", errno: renameErrno, src: src, dst: dst)
        }
        try safeCopy(from: src, to: dst)
        if unlink(src.path) != 0 {
            let e = errno
            throw posixFail("unlink", errno: e, src: src, dst: dst)
        }
    }

    private static func posixFail(_ what: String, errno e: Int32, src: URL, dst: URL) -> Error {
        let msg = String(cString: strerror(e))
        return NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(e),
            userInfo: [NSLocalizedDescriptionKey: "\(what) failed: \(msg) (\(src.path) -> \(dst.path))"]
        )
    }
}

enum FileOperationError: LocalizedError {
    case sourceNotFound(String)
    case destinationNotDirectory
    case destinationDirMissing(String)
    case destinationNotDirectoryPath(String)
    case destinationExists(String)
    case directoryRequiresRecursive(String)
    case conflictingFlags
    case restoreFailed(backupPath: String, operationError: String, restoreError: String)
    case verificationFailed(String, reason: String)
    case typeMismatch(src: String, dst: String, reason: String)
    case partialFailure(sourcePath: String, failedCount: Int)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound(let path):
            return "Source not found: \(path)"
        case .destinationNotDirectory:
            return "Destination must be a directory when operating on multiple files."
        case .destinationDirMissing(let path):
            return "Destination directory does not exist: \(path) (trailing / requires an existing directory)"
        case .destinationNotDirectoryPath(let path):
            return "Destination is not a directory: \(path) (trailing / requires a directory)"
        case .destinationExists(let path):
            return "Destination exists: \(path) (use -f to overwrite)"
        case .directoryRequiresRecursive(let name):
            return "\(name) is a directory (use -r to copy recursively)"
        case .conflictingFlags:
            return "Cannot use --force and --no-clobber together."
        case .restoreFailed(let backupPath, let opError, let restoreError):
            return "Operation failed (\(opError)) AND backup restore failed (\(restoreError)). Backup left at: \(backupPath)"
        case .verificationFailed(let path, let reason):
            return "Verification failed for \(path): \(reason)"
        case .typeMismatch(let src, let dst, let reason):
            return "Cannot complete \(src) -> \(dst): \(reason)"
        case .partialFailure(let path, let n):
            return "\(n) file\(n == 1 ? "" : "s") from \(path) could not be moved or copied (see above)."
        }
    }
}
