import Foundation

struct TagFilter {
    let anyOf: [[String]]

    func matches(_ tags: [String]) -> Bool {
        let lowered = Set(tags.map { $0.lowercased() })
        return anyOf.contains { group in
            group.allSatisfy { lowered.contains($0) }
        }
    }

    static func parse(_ expressions: [String]) -> TagFilter {
        let groups = expressions.map { expr in
            expr.split(separator: "+").map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        }
        return TagFilter(anyOf: groups)
    }
}

struct PinResult: Encodable {
    let path: String
    let name: String
    let status: String
}

struct Pinner {
    static let xattrName = "com.apple.fileprovider.pinned#PX"
    static let pinValue: [UInt8] = [0x31]

    static func pin(_ url: URL) throws {
        let result = pinValue.withUnsafeBufferPointer { buf in
            setxattr(url.path, xattrName, buf.baseAddress, 1, 0, 0)
        }
        if result == -1 {
            throw PinError.xattrFailed("pin", url.lastPathComponent, errno)
        }
    }

    static func unpin(_ url: URL) throws {
        let result = removexattr(url.path, xattrName, 0)
        if result == -1 && errno != ENOATTR {
            throw PinError.xattrFailed("unpin", url.lastPathComponent, errno)
        }
    }

    static func isPinned(_ url: URL) -> Bool {
        getxattr(url.path, xattrName, nil, 0, 0, 0) >= 0
    }

    static func execute(
        paths: [String],
        recursive: Bool,
        fromTags: [String],
        pinning: Bool,
        dryRun: Bool,
        verbose: Bool,
        json: Bool
    ) throws {
        let verb = pinning ? "pinned" : "unpinned"
        let wouldVerb = pinning ? "would pin" : "would unpin"
        var totalCount = 0

        let tagFilter = fromTags.isEmpty ? nil : TagFilter.parse(fromTags)

        let targets: [URL]
        if paths.isEmpty && tagFilter != nil {
            targets = [PathResolver.resolveDefault()]
        } else if paths.isEmpty {
            throw PinError.noPaths
        } else {
            targets = paths.map { PathResolver.resolve($0) }
        }

        for url in targets {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
                throw PinError.notFound(url.path)
            }

            if isDir.boolValue && !recursive && tagFilter == nil {
                throw PinError.directoryRequiresRecursive(url.lastPathComponent)
            }

            let rebase = PathResolver.Rebase(url)

            if isDir.boolValue {
                let filter: ((ICloudFile) -> Bool)? = tagFilter.map { tf in
                    { file in tf.matches(file.tagNames) }
                }
                let result = try Scanner.scan(directory: url, recursive: recursive, filter: filter)
                for file in result.files {
                    totalCount += try processFile(
                        file, pinning: pinning, dryRun: dryRun,
                        verbose: verbose, json: json, verb: verb,
                        wouldVerb: wouldVerb, rebase: rebase)
                }
            } else {
                let file = try ICloudFile.from(url: url)
                if let tagFilter, !tagFilter.matches(file.tagNames) { continue }
                totalCount += try processFile(
                    file, pinning: pinning, dryRun: dryRun,
                    verbose: verbose, json: json, verb: verb,
                    wouldVerb: wouldVerb, rebase: rebase)
            }
        }

        if !json && totalCount > 0 {
            let label = dryRun ? "\(Output.dim)\(totalCount) file\(totalCount == 1 ? "" : "s") to \(pinning ? "pin" : "unpin")\(Output.reset)"
                : "\(Output.green)\(totalCount) file\(totalCount == 1 ? "" : "s") \(verb)\(Output.reset)"
            print("\n\(label)")
        } else if !json && totalCount == 0 {
            let reason = tagFilter != nil ? "matched tag filter" : "to \(pinning ? "pin" : "unpin")"
            print("\(Output.dim)No files \(reason).\(Output.reset)")
        }
    }

    private static func processFile(
        _ file: ICloudFile,
        pinning: Bool,
        dryRun: Bool,
        verbose: Bool,
        json: Bool,
        verb: String,
        wouldVerb: String,
        rebase: PathResolver.Rebase
    ) throws -> Int {
        if pinning && file.isPinned {
            if verbose && !json {
                print("  \(Output.dim)already pinned\(Output.reset) \(PathResolver.relativePath(file.url, rebase: rebase))")
            }
            return 0
        }
        if !pinning && !file.isPinned {
            if verbose && !json {
                print("  \(Output.dim)not pinned\(Output.reset) \(PathResolver.relativePath(file.url, rebase: rebase))")
            }
            return 0
        }

        let display = PathResolver.relativePath(file.url, rebase: rebase)

        if dryRun {
            if json {
                try Output.printJSONLine(PinResult(path: file.url.path, name: file.name, status: wouldVerb))
            } else {
                print("  \(Output.dim)\(wouldVerb)\(Output.reset) \(display)")
            }
        } else {
            if pinning { try pin(file.url) } else { try unpin(file.url) }
            if json {
                try Output.printJSONLine(PinResult(path: file.url.path, name: file.name, status: verb))
            } else if verbose {
                print("  \(Output.green)\(verb)\(Output.reset) \(display)")
            }
        }
        return 1
    }
}

enum PinError: LocalizedError {
    case noPaths
    case notFound(String)
    case directoryRequiresRecursive(String)
    case xattrFailed(String, String, Int32)

    var errorDescription: String? {
        switch self {
        case .noPaths:
            return "Provide paths or use --from-tag to select files."
        case .notFound(let path):
            return "Path does not exist: \(path)"
        case .directoryRequiresRecursive(let name):
            return "\(name) is a directory (use -r)"
        case .xattrFailed(let op, let name, let err):
            return "Failed to \(op) \(name): \(String(cString: strerror(err)))"
        }
    }
}
