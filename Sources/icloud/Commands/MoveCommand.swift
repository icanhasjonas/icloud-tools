import ArgumentParser
import Foundation

struct MoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mv",
        abstract: "Move iCloud Drive files (downloads dataless files first)."
    )

    @Argument(help: "Source path(s) followed by destination.")
    var paths: [String]

    @Flag(name: .shortAndLong, help: "Force overwrite.")
    var force = false

    @Flag(name: .shortAndLong, help: "Do not overwrite existing files.")
    var noClobber = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    var verbose = false

    func validate() throws {
        guard paths.count >= 2 else {
            throw ValidationError("Usage: icloud mv <source...> <destination>")
        }
    }

    func run() throws {
        let fm = FileManager.default
        let sources = paths.dropLast()
        let destURL = PathResolver.resolve(paths.last!)
        var destIsDir: ObjCBool = false
        let destExists = fm.fileExists(atPath: destURL.path, isDirectory: &destIsDir)

        if sources.count > 1 && (!destExists || !destIsDir.boolValue) {
            throw ValidationError("Destination must be a directory when moving multiple files.")
        }

        for source in sources {
            let srcURL = PathResolver.resolve(source)

            guard fm.fileExists(atPath: srcURL.path) else {
                throw ValidationError("Source not found: \(srcURL.path)")
            }

            var srcIsDir: ObjCBool = false
            fm.fileExists(atPath: srcURL.path, isDirectory: &srcIsDir)

            if verbose {
                print("\(Output.dim)downloading\(Output.reset) \(srcURL.lastPathComponent)")
            }

            if srcIsDir.boolValue {
                try Downloader.ensureLocalRecursive(srcURL) { name, done in
                    if verbose && done {
                        print("  \(Output.green)ready\(Output.reset) \(name)")
                    }
                }
            } else {
                try Downloader.ensureLocal(srcURL)
            }

            let finalDest: URL
            if destExists && destIsDir.boolValue {
                finalDest = destURL.appendingPathComponent(srcURL.lastPathComponent)
            } else {
                finalDest = destURL
            }

            if fm.fileExists(atPath: finalDest.path) {
                if noClobber {
                    if verbose {
                        print("\(Output.yellow)skipped\(Output.reset) \(srcURL.lastPathComponent) (exists)")
                    }
                    continue
                }
                if force {
                    try fm.removeItem(at: finalDest)
                } else {
                    throw ValidationError("Destination exists: \(finalDest.path) (use -f to overwrite)")
                }
            }

            try fm.moveItem(at: srcURL, to: finalDest)

            if verbose {
                print("\(Output.green)moved\(Output.reset) \(srcURL.lastPathComponent) -> \(finalDest.path)")
            }
        }
    }
}
