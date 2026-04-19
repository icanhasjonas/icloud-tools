import Foundation

enum ICloudStatus: String, Sendable {
    case local
    case cloud
    case downloading
    case uploading
    case excluded
    case unknown
}

struct ICloudFile: Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let status: ICloudStatus
    let fileSize: Int64
    let allocatedSize: Int64
    let isUbiquitous: Bool
    let isDownloading: Bool
    let isUploading: Bool
    let isShared: Bool
    let hasConflicts: Bool
    let isPinned: Bool
    let childCount: Int?

    var isDataless: Bool {
        fileSize > 0 && allocatedSize == 0
    }

    var displaySize: String {
        Output.humanSize(fileSize)
    }

    static func from(url: URL, checkPin: Bool = true) throws -> ICloudFile {
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

        let values = try url.resourceValues(forKeys: resourceKeys)
        let isDir = values.isDirectory ?? false
        let isUbiquitous = values.isUbiquitousItem ?? false

        let status: ICloudStatus
        if values.ubiquitousItemIsExcludedFromSync == true {
            status = .excluded
        } else if values.ubiquitousItemIsDownloading == true {
            status = .downloading
        } else if values.ubiquitousItemIsUploading == true {
            status = .uploading
        } else {
            switch values.ubiquitousItemDownloadingStatus {
            case URLUbiquitousItemDownloadingStatus.current,
                 URLUbiquitousItemDownloadingStatus.downloaded:
                status = .local
            case URLUbiquitousItemDownloadingStatus.notDownloaded:
                status = .cloud
            default:
                if !isUbiquitous {
                    status = .local
                } else {
                    status = .unknown
                }
            }
        }

        var pinned = false
        if checkPin {
            let path = url.path
            pinned = getxattr(path, "com.apple.fileprovider.pinned#PX", nil, 0, 0, 0) >= 0
        }

        return ICloudFile(
            url: url,
            name: url.lastPathComponent,
            isDirectory: isDir,
            status: status,
            fileSize: Int64(values.fileSize ?? 0),
            allocatedSize: Int64(values.fileAllocatedSize ?? 0),
            isUbiquitous: isUbiquitous,
            isDownloading: values.ubiquitousItemIsDownloading ?? false,
            isUploading: values.ubiquitousItemIsUploading ?? false,
            isShared: values.ubiquitousItemIsShared ?? false,
            hasConflicts: values.ubiquitousItemHasUnresolvedConflicts ?? false,
            isPinned: pinned,
            childCount: nil
        )
    }
}
