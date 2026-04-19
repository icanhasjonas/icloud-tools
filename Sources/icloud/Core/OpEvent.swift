import Foundation

enum FileVerb: String, Encodable {
    case move
    case copy

    var past: String {
        switch self {
        case .move: return "moved"
        case .copy: return "copied"
        }
    }

    var present: String {
        switch self {
        case .move: return "move"
        case .copy: return "copy"
        }
    }
}

enum Phase: String, Encodable {
    case discover
    case download
    case operate
    case report
}

enum OpEvent {
    case phaseStart(phase: Phase, totalFiles: Int?)
    case phaseEnd(phase: Phase)

    case discovered(src: URL, dst: URL?, size: Int64, needsDownload: Bool)

    case downloadStart(url: URL, size: Int64)
    case downloadTick(url: URL, elapsed: TimeInterval)
    case downloadDone(url: URL, size: Int64, elapsed: TimeInterval)
    case downloadFail(url: URL, error: Error)

    case opDone(verb: FileVerb, src: URL, dst: URL, size: Int64)
    case opFail(verb: FileVerb, src: URL, dst: URL, error: Error)
    case opSkipped(verb: FileVerb, src: URL, dst: URL, reason: String, size: Int64)
    case opWouldDo(verb: FileVerb, src: URL, dst: URL, size: Int64)
}
