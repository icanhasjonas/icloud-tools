import ArgumentParser
import Foundation

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show iCloud status for files."
    )

    @Argument(help: "Path to check (default: iCloud Drive root).")
    var path: String?

    @Flag(name: .shortAndLong, help: "Recurse into subdirectories.")
    var recursive = false

    @Flag(help: "Only show cloud-only (dataless) files.")
    var cloud = false

    @Flag(help: "Only show local files.")
    var local = false

    @Flag(help: "Only show actively downloading files.")
    var downloading = false

    @Option(help: "Sort by: name, size, status.")
    var sort: SortField = .name

    func run() throws {
        let url = PathResolver.resolve(path)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("Path does not exist: \(url.path)")
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
            if downloading && (file.status == .downloading) { return true }
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
