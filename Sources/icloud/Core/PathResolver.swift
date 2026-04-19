import Foundation

struct PathResolver {
    static let iCloudDriveRoot: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    }()

    static func resolve(_ path: String?) -> URL {
        guard let path else { return iCloudDriveRoot }

        if path.hasPrefix("icloud:") {
            let relative = String(path.dropFirst("icloud:".count))
            return iCloudDriveRoot.appendingPathComponent(relative)
        }

        let expanded = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)

        if url.path.hasPrefix("/") {
            return url
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
    }

    static func isUnderMobileDocuments(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let mobileDocuments = home.appendingPathComponent("Library/Mobile Documents").path
        return url.path.hasPrefix(mobileDocuments)
    }
}
