import Foundation

struct PathResolver {
    static let iCloudDriveRoot: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    }()

    static let mobileDocuments: String =
        iCloudDriveRoot.deletingLastPathComponent().path

    static func resolveDefault() -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .standardized
        if isUnderMobileDocuments(cwd) {
            return cwd
        }
        return iCloudDriveRoot
    }

    static func resolve(_ path: String?) -> URL {
        guard let path else { return resolveDefault() }

        if path.hasPrefix("icloud:") {
            let relative = String(path.dropFirst("icloud:".count))
            return iCloudDriveRoot.appendingPathComponent(relative).standardized
        }

        let expanded = NSString(string: path).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardized
    }

    static func isUnderMobileDocuments(_ url: URL) -> Bool {
        url.resolvingSymlinksInPath().path.hasPrefix(mobileDocuments)
    }
}
