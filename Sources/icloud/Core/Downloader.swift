import Foundation

enum DownloadEvent {
    case starting(ICloudFile)
    case done(ICloudFile)
    case wouldDownload(ICloudFile)
    case skipped(ICloudFile)

    var file: ICloudFile {
        switch self {
        case .starting(let f), .done(let f), .wouldDownload(let f), .skipped(let f): return f
        }
    }
}

struct Downloader {
    static func ensureLocal(_ file: ICloudFile, timeout: TimeInterval = 300, dryRun: Bool = false) throws {
        guard file.isUbiquitous && (file.status == .cloud || file.status == .downloading || file.isDataless) else { return }
        if dryRun { return }

        if file.status != .downloading {
            try FileManager.default.startDownloadingUbiquitousItem(at: file.url)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let fresh = URL(fileURLWithPath: file.url.path)
            let values = try fresh.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .fileSizeKey,
                .fileAllocatedSizeKey,
            ])

            let status = values.ubiquitousItemDownloadingStatus
            let fileSize = values.fileSize ?? 0
            let allocated = values.fileAllocatedSize ?? 0
            let stillDataless = fileSize > 0 && allocated == 0

            if (status == .current || status == .downloaded) && !stillDataless {
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
        progress: ((DownloadEvent) throws -> Void)? = nil
    ) throws {
        let file = try ICloudFile.from(url: url, checkPin: false)

        if !file.isDirectory {
            try processOne(file, timeout: timeout, dryRun: dryRun, progress: progress)
            return
        }

        let fm = FileManager.default
        var enumeratorError: Error?
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(ICloudFile.resourceKeys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                enumeratorError = error
                return false
            }
        ) else {
            throw DownloadError.enumerationFailed(url.path)
        }

        for case let fileURL as URL in enumerator {
            if let err = enumeratorError { throw err }
            let child = try ICloudFile.from(url: fileURL, checkPin: false)
            if child.isDirectory { continue }
            try processOne(child, timeout: timeout, dryRun: dryRun, progress: progress)
        }
        if let err = enumeratorError { throw err }
    }

    private static func processOne(
        _ file: ICloudFile,
        timeout: TimeInterval,
        dryRun: Bool,
        progress: ((DownloadEvent) throws -> Void)?
    ) throws {
        if file.isUbiquitous && (file.status == .cloud || file.status == .downloading || file.isDataless) {
            if dryRun {
                try progress?(.wouldDownload(file))
            } else {
                try progress?(.starting(file))
                try ensureLocal(file, timeout: timeout)
                try progress?(.done(file))
            }
        } else {
            try progress?(.skipped(file))
        }
    }
}

enum DownloadError: LocalizedError {
    case timeout(String)
    case enumerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .timeout(let name): return "Download timed out: \(name)"
        case .enumerationFailed(let path): return "Cannot enumerate directory: \(path)"
        }
    }
}
