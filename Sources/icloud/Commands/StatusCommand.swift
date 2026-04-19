import ArgumentParser
import Foundation

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show iCloud status for files."
    )

    @Argument(help: "Path to check (default: cwd if iCloud, otherwise iCloud Drive root).")
    var path: String?

    @Flag(name: .shortAndLong, help: "Recurse into subdirectories.")
    var recursive = false

    @Flag(help: "Only show cloud-only (dataless) files.")
    var cloud = false

    @Flag(help: "Only show local files.")
    var local = false

    @Flag(help: "Only show actively downloading files.")
    var downloading = false

    @Flag(name: .shortAndLong, help: "Show resolved paths and debug info.")
    var verbose = false

    @Option(help: "Sort by: name, size, status.")
    var sort: SortField = .name

    func run() throws {
        let url = PathResolver.resolve(path)
        let resolved = url.resolvingSymlinksInPath()

        if verbose {
            print("\(Output.dim)resolved: \(url.path)\(Output.reset)")
            if resolved.path != url.path {
                print("\(Output.dim)symlink:  \(resolved.path)\(Output.reset)")
            }
            let isICloud = resolved.path.hasPrefix(PathResolver.mobileDocuments)
            print("\(Output.dim)icloud:   \(isICloud)\(Output.reset)")
            print()
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw ValidationError("Path does not exist: \(url.path)")
        }

        if !PathResolver.isUnderMobileDocuments(url) {
            print("\(Output.yellow)Not an iCloud Drive path:\(Output.reset) \(url.path)")
            print("\(Output.dim)iCloud Drive: \(PathResolver.iCloudDriveRoot.path)\(Output.reset)")
            return
        }

        if !isDir.boolValue {
            let file = try ICloudFile.from(url: url)
            Output.printFileTable([file])
            return
        }

        let filter: ((ICloudFile) -> Bool)? = buildFilter()

        let result = try Scanner.scan(
            directory: url,
            recursive: recursive,
            filter: filter
        )

        if result.files.isEmpty {
            print("No files found.")
            return
        }

        let sorted = sortFiles(result.files)
        Output.printFileTable(sorted)
        Output.printSummary(result)
    }

    private func buildFilter() -> ((ICloudFile) -> Bool)? {
        if !cloud && !local && !downloading { return nil }

        return { file in
            if cloud && file.status == .cloud { return true }
            if local && file.status == .local { return true }
            if downloading && file.status == .downloading { return true }
            return false
        }
    }

    private func sortFiles(_ files: [ICloudFile]) -> [ICloudFile] {
        switch sort {
        case .name:
            return files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            return files.sorted { $0.fileSize > $1.fileSize }
        case .status:
            return files.sorted { $0.status.rawValue < $1.status.rawValue }
        }
    }
}

enum SortField: String, ExpressibleByArgument, Sendable {
    case name, size, status
}
