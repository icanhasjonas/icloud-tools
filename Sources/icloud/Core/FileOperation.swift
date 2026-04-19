import Foundation

struct FileOperationResult: Encodable {
    let source: String
    let destination: String
    let status: String
    let size: Int64
}

struct FileOperation {
    static func execute(
        paths: [String],
        verb: String,
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

        let actionVerb = verb == "moved" ? "move" : "copy"

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
                let srcResolved = srcURL.resolvingSymlinksInPath().path
                try Downloader.ensureLocalRecursive(srcURL, dryRun: dryRun) { event in
                    guard verbose && !json else { return }
                    let f: ICloudFile
                    switch event {
                    case .starting(let file): f = file
                    case .done(let file): f = file
                    case .wouldDownload(let file): f = file
                    case .skipped(let file): f = file
                    }

                    let display = PathResolver.relativePath(f.url, rebase: rebase)
                    let size = Output.humanSize(f.fileSize)
                    let childRelative = String(f.url.resolvingSymlinksInPath().path.dropFirst(srcResolved.count))
                    let toURL = finalDest.appendingPathComponent(childRelative)
                    let toDisplay = PathResolver.relativePath(toURL)

                    switch event {
                    case .starting:
                        print("\(display) \(Output.dim)(\(size))\(Output.reset)")
                        print("  \(Output.yellow)downloading...\(Output.reset)")
                    case .done:
                        print("  \(Output.green)\(verb)\(Output.reset) -> \(toDisplay)")
                    case .wouldDownload:
                        print("\(display) \(Output.dim)(\(size))\(Output.reset)")
                        print("  \(Output.dim)would download\(Output.reset)")
                        print("  \(Output.dim)would \(actionVerb)\(Output.reset) -> \(toDisplay)")
                    case .skipped:
                        print("\(display) \(Output.dim)(\(size))\(Output.reset)")
                        if dryRun {
                            print("  \(Output.dim)would \(actionVerb)\(Output.reset) -> \(toDisplay)")
                        } else {
                            print("  \(Output.green)\(verb)\(Output.reset) -> \(toDisplay)")
                        }
                    }
                }
            } else {
                let needsDownload = fileInfo.isUbiquitous && fileInfo.status == .cloud
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

                try Downloader.ensureLocal(srcURL, dryRun: dryRun)
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
                    if !dryRun {
                        try fm.removeItem(at: finalDest)
                    }
                } else {
                    throw FileOperationError.destinationExists(finalDest.path)
                }
            }

            if dryRun {
                if json {
                    try Output.printJSONLine(FileOperationResult(
                        source: srcURL.path, destination: finalDest.path,
                        status: "would-\(actionVerb)", size: fileInfo.fileSize))
                } else if !srcIsDir.boolValue {
                    print("  \(Output.dim)would \(actionVerb)\(Output.reset) -> \(destDisplay)")
                }
            } else {
                try operation(fm, srcURL, finalDest)

                if json {
                    try Output.printJSONLine(FileOperationResult(
                        source: srcURL.path, destination: finalDest.path,
                        status: verb, size: fileInfo.fileSize))
                } else if verbose && !srcIsDir.boolValue {
                    print("  \(Output.green)\(verb)\(Output.reset) -> \(destDisplay)")
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
        }
    }
}
