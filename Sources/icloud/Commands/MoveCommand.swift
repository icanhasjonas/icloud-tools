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

    @Flag(help: "Warn and continue if a source does not exist.")
    var ignoreMissing = false

    @Flag(help: "With -n: if dst exists and file sizes match, delete source instead of skipping. Never downloads.")
    var pruneSource = false

    @Flag(help: "With -n or -f: on size mismatch, overwrite dst (downloads source if needed). Match-case still follows the other flags.")
    var updateIfMismatch = false

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
        if pruneSource && !noClobber {
            throw ValidationError("--prune-source requires --no-clobber (-n).")
        }
        if updateIfMismatch && !noClobber && !force {
            throw ValidationError("--update-if-mismatch requires --no-clobber (-n) or --force (-f).")
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
            ignoreMissing: ignoreMissing,
            pruneSource: pruneSource,
            updateIfMismatch: updateIfMismatch,
            dryRun: dryRun,
            baselineTimeout: TimeInterval(timeout),
            maxConcurrent: maxConcurrent,
            renderer: renderer
        ) { _, src, dest in
            try FileOperation.safeMove(from: src, to: dest)
        }
        try renderer.finish()
    }
}
