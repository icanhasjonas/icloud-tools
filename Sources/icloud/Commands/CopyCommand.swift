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
              icloud cp -fn a.pdf b.pdf dest/
              icloud cp --json src.pdf dest/
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

    @Flag(help: "NDJSON output.")
    var json = false

    func validate() throws {
        guard paths.count >= 2 else {
            throw ValidationError("Usage: icloud cp [-rfnv] source... dest")
        }
    }

    func run() throws {
        try FileOperation.execute(
            paths: paths,
            verb: "copied",
            allowDirectories: recursive,
            force: force,
            noClobber: noClobber,
            verbose: verbose,
            json: json
        ) { fm, src, dest in
            try fm.copyItem(at: src, to: dest)
        }
    }
}
