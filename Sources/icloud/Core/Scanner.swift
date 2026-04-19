import Foundation

struct ScanResult: Sendable {
    let files: [ICloudFile]

    var totalCount: Int { files.count }

    private var _counts: (local: Int, cloud: Int, downloading: Int, uploading: Int, evictable: Int64) {
        var local = 0, cloud = 0, downloading = 0, uploading = 0
        var evictable: Int64 = 0
        for file in files {
            switch file.status {
            case .local:
                local += 1
                if file.isUbiquitous { evictable += file.allocatedSize }
            case .cloud: cloud += 1
            case .downloading: downloading += 1
            case .uploading: uploading += 1
            case .excluded, .unknown: break
            }
        }
        return (local, cloud, downloading, uploading, evictable)
    }

    var localCount: Int { _counts.local }
    var cloudCount: Int { _counts.cloud }
    var downloadingCount: Int { _counts.downloading }
    var uploadingCount: Int { _counts.uploading }
    var totalEvictableSize: Int64 { _counts.evictable }
}

struct Scanner {
    static func scan(
        directory: URL,
        recursive: Bool = false,
        filter: ((ICloudFile) -> Bool)? = nil
    ) throws -> ScanResult {
        let fm = FileManager.default
        var files: [ICloudFile] = []

        if recursive {
            guard let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(ICloudFile.resourceKeys),
                options: [.skipsHiddenFiles]
            ) else {
                return ScanResult(files: [])
            }

            for case let url as URL in enumerator {
                let file = try ICloudFile.from(url: url)
                if file.isDirectory { continue }
                if let filter, !filter(file) { continue }
                files.append(file)
            }
        } else {
            let contents = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(ICloudFile.resourceKeys),
                options: [.skipsHiddenFiles]
            )

            for url in contents {
                let file = try ICloudFile.from(url: url)
                if let filter, !filter(file) { continue }
                files.append(file)
            }
        }

        return ScanResult(files: files)
    }
}
