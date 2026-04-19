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
              icloud mv -fn old.pdf new.pdf
              icloud mv --json src.pdf dest/
            """
    )

    @Argument(parsing: .allUnrecognized, help: "source... dest")
    var paths: [String]

    @Flag(name: .shortAndLong, help: "Overwrite existing files.")
    var force = false

    @Flag(name: .shortAndLong, help: "Do not overwrite existing files.")
    var noClobber = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    var verbose = false

    @Flag(help: "NDJSON output.")
    var json = false

    func validate() throws {
        guard paths.count >= 2 else {
            throw ValidationError("Usage: icloud mv [-fnv] source... dest")
        }
    }

    func run() throws {
        try FileOperation.execute(
            paths: paths,
            verb: "moved",
            allowDirectories: true,
            force: force,
            noClobber: noClobber,
            verbose: verbose,
            json: json
        ) { fm, src, dest in
            try fm.moveItem(at: src, to: dest)
        }
    }
}
