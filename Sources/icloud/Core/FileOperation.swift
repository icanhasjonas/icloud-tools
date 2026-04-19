import Foundation

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
        dryRun: Bool = false,
        timeout: TimeInterval = 300,
        renderer: OpRenderer,
        operation: (FileManager, URL, URL) throws -> Void
    ) throws {
        let fm = FileManager.default
        let sources = paths.dropLast()
        let destURL = PathResolver.resolve(paths.last!)
        var destIsDir: ObjCBool = false
        let destExists = fm.fileExists(atPath: destURL.path, isDirectory: &destIsDir)

        if sources.count > 1 && (!destExists || !destIsDir.boolValue) {
            throw FileOperationError.destinationNotDirectory
        }

        if force && noClobber {
            throw FileOperationError.conflictingFlags
        }

        for source in sources {
            try processSource(
                source: source, verb: verb, allowDirectories: allowDirectories,
                force: force, noClobber: noClobber, dryRun: dryRun, timeout: timeout,
                destURL: destURL, destExists: destExists, destIsDir: destIsDir.boolValue,
                renderer: renderer, operation: operation
            )
        }
    }

    private static func processSource(
        source: String, verb: FileVerb, allowDirectories: Bool,
        force: Bool, noClobber: Bool, dryRun: Bool, timeout: TimeInterval,
        destURL: URL, destExists: Bool, destIsDir: Bool,
        renderer: OpRenderer,
        operation: (FileManager, URL, URL) throws -> Void
    ) throws {
        let fm = FileManager.default
        let srcURL = PathResolver.resolve(source)
        var srcIsDir: ObjCBool = false

        guard fm.fileExists(atPath: srcURL.path, isDirectory: &srcIsDir) else {
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

        let files = try Downloader.enumerate(srcURL)
        let pendingCount = files.filter { Downloader.needsDownload($0) }.count
        try renderer.handle(.phaseStart(phase: .download, totalFiles: pendingCount))
        try Downloader.ensureLocalBatch(files, timeout: timeout, dryRun: false) { event in
            try renderer.handle(event)
        }
        try renderer.handle(.phaseEnd(phase: .download))

        let isMergeCase = finalDestExists && srcIsDir.boolValue && finalDestIsDir.boolValue

        if isMergeCase {
            try mergeMove(
                discovered: discovered, srcURL: srcURL, verb: verb,
                force: force, noClobber: noClobber,
                renderer: renderer, operation: operation
            )
        } else {
            try singleOpMove(
                discovered: discovered, srcURL: srcURL, finalDest: finalDest, verb: verb,
                force: force, noClobber: noClobber, finalDestExists: finalDestExists,
                renderer: renderer, operation: operation
            )
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
        let srcResolved = srcURL.resolvingSymlinksInPath().path
        return files.map { file in
            let childRel = String(file.url.resolvingSymlinksInPath().path.dropFirst(srcResolved.count))
            return Discovered(
                src: file.url,
                dst: finalDest.appendingPathComponent(childRel),
                size: file.fileSize,
                needsDownload: Downloader.needsDownload(file)
            )
        }
    }

    private static func mergeMove(
        discovered: [Discovered], srcURL: URL, verb: FileVerb,
        force: Bool, noClobber: Bool,
        renderer: OpRenderer, operation: (FileManager, URL, URL) throws -> Void
    ) throws {
        let fm = FileManager.default
        try renderer.handle(.phaseStart(phase: .operate, totalFiles: discovered.count))
        var anyFailed = false

        for d in discovered {
            let parentDir = d.dst.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                do {
                    try fm.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: error))
                    anyFailed = true
                    continue
                }
            }

            var targetIsDir: ObjCBool = false
            let targetExists = fm.fileExists(atPath: d.dst.path, isDirectory: &targetIsDir)

            if targetExists && targetIsDir.boolValue {
                let err = FileOperationError.typeMismatch(src: d.src.path, dst: d.dst.path, reason: "target path is a directory; will not delete directories")
                try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: err))
                anyFailed = true
                continue
            }

            if targetExists {
                if noClobber {
                    try renderer.handle(.opSkipped(verb: verb, src: d.src, dst: d.dst, reason: "exists", size: d.size))
                    continue
                }
                if !force {
                    let err = FileOperationError.destinationExists(d.dst.path)
                    try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: err))
                    anyFailed = true
                    continue
                }
                do {
                    try replaceWithBackup(src: d.src, dst: d.dst, operation: operation)
                } catch let err {
                    try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: err))
                    anyFailed = true
                    continue
                }
            } else {
                do {
                    try operation(fm, d.src, d.dst)
                } catch let err {
                    try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: err))
                    anyFailed = true
                    continue
                }
            }

            if let verifyErr = verifyOne(d: d) {
                try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: verifyErr))
                anyFailed = true
                continue
            }
            try renderer.handle(.opDone(verb: verb, src: d.src, dst: d.dst, size: d.size))
        }

        try renderer.handle(.phaseEnd(phase: .operate))

        if anyFailed {
            throw FileOperationError.partialFailure(sourcePath: srcURL.path)
        }
    }

    private static func singleOpMove(
        discovered: [Discovered], srcURL: URL, finalDest: URL, verb: FileVerb,
        force: Bool, noClobber: Bool, finalDestExists: Bool,
        renderer: OpRenderer, operation: (FileManager, URL, URL) throws -> Void
    ) throws {
        let fm = FileManager.default

        if finalDestExists {
            if noClobber {
                for d in discovered {
                    try renderer.handle(.opSkipped(verb: verb, src: d.src, dst: d.dst, reason: "exists", size: d.size))
                }
                return
            }
            if !force {
                throw FileOperationError.destinationExists(finalDest.path)
            }
        }

        var backupURL: URL?
        if force && finalDestExists {
            backupURL = try makeBackup(of: finalDest)
        }

        try renderer.handle(.phaseStart(phase: .operate, totalFiles: discovered.count))
        do {
            try operation(fm, srcURL, finalDest)
            if let bu = backupURL {
                try fm.removeItem(at: bu)
            }
        } catch let opError {
            if let bu = backupURL {
                do {
                    try fm.moveItem(at: bu, to: finalDest)
                } catch let restoreError {
                    throw FileOperationError.restoreFailed(
                        backupPath: bu.path,
                        operationError: opError.localizedDescription,
                        restoreError: restoreError.localizedDescription
                    )
                }
            }
            for d in discovered {
                try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: opError))
            }
            throw opError
        }
        try renderer.handle(.phaseEnd(phase: .operate))

        try verifyAndReport(verb: verb, discovered: discovered, renderer: renderer)
    }

    private static func replaceWithBackup(
        src: URL, dst: URL,
        operation: (FileManager, URL, URL) throws -> Void
    ) throws {
        let fm = FileManager.default
        let backup = try makeBackup(of: dst)
        do {
            try operation(fm, src, dst)
            try fm.removeItem(at: backup)
        } catch let opError {
            do {
                try fm.moveItem(at: backup, to: dst)
            } catch let restoreError {
                throw FileOperationError.restoreFailed(
                    backupPath: backup.path,
                    operationError: opError.localizedDescription,
                    restoreError: restoreError.localizedDescription
                )
            }
            throw opError
        }
    }

    private static func makeBackup(of target: URL) throws -> URL {
        let fm = FileManager.default
        let suffix = ".icloud-backup-\(ProcessInfo.processInfo.processIdentifier)-\(Int(Date().timeIntervalSince1970))-\(Int.random(in: 0...99999))"
        let backup = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent)\(suffix)")
        try fm.moveItem(at: target, to: backup)
        return backup
    }

    private static func verifyOne(d: Discovered) -> Error? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: d.dst.path) else {
            return FileOperationError.verificationFailed(d.dst.path, reason: "destination missing after op")
        }
        if d.size > 0 {
            do {
                let attrs = try fm.attributesOfItem(atPath: d.dst.path)
                let actual = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                if actual != d.size {
                    return FileOperationError.verificationFailed(d.dst.path, reason: "size mismatch: expected \(d.size), got \(actual)")
                }
            } catch {
                return error
            }
        }
        return nil
    }

    private static func verifyAndReport(
        verb: FileVerb, discovered: [Discovered], renderer: OpRenderer
    ) throws {
        var failed = 0
        for d in discovered {
            if let err = verifyOne(d: d) {
                try renderer.handle(.opFail(verb: verb, src: d.src, dst: d.dst, error: err))
                failed += 1
                continue
            }
            try renderer.handle(.opDone(verb: verb, src: d.src, dst: d.dst, size: d.size))
        }
        if failed > 0 {
            throw FileOperationError.verificationFailed("<\(failed) file(s)>", reason: "post-op verification failed for \(failed) file(s)")
        }
    }
}

enum FileOperationError: LocalizedError {
    case sourceNotFound(String)
    case destinationNotDirectory
    case destinationExists(String)
    case directoryRequiresRecursive(String)
    case conflictingFlags
    case restoreFailed(backupPath: String, operationError: String, restoreError: String)
    case verificationFailed(String, reason: String)
    case typeMismatch(src: String, dst: String, reason: String)
    case partialFailure(sourcePath: String)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound(let path):
            return "Source not found: \(path)"
        case .destinationNotDirectory:
            return "Destination must be a directory when operating on multiple files."
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
        case .partialFailure(let path):
            return "Some files from \(path) could not be moved (see above)."
        }
    }
}
