import Foundation

final class JSONRenderer: OpRenderer {
    var rebase: PathResolver.Rebase?
    private var summary = OpSummary()

    private struct Record: Encodable {
        let type: String
        let phase: String?
        let total: Int?
        let src: String?
        let dst: String?
        let url: String?
        let size: Int64?
        let verb: String?
        let elapsed: Double?
        let needsDownload: Bool?
        let reason: String?
        let error: String?
    }

    private struct SummaryRecord: Encodable {
        let type = "summary"
        let verb: String?
        let copied: Int
        let moved: Int
        let updated: Int
        let updatedBytes: Int64
        let skipped: Int
        let pruned: Int
        let prunedBytes: Int64
        let failed: Int
        let timedOut: Int
        let notFound: Int
        let wouldDo: Int
    }

    func handle(_ event: OpEvent) throws {
        summary.record(event)
        let r: Record
        switch event {
        case .downloadFail(let url, let error):
            r = rec(type: "download.fail", url: url.path, error: error.localizedDescription)
        case .opDone(let verb, let src, let dst, let size):
            r = rec(type: "op.done", src: src.path, dst: dst.path, size: size, verb: verb.rawValue)
        case .opFail(let verb, let src, let dst, let error):
            r = rec(type: "op.fail", src: src.path, dst: dst.path, verb: verb.rawValue, error: error.localizedDescription)
        case .opSkipped(let verb, let src, let dst, let reason, let size):
            r = rec(type: "op.skipped", src: src.path, dst: dst.path, size: size, verb: verb.rawValue, reason: reason)
        case .opPruned(let verb, let src, let dst, let size):
            r = rec(type: "op.pruned", src: src.path, dst: dst.path, size: size, verb: verb.rawValue)
        case .opUpdated(let verb, let src, let dst, let size):
            r = rec(type: "op.updated", src: src.path, dst: dst.path, size: size, verb: verb.rawValue)
        case .opWouldDo(let verb, let src, let dst, let size):
            r = rec(type: "op.would", src: src.path, dst: dst.path, size: size, verb: verb.rawValue)
        case .sourceMissing(let src):
            r = rec(type: "source.missing", src: src.path, reason: "not found")
        case .phaseStart, .phaseEnd, .discovered,
             .downloadStart, .downloadTick, .downloadDone:
            return
        }
        try Output.printJSONLine(r)
    }

    func finish() throws {
        try Output.printJSONLine(SummaryRecord(
            verb: summary.verb?.rawValue,
            copied: summary.copied,
            moved: summary.moved,
            updated: summary.updated,
            updatedBytes: summary.updatedBytes,
            skipped: summary.skipped,
            pruned: summary.pruned,
            prunedBytes: summary.prunedBytes,
            failed: summary.failed,
            timedOut: summary.timedOut,
            notFound: summary.notFound,
            wouldDo: summary.wouldDo
        ))
    }

    private func rec(type: String, phase: String? = nil, total: Int? = nil, src: String? = nil, dst: String? = nil, url: String? = nil, size: Int64? = nil, verb: String? = nil, elapsed: Double? = nil, needsDownload: Bool? = nil, reason: String? = nil, error: String? = nil) -> Record {
        Record(type: type, phase: phase, total: total, src: src, dst: dst, url: url, size: size, verb: verb, elapsed: elapsed, needsDownload: needsDownload, reason: reason, error: error)
    }
}
