import ArgumentParser
import Foundation

struct UnpinCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unpin",
        abstract: "Unpin files to allow automatic eviction.",
        discussion: """
            Removes the "Keep Downloaded" flag. The system may
            evict the file on disk pressure.

            EXAMPLES:
              icloud unpin file.pdf
              icloud unpin -r Documents/
              icloud unpin --from-tag Green
              icloud unpin --dry-run -r .
              icloud unpin --json -r dir/ | jq -s .       # NDJSON -> array
            """
    )

    @Argument(help: "path...")
    var paths: [String] = []

    @Flag(name: .shortAndLong, help: "Unpin directories recursively.")
    var recursive = false

    @Option(name: .long, help: "Select by Finder tag. Repeat for any, + for all.")
    var fromTag: [String] = []

    @Flag(name: .shortAndLong, help: "Verbose output.")
    var verbose = false

    @Flag(name: .shortAndLong, help: "Preview without unpinning.")
    var dryRun = false

    @Flag(help: "NDJSON output.")
    var json = false

    func validate() throws {
        if paths.isEmpty && fromTag.isEmpty {
            throw ValidationError("Usage: icloud unpin [-rv] [--from-tag TAG] path...")
        }
    }

    func run() throws {
        try Pinner.execute(
            paths: paths,
            recursive: recursive || !fromTag.isEmpty,
            fromTags: fromTag,
            pinning: false,
            dryRun: dryRun,
            verbose: verbose,
            json: json
        )
    }
}
