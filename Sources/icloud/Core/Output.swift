import Foundation

struct Output {
    static let noColor = ProcessInfo.processInfo.environment["NO_COLOR"] != nil
        || isatty(STDOUT_FILENO) == 0

    static let reset = noColor ? "" : "\u{1B}[0m"
    static let bold = noColor ? "" : "\u{1B}[1m"
    static let dim = noColor ? "" : "\u{1B}[2m"
    static let green = noColor ? "" : "\u{1B}[32m"
    static let yellow = noColor ? "" : "\u{1B}[33m"
    static let red = noColor ? "" : "\u{1B}[31m"
    static let cyan = noColor ? "" : "\u{1B}[36m"
    static let blue = noColor ? "" : "\u{1B}[34m"

    static func statusColor(_ status: ICloudStatus) -> String {
        switch status {
        case .local: return green
        case .cloud: return dim
        case .downloading: return yellow
        case .uploading: return cyan
        case .excluded: return blue
        case .unknown: return red
        }
    }

    static func statusLabel(_ status: ICloudStatus) -> String {
        switch status {
        case .local: return "local"
        case .cloud: return "cloud"
        case .downloading: return "sync"
        case .uploading: return "sync"
        case .excluded: return "excl"
        case .unknown: return "????"
        }
    }

    static func humanSize(_ bytes: Int64) -> String {
        if bytes == 0 { return "" }
        let units: [(String, Int64)] = [
            ("GB", 1_000_000_000),
            ("MB", 1_000_000),
            ("KB", 1_000),
        ]
        for (unit, threshold) in units {
            if bytes >= threshold {
                let value = Double(bytes) / Double(threshold)
                return value >= 10
                    ? "\(Int(value)) \(unit)"
                    : String(format: "%.1f \(unit)", value)
            }
        }
        return "\(bytes) B"
    }

    static func printFileTable(_ files: [ICloudFile]) {
        let nameWidth = files.map(\.name.count).max() ?? 20

        for file in files {
            let name = file.isDirectory ? file.name + "/" : file.name
            let padding = String(repeating: " ", count: max(0, nameWidth - name.count + 2))

            if file.isDirectory {
                let pin = file.isPinned ? " \(cyan)P\(reset)" : ""
                print("  \(dim) dir\(reset)   \(name)\(padding)\(reset)\(pin)")
            } else {
                let color = statusColor(file.status)
                let label = statusLabel(file.status)
                let size = humanSize(file.fileSize)
                let pin = file.isPinned ? " \(cyan)P\(reset)" : ""
                print("  \(color)\(label)\(reset)   \(name)\(padding)\(dim)\(size)\(reset)\(pin)")
            }
        }
    }

    static func printSummary(_ result: ScanResult) {
        var parts: [String] = []
        if result.localCount > 0 {
            parts.append("\(green)\(result.localCount) local\(reset)")
        }
        if result.cloudCount > 0 {
            parts.append("\(dim)\(result.cloudCount) cloud\(reset)")
        }
        if result.downloadingCount > 0 || result.uploadingCount > 0 {
            let syncCount = result.downloadingCount + result.uploadingCount
            parts.append("\(yellow)\(syncCount) syncing\(reset)")
        }

        var summary = "\n" + parts.joined(separator: "  ")
        if result.totalEvictableSize > 0 {
            summary += "  \(dim)(\(humanSize(result.totalEvictableSize)) evictable)\(reset)"
        }
        print(summary)
    }

    private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let jsonLineEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static func printJSON(_ value: some Encodable) throws {
        let data = try jsonEncoder.encode(value)
        print(String(data: data, encoding: .utf8)!)
    }

    static func printJSONLine(_ value: some Encodable) throws {
        let data = try jsonLineEncoder.encode(value)
        print(String(data: data, encoding: .utf8)!)
    }
}
