import Foundation

enum ICloudStatus: String, Sendable, Encodable {
    case local
    case cloud
    case downloading
    case uploading
    case excluded
    case unknown
}

struct ICloudFile: Sendable, Encodable {
    static let resourceKeys: Set<URLResourceKey> = [
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
        .tagNamesKey,
    ]

    let url: URL
    let name: String
    let isDirectory: Bool
    let status: ICloudStatus
    let fileSize: Int64
    let allocatedSize: Int64
    let isUbiquitous: Bool
    let isPinned: Bool
    let tagNames: [String]

    var isDataless: Bool {
        fileSize > 0 && allocatedSize == 0
    }

    enum CodingKeys: String, CodingKey {
        case name, path, isDirectory, status
        case fileSize, allocatedSize, isUbiquitous, isPinned, isDataless, tagNames
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(url.path, forKey: .path)
        try container.encode(isDirectory, forKey: .isDirectory)
        try container.encode(status, forKey: .status)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encode(allocatedSize, forKey: .allocatedSize)
        try container.encode(isUbiquitous, forKey: .isUbiquitous)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isDataless, forKey: .isDataless)
        if !tagNames.isEmpty {
            try container.encode(tagNames, forKey: .tagNames)
        }
    }

    static func from(url: URL, checkPin: Bool = true) throws -> ICloudFile {
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
                status = isUbiquitous ? .unknown : .local
            }
        }

        return ICloudFile(
            url: url,
            name: url.lastPathComponent,
            isDirectory: isDir,
            status: status,
            fileSize: Int64(values.fileSize ?? 0),
            allocatedSize: Int64(values.fileAllocatedSize ?? 0),
            isUbiquitous: isUbiquitous,
            isPinned: checkPin ? Pinner.isPinned(url) : false,
            tagNames: values.tagNames ?? []
        )
    }
}
