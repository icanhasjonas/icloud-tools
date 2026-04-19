import Foundation

enum DownloadEvent {
    case starting(ICloudFile)
    case done(ICloudFile)
    case wouldDownload(ICloudFile)
    case skipped(ICloudFile)
}

struct Downloader {
    static func ensureLocal(_ url: URL, timeout: TimeInterval = 300, dryRun: Bool = false) throws {
        let file = try ICloudFile.from(url: url, checkPin: false)
        guard file.isUbiquitous && file.status == .cloud else { return }
        if dryRun { return }

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
        dryRun: Bool = false,
        progress: ((DownloadEvent) -> Void)? = nil
    ) throws {
        let file = try ICloudFile.from(url: url, checkPin: false)

        if !file.isDirectory {
            if file.isUbiquitous && file.status == .cloud {
                if dryRun {
                    progress?(.wouldDownload(file))
                } else {
                    progress?(.starting(file))
                    try ensureLocal(url, timeout: timeout)
                    progress?(.done(file))
                }
            } else {
                progress?(.skipped(file))
            }
            return
        }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(ICloudFile.resourceKeys),
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            let child = try ICloudFile.from(url: fileURL, checkPin: false)
            if child.isDirectory { continue }

            if child.isUbiquitous && child.status == .cloud {
                if dryRun {
                    progress?(.wouldDownload(child))
                } else {
                    progress?(.starting(child))
                    try ensureLocal(fileURL, timeout: timeout)
                    progress?(.done(child))
                }
            } else {
                progress?(.skipped(child))
            }
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
