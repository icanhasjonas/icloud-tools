import Foundation

struct Downloader {
    static func ensureLocal(_ url: URL, timeout: TimeInterval = 300) throws {
        let file = try ICloudFile.from(url: url, checkPin: false)
        guard file.isUbiquitous && file.status == .cloud else { return }

        try FileManager.default.startDownloadingUbiquitousItem(at: url)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let fresh = URL(fileURLWithPath: url.path)
            let values = try fresh.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey,
            ])

            let status = values.ubiquitousItemDownloadingStatus
            if status == .current || status == .downloaded {
                return
            }

            Thread.sleep(forTimeInterval: 0.5)
        }

        throw DownloadError.timeout(url.lastPathComponent)
    }

    static func ensureLocalRecursive(
        _ url: URL,
        timeout: TimeInterval = 300,
        progress: ((String, Bool) -> Void)? = nil
    ) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw DownloadError.notFound(url.path)
        }

        if !isDir.boolValue {
            progress?(url.lastPathComponent, false)
            try ensureLocal(url, timeout: timeout)
            progress?(url.lastPathComponent, true)
            return
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isUbiquitousItemKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true { continue }

            progress?(fileURL.lastPathComponent, false)
            try ensureLocal(fileURL, timeout: timeout)
            progress?(fileURL.lastPathComponent, true)
        }
    }
}

enum DownloadError: LocalizedError {
    case timeout(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .timeout(let name): return "Download timed out: \(name)"
        case .notFound(let path): return "File not found: \(path)"
        }
    }
}
