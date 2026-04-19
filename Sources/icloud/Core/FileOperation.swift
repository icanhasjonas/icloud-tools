import Foundation

struct FileOperationResult: Encodable {
    let source: String
    let destination: String
    let status: String
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

        for source in sources {
            let srcURL = PathResolver.resolve(source)
            var srcIsDir: ObjCBool = false

            guard fm.fileExists(atPath: srcURL.path, isDirectory: &srcIsDir) else {
                throw FileOperationError.sourceNotFound(srcURL.path)
            }

            if srcIsDir.boolValue && !allowDirectories {
                throw FileOperationError.directoryRequiresRecursive(srcURL.lastPathComponent)
            }

            if verbose && !json {
                print("\(Output.dim)downloading\(Output.reset) \(srcURL.lastPathComponent)")
            }

            if srcIsDir.boolValue {
                try Downloader.ensureLocalRecursive(srcURL) { name, done in
                    if verbose && !json && done {
                        print("  \(Output.green)ready\(Output.reset) \(name)")
                    }
                }
            } else {
                try Downloader.ensureLocal(srcURL)
            }

            let finalDest = destExists && destIsDir.boolValue
                ? destURL.appendingPathComponent(srcURL.lastPathComponent)
                : destURL

            if fm.fileExists(atPath: finalDest.path) {
                if noClobber {
                    if json {
                        try Output.printJSONLine(FileOperationResult(
                            source: srcURL.path, destination: finalDest.path, status: "skipped"))
                    } else if verbose {
                        print("\(Output.yellow)skipped\(Output.reset) \(srcURL.lastPathComponent) (exists)")
                    }
                    continue
                }
                if force {
                    try fm.removeItem(at: finalDest)
                } else {
                    throw FileOperationError.destinationExists(finalDest.path)
                }
            }

            try operation(fm, srcURL, finalDest)

            if json {
                try Output.printJSONLine(FileOperationResult(
                    source: srcURL.path, destination: finalDest.path, status: verb))
            } else if verbose {
                print("\(Output.green)\(verb)\(Output.reset) \(srcURL.lastPathComponent) -> \(finalDest.path)")
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
