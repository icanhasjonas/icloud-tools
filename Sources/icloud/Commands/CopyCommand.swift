import ArgumentParser
import Foundation

struct CopyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cp",
        abstract: "Copy files (downloads cloud-only files first).",
        discussion: """
            Downloads dataless files before copying, preventing mmap deadlocks.
            Use -r for directories. Accepts multiple sources with a directory as
            the last argument.

            EXAMPLES:
              icloud cp file.pdf ~/Desktop/
              icloud cp -rv Documents/ ~/backup/
              icloud cp -f a.pdf b.pdf dest/
              icloud cp --dry-run src.pdf dest/
              icloud cp --json -r dir/ dest/ | jq -s .    # NDJSON -> array
            """
    )

    @Argument(help: "source... dest")
    var paths: [String]

    @Flag(name: .shortAndLong, help: "Copy directories recursively.")
    var recursive = false

    @Flag(name: .shortAndLong, help: "Overwrite existing files.")
    var force = false

    @Flag(name: .shortAndLong, help: "Do not overwrite existing files.")
    var noClobber = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    var verbose = false

    @Flag(name: .shortAndLong, help: "Preview without copying.")
    var dryRun = false

    @Flag(help: "Warn and continue if a source does not exist.")
    var ignoreMissing = false

    @Flag(help: "NDJSON output.")
    var json = false

    @Option(name: [.customShort("j"), .long], help: "Max concurrent downloads.")
    var maxConcurrent: Int = Downloader.defaultMaxConcurrent

    @Option(name: [.customShort("t"), .long], help: "Base download timeout (sec). Per file: max(base, size_mb * 1.2).")
    var timeout: Int = Int(Downloader.defaultBaselineTimeout)

    func validate() throws {
        guard paths.count >= 2 else {
            throw ValidationError("Usage: icloud cp [-rfnvd] source... dest")
        }
    }

    func run() throws {
        let renderer = RendererFactory.make(verbose: verbose, json: json, dryRun: dryRun)
        try FileOperation.execute(
            paths: paths,
            verb: .copy,
            allowDirectories: recursive,
            force: force,
            noClobber: noClobber,
            ignoreMissing: ignoreMissing,
            dryRun: dryRun,
            baselineTimeout: TimeInterval(timeout),
            maxConcurrent: maxConcurrent,
            renderer: renderer
        ) { _, src, dest in
            try FileOperation.safeCopy(from: src, to: dest)
        }
        try renderer.finish()
    }
}
