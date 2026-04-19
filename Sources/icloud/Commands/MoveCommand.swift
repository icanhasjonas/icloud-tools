import ArgumentParser
import Foundation

struct MoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mv",
        abstract: "Move files (downloads cloud-only files first).",
        discussion: """
            Downloads dataless files before moving, preventing mmap deadlocks.
            Accepts multiple sources with a directory as the last argument.

            EXAMPLES:
              icloud mv file.pdf ~/Desktop/
              icloud mv -v a.pdf b.pdf dest/
              icloud mv -f old.pdf new.pdf
              icloud mv --dry-run src.pdf dest/
              icloud mv --json a b dest/ | jq -s .        # NDJSON -> array
            """
    )

    @Argument(help: "source... dest")
    var paths: [String]

    @Flag(name: .shortAndLong, help: "Overwrite existing files.")
    var force = false

    @Flag(name: .shortAndLong, help: "Do not overwrite existing files.")
    var noClobber = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    var verbose = false

    @Flag(name: .shortAndLong, help: "Preview without moving.")
    var dryRun = false

    @Flag(help: "NDJSON output.")
    var json = false

    @Option(name: [.customShort("j"), .long], help: "Max concurrent downloads.")
    var maxConcurrent: Int = Downloader.defaultMaxConcurrent

    @Option(name: [.customShort("t"), .long], help: "Base download timeout (sec). Per file: max(base, size_mb * 1.2).")
    var timeout: Int = Int(Downloader.defaultBaselineTimeout)

    func validate() throws {
        guard paths.count >= 2 else {
            throw ValidationError("Usage: icloud mv [-fnvd] source... dest")
        }
    }

    func run() throws {
        let renderer = RendererFactory.make(verbose: verbose, json: json, dryRun: dryRun)
        try FileOperation.execute(
            paths: paths,
            verb: .move,
            allowDirectories: true,
            force: force,
            noClobber: noClobber,
            dryRun: dryRun,
            baselineTimeout: TimeInterval(timeout),
            maxConcurrent: maxConcurrent,
            renderer: renderer
        ) { fm, src, dest in
            try fm.moveItem(at: src, to: dest)
        }
        try renderer.finish()
    }
}
