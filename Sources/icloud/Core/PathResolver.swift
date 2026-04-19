import Foundation

struct PathResolver {
    static let iCloudDriveRoot: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    }()

    static let mobileDocuments: String =
        iCloudDriveRoot.deletingLastPathComponent().path

    private static let cwdRaw: String =
        FileManager.default.currentDirectoryPath

    private static let cwdResolved: String =
        URL(fileURLWithPath: cwdRaw).resolvingSymlinksInPath().path

    private static let homePath: String =
        FileManager.default.homeDirectoryForCurrentUser.path

    static func resolveDefault() -> URL {
        let cwd = URL(fileURLWithPath: cwdRaw).standardized
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

    struct Rebase {
        let resolved: String
        let original: String

        init(_ url: URL) {
            self.resolved = url.resolvingSymlinksInPath().path
            self.original = url.path
        }
    }

    static func relativePath(_ url: URL, rebase: Rebase? = nil) -> String {
        var rawPath = url.path
        if let rebase, rawPath.hasPrefix(rebase.resolved) {
            rawPath = rebase.original + String(rawPath.dropFirst(rebase.resolved.count))
        }
        let cwdPrefix = cwdRaw + "/"
        if rawPath.hasPrefix(cwdPrefix) {
            return String(rawPath.dropFirst(cwdPrefix.count))
        }
        let cwdResolvedPrefix = cwdResolved + "/"
        if rawPath.hasPrefix(cwdResolvedPrefix) {
            return String(rawPath.dropFirst(cwdResolvedPrefix.count))
        }
        let homePrefix = homePath + "/"
        if rawPath.hasPrefix(homePrefix) {
            return "~/" + String(rawPath.dropFirst(homePrefix.count))
        }
        return rawPath
    }
}
