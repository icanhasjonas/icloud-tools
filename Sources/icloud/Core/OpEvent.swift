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
    case opPruned(verb: FileVerb, src: URL, dst: URL, size: Int64)
    case opWouldDo(verb: FileVerb, src: URL, dst: URL, size: Int64)

    case sourceMissing(src: URL)
}

struct OpSummary {
    var copied = 0
    var moved = 0
    var skipped = 0
    var pruned = 0
    var prunedBytes: Int64 = 0
    var failed = 0
    var timedOut = 0
    var notFound = 0
    var wouldDo = 0

    var verb: FileVerb?

    mutating func record(_ event: OpEvent) {
        switch event {
        case .opDone(let v, _, _, _):
            verb = v
            switch v {
            case .copy: copied += 1
            case .move: moved += 1
            }
        case .opFail(let v, _, _, _):
            verb = v
            failed += 1
        case .opSkipped(let v, _, _, _, _):
            verb = v
            skipped += 1
        case .opPruned(let v, _, _, let size):
            verb = v
            pruned += 1
            prunedBytes += size
        case .opWouldDo(let v, _, _, _):
            verb = v
            wouldDo += 1
        case .downloadFail:
            timedOut += 1
        case .sourceMissing:
            notFound += 1
        case .phaseStart, .phaseEnd, .discovered,
             .downloadStart, .downloadTick, .downloadDone:
            break
        }
    }

    var totalOps: Int { copied + moved + skipped + pruned + failed + notFound + wouldDo }
    var isEmpty: Bool { totalOps == 0 && timedOut == 0 }
}
