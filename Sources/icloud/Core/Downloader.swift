import Foundation

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

struct Downloader {
    static func needsDownload(_ file: ICloudFile) -> Bool {
        guard file.isUbiquitous else { return false }
        switch file.status {
        case .cloud, .downloading: return true
        case .local, .unknown: return file.isDataless
        case .uploading, .excluded: return false
        }
    }

    static func enumerate(_ url: URL) throws -> [ICloudFile] {
        let root = try ICloudFile.from(url: url, checkPin: false)
        if !root.isDirectory {
            return [root]
        }
        let fm = FileManager.default
        var enumError: Error?
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(ICloudFile.resourceKeys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                enumError = error
                return false
            }
        ) else {
            throw DownloadError.enumerationFailed(url.path)
        }
        var result: [ICloudFile] = []
        for case let fileURL as URL in enumerator {
            if let err = enumError { throw err }
            let child = try ICloudFile.from(url: fileURL, checkPin: false)
            if child.isDirectory { continue }
            result.append(child)
        }
        if let err = enumError { throw err }
        return result
    }

    static let defaultMaxConcurrent = 3
    static let defaultBaselineTimeout: TimeInterval = 120
    static let secondsPerMB: Double = 1.2

    /// Per-file timeout that scales with file size. ~100 MB => ~2 minutes, ~2 GB => ~40 minutes,
    /// small files get the baseline floor so cold TLS/handshakes don't trip.
    static func timeoutFor(sizeBytes: Int64, baseline: TimeInterval) -> TimeInterval {
        let sizeMB = Double(sizeBytes) / 1_000_000
        let scaled = sizeMB * secondsPerMB
        return max(baseline, scaled)
    }

    static func ensureLocalBatch(
        _ files: [ICloudFile],
        baselineTimeout: TimeInterval = Downloader.defaultBaselineTimeout,
        maxConcurrent: Int = Downloader.defaultMaxConcurrent,
        dryRun: Bool,
        emit: (OpEvent) throws -> Void
    ) throws {
        var queue = files.filter { needsDownload($0) }
        if queue.isEmpty || dryRun { return }

        let cap = max(1, maxConcurrent)
        var inFlight: [String: (file: ICloudFile, started: Date, deadline: Date)] = [:]
        var failed: [(ICloudFile, Error)] = []

        func dispatchMore() throws {
            while inFlight.count < cap, !queue.isEmpty {
                let f = queue.removeFirst()
                if f.status != .downloading {
                    try FileManager.default.startDownloadingUbiquitousItem(at: f.url)
                }
                try emit(.downloadStart(url: f.url, size: f.fileSize))
                let now = Date()
                let t = timeoutFor(sizeBytes: f.fileSize, baseline: baselineTimeout)
                inFlight[f.url.path] = (f, now, now.addingTimeInterval(t))
            }
        }

        try dispatchMore()

        while !inFlight.isEmpty || !queue.isEmpty {
            for key in Array(inFlight.keys) {
                guard let entry = inFlight[key] else { continue }
                let fresh = URL(fileURLWithPath: key)
                let values = try fresh.resourceValues(forKeys: [
                    .ubiquitousItemDownloadingStatusKey,
                    .fileSizeKey,
                    .fileAllocatedSizeKey,
                ])

                let status = values.ubiquitousItemDownloadingStatus
                let fileSize = Int64(values.fileSize ?? 0)
                let allocated = Int64(values.fileAllocatedSize ?? 0)
                let stillDataless = fileSize > 0 && allocated == 0

                if (status == .current || status == .downloaded) && !stillDataless {
                    let elapsed = Date().timeIntervalSince(entry.started)
                    try emit(.downloadDone(url: entry.file.url, size: fileSize, elapsed: elapsed))
                    inFlight.removeValue(forKey: key)
                } else if Date() > entry.deadline {
                    let err = DownloadError.timeout(entry.file.url.lastPathComponent)
                    try emit(.downloadFail(url: entry.file.url, error: err))
                    failed.append((entry.file, err))
                    inFlight.removeValue(forKey: key)
                } else {
                    let elapsed = Date().timeIntervalSince(entry.started)
                    try emit(.downloadTick(url: entry.file.url, elapsed: elapsed))
                }
            }

            try dispatchMore()

            if !inFlight.isEmpty {
                Thread.sleep(forTimeInterval: 0.25)
            }
        }

        if let (file, _) = failed.first {
            throw DownloadError.timeout("\(failed.count) file(s), first: \(file.url.lastPathComponent)")
        }
    }

    static func ensureLocal(_ file: ICloudFile, baselineTimeout: TimeInterval = Downloader.defaultBaselineTimeout, dryRun: Bool = false) throws {
        try ensureLocalBatch([file], baselineTimeout: baselineTimeout, dryRun: dryRun) { _ in }
    }

    static func ensureLocal(_ url: URL, baselineTimeout: TimeInterval = Downloader.defaultBaselineTimeout, dryRun: Bool = false) throws {
        let file = try ICloudFile.from(url: url, checkPin: false)
        try ensureLocal(file, baselineTimeout: baselineTimeout, dryRun: dryRun)
    }
}
