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

    static func relativePath(_ url: URL) -> String {
        let resolved = url.resolvingSymlinksInPath().path
        let cwdRaw = FileManager.default.currentDirectoryPath
        let cwdResolved = URL(fileURLWithPath: cwdRaw).resolvingSymlinksInPath().path + "/"
        if resolved.hasPrefix(cwdResolved) {
            return String(resolved.dropFirst(cwdResolved.count))
        }
        let rawCwd = cwdRaw + "/"
        let rawPath = url.path
        if rawPath.hasPrefix(rawCwd) {
            return String(rawPath.dropFirst(rawCwd.count))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if resolved.hasPrefix(home) {
            return "~" + String(resolved.dropFirst(home.count))
        }
        return url.path
    }
}
