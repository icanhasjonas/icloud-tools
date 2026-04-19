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

    static func pin(_ url: URL) {
        _ = pinValue.withUnsafeBufferPointer { buf in
            setxattr(url.path, xattrName, buf.baseAddress, 1, 0, 0)
        }
    }

    static func unpin(_ url: URL) {
        removexattr(url.path, xattrName, 0)
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

            if isDir.boolValue || (recursive && isDir.boolValue) {
                let files = try collectFiles(url: url, recursive: recursive, tagFilter: tagFilter)
                for file in files {
                    totalCount += try processFile(
                        file.url, pinning: pinning, dryRun: dryRun,
                        verbose: verbose, json: json, verb: verb,
                        wouldVerb: wouldVerb, rebase: rebase)
                }
            } else {
                if let tagFilter {
                    let tags = try url.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
                    guard tagFilter.matches(tags) else { continue }
                }
                totalCount += try processFile(
                    url, pinning: pinning, dryRun: dryRun,
                    verbose: verbose, json: json, verb: verb,
                    wouldVerb: wouldVerb, rebase: rebase)
            }
        }

        if !json && totalCount > 0 {
            let label = dryRun ? "\(Output.dim)\(totalCount) file\(totalCount == 1 ? "" : "s") to \(pinning ? "pin" : "unpin")\(Output.reset)"
                : "\(Output.green)\(totalCount) file\(totalCount == 1 ? "" : "s") \(verb)\(Output.reset)"
            print("\n\(label)")
        }
    }

    private static func processFile(
        _ url: URL,
        pinning: Bool,
        dryRun: Bool,
        verbose: Bool,
        json: Bool,
        verb: String,
        wouldVerb: String,
        rebase: PathResolver.Rebase
    ) throws -> Int {
        let alreadyPinned = isPinned(url)
        if pinning && alreadyPinned {
            if verbose && !json {
                print("  \(Output.dim)already pinned\(Output.reset) \(PathResolver.relativePath(url, rebase: rebase))")
            }
            return 0
        }
        if !pinning && !alreadyPinned {
            if verbose && !json {
                print("  \(Output.dim)not pinned\(Output.reset) \(PathResolver.relativePath(url, rebase: rebase))")
            }
            return 0
        }

        let display = PathResolver.relativePath(url, rebase: rebase)

        if dryRun {
            if json {
                try Output.printJSONLine(PinResult(path: url.path, name: url.lastPathComponent, status: wouldVerb))
            } else {
                print("  \(Output.dim)\(wouldVerb)\(Output.reset) \(display)")
            }
        } else {
            if pinning { pin(url) } else { unpin(url) }
            if json {
                try Output.printJSONLine(PinResult(path: url.path, name: url.lastPathComponent, status: verb))
            } else if verbose {
                print("  \(Output.green)\(verb)\(Output.reset) \(display)")
            }
        }
        return 1
    }

    private static func collectFiles(
        url: URL,
        recursive: Bool,
        tagFilter: TagFilter?
    ) throws -> [ICloudFile] {
        var keys = ICloudFile.resourceKeys
        keys.insert(.tagNamesKey)

        let fm = FileManager.default
        var files: [ICloudFile] = []

        if recursive {
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { return [] }

            for case let fileURL as URL in enumerator {
                let file = try ICloudFile.from(url: fileURL, checkPin: true)
                if file.isDirectory { continue }

                if let tagFilter {
                    let tags = try fileURL.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
                    guard tagFilter.matches(tags) else { continue }
                }
                files.append(file)
            }
        } else {
            let contents = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
            for fileURL in contents {
                let file = try ICloudFile.from(url: fileURL, checkPin: true)
                if let tagFilter {
                    let tags = try fileURL.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
                    guard tagFilter.matches(tags) else { continue }
                }
                files.append(file)
            }
        }

        return files
    }
}

enum PinError: LocalizedError {
    case noPaths
    case notFound(String)
    case directoryRequiresRecursive(String)

    var errorDescription: String? {
        switch self {
        case .noPaths:
            return "Provide paths or use --from-tag to select files."
        case .notFound(let path):
            return "Path does not exist: \(path)"
        case .directoryRequiresRecursive(let name):
            return "\(name) is a directory (use -r)"
        }
    }
}
