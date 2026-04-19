import ArgumentParser
import Foundation

struct DownloadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download",
        abstract: "Download (materialize) cloud-only files.",
        discussion: """
            Triggers iCloud download and waits for completion.
            Use -r for directories, --dry-run to preview.

            EXAMPLES:
              icloud download file.pdf
              icloud download -rv Documents/
              icloud download --dry-run -r .
              icloud download --json --timeout 60 big.zip
              icloud download --json -r dir/ | jq -s .    # NDJSON -> array
            """
    )

    @Argument(help: "path...")
    var paths: [String]

    @Flag(name: .shortAndLong, help: "Download directories recursively.")
    var recursive = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    var verbose = false

    @Flag(help: "NDJSON output.")
    var json = false

    @Flag(name: .shortAndLong, help: "Preview without downloading.")
    var dryRun = false

    @Option(name: .shortAndLong, help: "Seconds to wait per file.")
    var timeout: Int = 300

    func validate() throws {
        guard !paths.isEmpty else {
            throw ValidationError("Usage: icloud download [-rv] [--dry-run] path...")
        }
    }

    func run() throws {
        let fm = FileManager.default
        var allFiles: [ICloudFile] = []

        for path in paths {
            let url = PathResolver.resolve(path)
            var isDir: ObjCBool = false

            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
                throw ValidationError("Path does not exist: \(url.path)")
            }

            if isDir.boolValue && !recursive {
                throw ValidationError("\(url.lastPathComponent) is a directory (use -r)")
            }

            allFiles.append(contentsOf: try Downloader.enumerate(url))
        }

        let pending = allFiles.filter { Downloader.needsDownload($0) }

        if dryRun {
            for f in pending {
                let display = PathResolver.relativePath(f.url)
                let size = Output.humanSize(f.fileSize)
                if json {
                    try Output.printJSONLine(DownloadResult(
                        path: f.url.path, name: f.name,
                        size: f.fileSize, status: "would-download"))
                } else {
                    print("\(display) \(Output.dim)(\(size))\(Output.reset) \(Output.dim)would download\(Output.reset)")
                }
            }
            if !json && !pending.isEmpty {
                let total = pending.reduce(Int64(0)) { $0 + $1.fileSize }
                print("\n\(Output.dim)\(pending.count) file\(pending.count == 1 ? "" : "s") to download (\(Output.humanSize(total)))\(Output.reset)")
            }
            return
        }

        var doneCount = 0
        var doneBytes: Int64 = 0

        try Downloader.ensureLocalBatch(allFiles, timeout: TimeInterval(timeout), dryRun: false) { event in
            switch event {
            case .downloadStart(let url, let size):
                if verbose && !json {
                    print("\(PathResolver.relativePath(url)) \(Output.dim)(\(Output.humanSize(size)))\(Output.reset)")
                    print("  \(Output.yellow)downloading...\(Output.reset)")
                }
            case .downloadDone(let url, let size, let elapsed):
                doneCount += 1
                doneBytes += size
                if json {
                    try Output.printJSONLine(DownloadResult(
                        path: url.path, name: url.lastPathComponent,
                        size: size, status: "downloaded"))
                } else if verbose {
                    print("  \(Output.green)downloaded\(Output.reset) \(Output.dim)(\(String(format: "%.1fs", elapsed)))\(Output.reset)")
                } else {
                    print("\(Output.green)✓\(Output.reset) \(PathResolver.relativePath(url)) \(Output.dim)(\(Output.humanSize(size)), \(String(format: "%.1fs", elapsed)))\(Output.reset)")
                }
            case .downloadFail(let url, let error):
                if json {
                    try Output.printJSONLine(DownloadResult(
                        path: url.path, name: url.lastPathComponent,
                        size: 0, status: "failed"))
                } else {
                    print("\(Output.red)✗\(Output.reset) \(PathResolver.relativePath(url)): \(error.localizedDescription)")
                }
            default:
                break
            }
        }

        if !json && doneCount > 0 {
            print("\n\(Output.green)\(doneCount) file\(doneCount == 1 ? "" : "s") downloaded\(Output.reset) \(Output.dim)(\(Output.humanSize(doneBytes)))\(Output.reset)")
        }
    }
}

struct DownloadResult: Encodable {
    let path: String
    let name: String
    let size: Int64
    let status: String
}
