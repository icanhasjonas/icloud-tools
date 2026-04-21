import ArgumentParser
import Foundation

struct EvictCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "evict",
        abstract: "Evict local copies to free disk space.",
        discussion: """
            Makes files cloud-only by removing the local copy.
            Pinned files are skipped (unpin first). Use --dry-run to preview.

            EXAMPLES:
              icloud evict file.pdf
              icloud evict -rv old-projects/
              icloud evict --dry-run -r .
              icloud evict --json big.zip
              icloud evict --json -r dir/ | jq -s .       # NDJSON -> array
            """
    )

    @Argument(help: "path...")
    var paths: [String]

    @Flag(name: .shortAndLong, help: "Evict directories recursively.")
    var recursive = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    var verbose = false

    @Flag(help: "NDJSON output.")
    var json = false

    @Flag(name: .shortAndLong, help: "Preview without evicting.")
    var dryRun = false

    func validate() throws {
        guard !paths.isEmpty else {
            throw ValidationError("Usage: icloud evict [-rv] [--dry-run] path...")
        }
    }

    func run() throws {
        let fm = FileManager.default
        var totalFiles = 0
        var totalFreed: Int64 = 0
        var failedCount = 0

        for path in paths {
            let url = PathResolver.resolve(path)
            var isDir: ObjCBool = false

            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
                throw ValidationError("Path does not exist: \(url.path)")
            }

            if isDir.boolValue && !recursive {
                throw ValidationError("\(url.lastPathComponent) is a directory (use -r)")
            }

            let rebase = PathResolver.Rebase(url)
            let filesToEvict: [ICloudFile]
            if isDir.boolValue {
                let result = try Scanner.scan(directory: url, recursive: true) {
                    $0.status == .local && $0.isUbiquitous && !$0.isPinned
                }
                filesToEvict = result.files
            } else {
                let file = try ICloudFile.from(url: url)
                if file.status != .local || !file.isUbiquitous {
                    if json {
                        try Output.printJSONLine(EvictResult(
                            path: url.path, name: file.name,
                            freed: 0, status: "already-cloud"))
                    } else if verbose {
                        print("  \(Output.dim)already cloud\(Output.reset) \(PathResolver.relativePath(url))")
                    }
                    continue
                }
                if file.isPinned {
                    if json {
                        try Output.printJSONLine(EvictResult(
                            path: url.path, name: file.name,
                            freed: 0, status: "pinned"))
                    } else if verbose {
                        print("  \(Output.cyan)pinned\(Output.reset) \(PathResolver.relativePath(url)) (unpin first)")
                    }
                    continue
                }
                filesToEvict = [file]
            }

            for file in filesToEvict {
                let display = PathResolver.relativePath(file.url, rebase: rebase)
                let size = Output.humanSize(file.allocatedSize)

                if dryRun {
                    if json {
                        try Output.printJSONLine(EvictResult(
                            path: file.url.path, name: file.name,
                            freed: file.allocatedSize, status: "would-evict"))
                    } else {
                        print("  \(Output.dim)would evict\(Output.reset) \(display) \(Output.dim)(\(size))\(Output.reset)")
                    }
                } else {
                    do {
                        try fm.evictUbiquitousItem(at: file.url)
                    } catch {
                        failedCount += 1
                        if json {
                            try Output.printJSONLine(EvictResult(
                                path: file.url.path, name: file.name,
                                freed: 0, status: "failed",
                                error: error.localizedDescription))
                        } else {
                            print("  \(Output.red)failed\(Output.reset) \(display): \(error.localizedDescription)")
                        }
                        continue
                    }
                    if json {
                        try Output.printJSONLine(EvictResult(
                            path: file.url.path, name: file.name,
                            freed: file.allocatedSize, status: "evicted"))
                    } else if verbose {
                        print("  \(Output.green)evicted\(Output.reset) \(display) \(Output.dim)(\(size))\(Output.reset)")
                    }
                }
                totalFiles += 1
                totalFreed += file.allocatedSize
            }
        }

        if !json && !dryRun && totalFiles > 0 {
            print("\n\(Output.green)\(totalFiles) file\(totalFiles == 1 ? "" : "s") evicted\(Output.reset) \(Output.dim)(freed \(Output.humanSize(totalFreed)))\(Output.reset)")
        } else if !json && dryRun && totalFiles > 0 {
            print("\n\(Output.dim)\(totalFiles) file\(totalFiles == 1 ? "" : "s") to evict (would free \(Output.humanSize(totalFreed)))\(Output.reset)")
        } else if !json && totalFiles == 0 && failedCount == 0 {
            print("\(Output.dim)Nothing to evict.\(Output.reset)")
        }

        if failedCount > 0 {
            throw EvictError.partialFailure(count: failedCount)
        }
    }
}

enum EvictError: LocalizedError {
    case partialFailure(count: Int)

    var errorDescription: String? {
        switch self {
        case .partialFailure(let n):
            return "\(n) file\(n == 1 ? "" : "s") failed to evict (see above)."
        }
    }
}

struct EvictResult: Encodable {
    let path: String
    let name: String
    let freed: Int64
    let status: String
    var error: String? = nil
}
