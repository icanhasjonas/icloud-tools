import ArgumentParser
import Foundation

struct CopyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cp",
        abstract: "Copy iCloud Drive files (downloads dataless files first)."
    )

    @Argument(help: "Source path(s) followed by destination.")
    var paths: [String]

    @Flag(name: .shortAndLong, help: "Copy directories recursively.")
    var recursive = false

    @Flag(name: .shortAndLong, help: "Force overwrite.")
    var force = false

    @Flag(name: .shortAndLong, help: "Do not overwrite existing files.")
    var noClobber = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    var verbose = false

    @Flag(help: "Output as JSON.")
    var json = false

    func validate() throws {
        guard paths.count >= 2 else {
            throw ValidationError("Usage: icloud cp <source...> <destination>")
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
