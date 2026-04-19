import ArgumentParser
import Foundation

struct DownloadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download",
        abstract: "Download iCloud Drive files (materialize dataless files)."
    )

    @Argument(help: "File or directory path(s) to download.")
    var paths: [String]

    @Flag(name: .shortAndLong, help: "Download directories recursively.")
    var recursive = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    var verbose = false

    @Flag(help: "Output as JSON (NDJSON).")
    var json = false

    @Flag(help: "Show what would be downloaded without doing it.")
    var dryRun = false

    @Option(help: "Max seconds to wait per file (default: 300).")
    var timeout: Int = 300

    func run() throws {
        let fm = FileManager.default
        var totalFiles = 0
        var totalBytes: Int64 = 0

        for path in paths {
            let url = PathResolver.resolve(path)
            var isDir: ObjCBool = false

            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
                throw ValidationError("Path does not exist: \(url.path)")
            }

            if isDir.boolValue && !recursive {
                throw ValidationError("\(url.lastPathComponent) is a directory (use -r to download recursively)")
            }

            if isDir.boolValue {
                let result = try Scanner.scan(directory: url, recursive: true) { $0.status == .cloud }

                for file in result.files {
                    let display = PathResolver.relativePath(file.url)
                    let size = Output.humanSize(file.fileSize)

                    if dryRun {
                        if json {
                            try Output.printJSONLine(DownloadResult(
                                path: file.url.path, name: file.name,
                                size: file.fileSize, status: "would-download"))
                        } else {
                            print("  \(Output.dim)would download\(Output.reset) \(display) \(Output.dim)(\(size))\(Output.reset)")
                        }
                    } else {
                        if verbose && !json {
                            print("  \(Output.yellow)downloading\(Output.reset) \(display) \(Output.dim)(\(size))\(Output.reset)")
                        }
                        try Downloader.ensureLocal(file.url, timeout: TimeInterval(timeout))
                        if json {
                            try Output.printJSONLine(DownloadResult(
                                path: file.url.path, name: file.name,
                                size: file.fileSize, status: "downloaded"))
                        } else if verbose {
                            print("  \(Output.green)done\(Output.reset) \(display)")
                        }
                    }
                    totalFiles += 1
                    totalBytes += file.fileSize
                }
            } else {
                let file = try ICloudFile.from(url: url, checkPin: false)
                let display = PathResolver.relativePath(url)
                let size = Output.humanSize(file.fileSize)

                if file.status != .cloud {
                    if json {
                        try Output.printJSONLine(DownloadResult(
                            path: url.path, name: file.name,
                            size: file.fileSize, status: "already-local"))
                    } else if verbose {
                        print("  \(Output.green)local\(Output.reset) \(display)")
                    }
                    continue
                }

                if dryRun {
                    if json {
                        try Output.printJSONLine(DownloadResult(
                            path: url.path, name: file.name,
                            size: file.fileSize, status: "would-download"))
                    } else {
                        print("  \(Output.dim)would download\(Output.reset) \(display) \(Output.dim)(\(size))\(Output.reset)")
                    }
                } else {
                    if verbose && !json {
                        print("  \(Output.yellow)downloading\(Output.reset) \(display) \(Output.dim)(\(size))\(Output.reset)")
                    }
                    try Downloader.ensureLocal(url, timeout: TimeInterval(timeout))
                    if json {
                        try Output.printJSONLine(DownloadResult(
                            path: url.path, name: file.name,
                            size: file.fileSize, status: "downloaded"))
                    } else if verbose {
                        print("  \(Output.green)done\(Output.reset) \(display)")
                    }
                }
                totalFiles += 1
                totalBytes += file.fileSize
            }
        }

        if !json && !dryRun && totalFiles > 0 {
            print("\n\(Output.green)\(totalFiles) file\(totalFiles == 1 ? "" : "s") downloaded\(Output.reset) \(Output.dim)(\(Output.humanSize(totalBytes)))\(Output.reset)")
        } else if !json && dryRun && totalFiles > 0 {
            print("\n\(Output.dim)\(totalFiles) file\(totalFiles == 1 ? "" : "s") to download (\(Output.humanSize(totalBytes)))\(Output.reset)")
        }
    }
}

struct DownloadResult: Encodable {
    let path: String
    let name: String
    let size: Int64
    let status: String
}
