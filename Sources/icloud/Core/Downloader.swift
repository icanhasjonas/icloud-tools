import Foundation

enum DownloadEvent {
    case starting(ICloudFile)
    case done(ICloudFile)
    case wouldDownload(ICloudFile)
    case skipped(ICloudFile)
}

struct Downloader {
    static func ensureLocal(_ file: ICloudFile, timeout: TimeInterval = 300, dryRun: Bool = false) throws {
        guard file.isUbiquitous && file.status == .cloud else { return }
        if dryRun { return }

        try FileManager.default.startDownloadingUbiquitousItem(at: file.url)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let fresh = URL(fileURLWithPath: file.url.path)
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

        throw DownloadError.timeout(file.url.lastPathComponent)
    }

    static func ensureLocal(_ url: URL, timeout: TimeInterval = 300, dryRun: Bool = false) throws {
        let file = try ICloudFile.from(url: url, checkPin: false)
        try ensureLocal(file, timeout: timeout, dryRun: dryRun)
    }

    static func ensureLocalRecursive(
        _ url: URL,
        timeout: TimeInterval = 300,
        dryRun: Bool = false,
        progress: ((DownloadEvent) -> Void)? = nil
    ) throws {
        let file = try ICloudFile.from(url: url, checkPin: false)

        if !file.isDirectory {
            processOne(file, timeout: timeout, dryRun: dryRun, progress: progress)
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
            processOne(child, timeout: timeout, dryRun: dryRun, progress: progress)
        }
    }

    private static func processOne(
        _ file: ICloudFile,
        timeout: TimeInterval,
        dryRun: Bool,
        progress: ((DownloadEvent) -> Void)?
    ) {
        if file.isUbiquitous && file.status == .cloud {
            if dryRun {
                progress?(.wouldDownload(file))
            } else {
                progress?(.starting(file))
                try? ensureLocal(file, timeout: timeout)
                progress?(.done(file))
            }
        } else {
            progress?(.skipped(file))
        }
    }
}

enum DownloadError: LocalizedError {
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .timeout(let name): return "Download timed out: \(name)"
        }
    }
}
