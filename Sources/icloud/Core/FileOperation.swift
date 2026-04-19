import Foundation

enum FileVerb {
    case move
    case copy

    var past: String {
        switch self {
        case .move: return "moved"
        case .copy: return "copied"
        }
    }

    var present: String {
        switch self {
        case .move: return "move"
        case .copy: return "copy"
        }
    }
}

struct FileOperationResult: Encodable {
    let source: String
    let destination: String
    let status: String
    let size: Int64
}

struct FileOperation {
    static func execute(
        paths: [String],
        verb: FileVerb,
        allowDirectories: Bool,
        force: Bool,
        noClobber: Bool,
        verbose: Bool,
        json: Bool,
        dryRun: Bool = false,
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
            let srcURL = PathResolver.resolve(source)
            var srcIsDir: ObjCBool = false

            guard fm.fileExists(atPath: srcURL.path, isDirectory: &srcIsDir) else {
                throw FileOperationError.sourceNotFound(srcURL.path)
            }

            if srcIsDir.boolValue && !allowDirectories {
                throw FileOperationError.directoryRequiresRecursive(srcURL.lastPathComponent)
            }

            let fileInfo = try ICloudFile.from(url: srcURL, checkPin: false)
            let srcDisplay = PathResolver.relativePath(srcURL)
            let finalDest = destExists && destIsDir.boolValue
                ? destURL.appendingPathComponent(srcURL.lastPathComponent)
                : destURL
            let destDisplay = PathResolver.relativePath(finalDest)

            if srcIsDir.boolValue {
                let rebase = PathResolver.Rebase(srcURL)
                try Downloader.ensureLocalRecursive(srcURL, dryRun: dryRun) { event in
                    guard verbose && !json else { return }
                    let f = event.file
                    let display = PathResolver.relativePath(f.url, rebase: rebase)
                    let size = Output.humanSize(f.fileSize)

                    switch event {
                    case .starting:
                        print("\(display) \(Output.dim)(\(size))\(Output.reset)")
                        print("  \(Output.yellow)downloading...\(Output.reset)")
                    case .done:
                        print("  \(Output.green)ready\(Output.reset)")
                    case .wouldDownload:
                        print("\(display) \(Output.dim)(\(size))\(Output.reset)")
                        print("  \(Output.dim)would download\(Output.reset)")
                    case .skipped:
                        break
                    }
                }
            } else {
                let needsDownload = fileInfo.isUbiquitous && (fileInfo.status == .cloud || fileInfo.isDataless)
                let size = Output.humanSize(fileInfo.fileSize)

                if verbose && !json {
                    print("\(srcDisplay) \(Output.dim)(\(size))\(Output.reset)")
                    if needsDownload {
                        if dryRun {
                            print("  \(Output.dim)would download\(Output.reset)")
                        } else {
                            print("  \(Output.yellow)downloading...\(Output.reset)")
                        }
                    }
                }

                try Downloader.ensureLocal(fileInfo, dryRun: dryRun)
            }

            if fm.fileExists(atPath: finalDest.path) {
                if noClobber {
                    if json {
                        try Output.printJSONLine(FileOperationResult(
                            source: srcURL.path, destination: finalDest.path,
                            status: "skipped", size: fileInfo.fileSize))
                    } else if verbose {
                        print("  \(Output.yellow)skipped\(Output.reset) (exists)")
                    }
                    continue
                }
                if force {
                    if dryRun {
                        // don't delete in dry-run
                    } else {
                        // move existing dest to temp, operate, then clean up
                        // if operation fails, restore dest from temp
                        let tempDest = finalDest.deletingLastPathComponent()
                            .appendingPathComponent(".\(finalDest.lastPathComponent).icloud-backup")
                        try fm.moveItem(at: finalDest, to: tempDest)
                        do {
                            try operation(fm, srcURL, finalDest)
                            try fm.removeItem(at: tempDest)
                        } catch {
                            try? fm.moveItem(at: tempDest, to: finalDest)
                            throw error
                        }

                        if json {
                            try Output.printJSONLine(FileOperationResult(
                                source: srcURL.path, destination: finalDest.path,
                                status: verb.past, size: fileInfo.fileSize))
                        } else if verbose {
                            print("\(Output.green)\(verb.past)\(Output.reset) \(srcDisplay) -> \(destDisplay)")
                        }
                        continue
                    }
                } else {
                    throw FileOperationError.destinationExists(finalDest.path)
                }
            }

            if dryRun {
                if json {
                    try Output.printJSONLine(FileOperationResult(
                        source: srcURL.path, destination: finalDest.path,
                        status: "would-\(verb.present)", size: fileInfo.fileSize))
                } else {
                    print("  \(Output.dim)would \(verb.present)\(Output.reset) -> \(destDisplay)")
                }
            } else {
                try operation(fm, srcURL, finalDest)

                if json {
                    try Output.printJSONLine(FileOperationResult(
                        source: srcURL.path, destination: finalDest.path,
                        status: verb.past, size: fileInfo.fileSize))
                } else if verbose {
                    print("\(Output.green)\(verb.past)\(Output.reset) \(srcDisplay) -> \(destDisplay)")
                }
            }
        }
    }
}

enum FileOperationError: LocalizedError {
    case sourceNotFound(String)
    case destinationNotDirectory
    case destinationExists(String)
    case directoryRequiresRecursive(String)
    case conflictingFlags

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
        }
    }
}
