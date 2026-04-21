import Foundation

struct ScanResult: Sendable {
    let files: [ICloudFile]
    let localCount: Int
    let cloudCount: Int
    let downloadingCount: Int
    let uploadingCount: Int
    let totalEvictableSize: Int64

    var totalCount: Int { files.count }

    init(files: [ICloudFile]) {
        self.files = files
        var local = 0, cloud = 0, downloading = 0, uploading = 0
        var evictable: Int64 = 0
        for file in files {
            // Dataless files report .local but have no bytes on disk. Count them as cloud.
            if file.isDataless {
                cloud += 1
                continue
            }
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
        self.localCount = local
        self.cloudCount = cloud
        self.downloadingCount = downloading
        self.uploadingCount = uploading
        self.totalEvictableSize = evictable
    }
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
            var enumeratorError: Error?
            guard let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(ICloudFile.resourceKeys),
                options: [.skipsHiddenFiles],
                errorHandler: { _, error in
                    enumeratorError = error
                    return false
                }
            ) else {
                throw ScanError.enumerationFailed(directory.path)
            }

            for case let url as URL in enumerator {
                if let err = enumeratorError { throw err }
                let file = try ICloudFile.from(url: url)
                if file.isDirectory { continue }
                if let filter, !filter(file) { continue }
                files.append(file)
            }
            if let err = enumeratorError { throw err }
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

enum ScanError: LocalizedError {
    case enumerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .enumerationFailed(let path):
            return "Cannot enumerate directory: \(path)"
        }
    }
}
