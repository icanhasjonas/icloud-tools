import Foundation

struct ScanResult: Sendable {
    let files: [ICloudFile]

    var totalCount: Int { files.count }

    var localCount: Int {
        files.count { $0.status == .local }
    }

    var cloudCount: Int {
        files.count { $0.status == .cloud }
    }

    var downloadingCount: Int {
        files.count { $0.status == .downloading }
    }

    var uploadingCount: Int {
        files.count { $0.status == .uploading }
    }

    var totalEvictableSize: Int64 {
        files.reduce(0) { sum, file in
            file.status == .local && file.isUbiquitous ? sum + file.allocatedSize : sum
        }
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
