import Foundation

struct ScanResult: Sendable {
    let files: [ICloudFile]
    let localCount: Int
    let cloudCount: Int
    let downloadingCount: Int
    let uploadingCount: Int
    let totalEvictableSize: Int64

    var totalCount: Int { files.count }
}

struct Scanner {
    static func scan(
        directory: URL,
        recursive: Bool = false,
        filter: ((ICloudFile) -> Bool)? = nil
    ) throws -> ScanResult {
        let fm = FileManager.default

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemDownloadRequestedKey,
            .ubiquitousItemIsUploadedKey,
            .ubiquitousItemIsUploadingKey,
            .ubiquitousItemHasUnresolvedConflictsKey,
            .ubiquitousItemIsSharedKey,
            .ubiquitousItemIsExcludedFromSyncKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
        ]

        var files: [ICloudFile] = []
        var localCount = 0
        var cloudCount = 0
        var downloadingCount = 0
        var uploadingCount = 0
        var totalEvictableSize: Int64 = 0

        if recursive {
            guard let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            ) else {
                return ScanResult(
                    files: [], localCount: 0, cloudCount: 0,
                    downloadingCount: 0, uploadingCount: 0, totalEvictableSize: 0
                )
            }

            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true { continue }

                let file = try ICloudFile.from(url: url)
                if let filter, !filter(file) { continue }

                tally(file, &localCount, &cloudCount, &downloadingCount, &uploadingCount, &totalEvictableSize)
                files.append(file)
            }
        } else {
            let contents = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )

            for url in contents {
                let file = try ICloudFile.from(url: url)
                if let filter, !filter(file) { continue }

                tally(file, &localCount, &cloudCount, &downloadingCount, &uploadingCount, &totalEvictableSize)
                files.append(file)
            }
        }

        return ScanResult(
            files: files,
            localCount: localCount,
            cloudCount: cloudCount,
            downloadingCount: downloadingCount,
            uploadingCount: uploadingCount,
            totalEvictableSize: totalEvictableSize
        )
    }

    private static func tally(
        _ file: ICloudFile,
        _ local: inout Int,
        _ cloud: inout Int,
        _ downloading: inout Int,
        _ uploading: inout Int,
        _ evictable: inout Int64
    ) {
        switch file.status {
        case .local:
            local += 1
            if file.isUbiquitous {
                evictable += file.allocatedSize
            }
        case .cloud:
            cloud += 1
        case .downloading:
            downloading += 1
        case .uploading:
            uploading += 1
        case .excluded, .unknown:
            break
        }
    }
}
