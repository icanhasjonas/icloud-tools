import ArgumentParser
import Foundation

struct PinCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pin",
        abstract: "Pin files to keep them downloaded.",
        discussion: """
            Prevents automatic eviction on disk pressure.
            Equivalent to Finder's "Keep Downloaded" option.

            EXAMPLES:
              icloud pin important.pdf
              icloud pin -r Documents/
              icloud pin --from-tag Green
              icloud pin --from-tag Green+Important -r .
              icloud pin --from-tag Red --from-tag Blue
              icloud pin --dry-run --from-tag Green
            """
    )

    @Argument(help: "path...")
    var paths: [String] = []

    @Flag(name: .shortAndLong, help: "Pin directories recursively.")
    var recursive = false

    @Option(name: .long, help: "Select by Finder tag. Repeat for any, + for all.")
    var fromTag: [String] = []

    @Flag(name: .shortAndLong, help: "Verbose output.")
    var verbose = false

    @Flag(name: .shortAndLong, help: "Preview without pinning.")
    var dryRun = false

    @Flag(help: "NDJSON output.")
    var json = false

    func validate() throws {
        if paths.isEmpty && fromTag.isEmpty {
            throw ValidationError("Usage: icloud pin [-rv] [--from-tag TAG] path...")
        }
    }

    func run() throws {
        try Pinner.execute(
            paths: paths,
            recursive: recursive || !fromTag.isEmpty,
            fromTags: fromTag,
            pinning: true,
            dryRun: dryRun,
            verbose: verbose,
            json: json
        )
    }
}
