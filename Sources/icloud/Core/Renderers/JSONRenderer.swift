import Foundation

final class JSONRenderer: OpRenderer {
    var rebase: PathResolver.Rebase?

    private struct Record: Encodable {
        let event: String
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

    func handle(_ event: OpEvent) throws {
        let r: Record
        switch event {
        case .phaseStart(let p, let total):
            r = rec(event: "phase.start", phase: p.rawValue, total: total)
        case .phaseEnd(let p):
            r = rec(event: "phase.end", phase: p.rawValue)
        case .discovered(let src, let dst, let size, let needsDownload):
            r = rec(event: "discovered", src: src.path, dst: dst?.path, size: size, needsDownload: needsDownload)
        case .downloadStart(let url, let size):
            r = rec(event: "download.start", url: url.path, size: size)
        case .downloadTick(let url, let elapsed):
            r = rec(event: "download.tick", url: url.path, elapsed: elapsed)
        case .downloadDone(let url, let size, let elapsed):
            r = rec(event: "download.done", url: url.path, size: size, elapsed: elapsed)
        case .downloadFail(let url, let error):
            r = rec(event: "download.fail", url: url.path, error: error.localizedDescription)
        case .opDone(let verb, let src, let dst, let size):
            r = rec(event: "op.done", src: src.path, dst: dst.path, size: size, verb: verb.rawValue)
        case .opFail(let verb, let src, let dst, let error):
            r = rec(event: "op.fail", src: src.path, dst: dst.path, verb: verb.rawValue, error: error.localizedDescription)
        case .opSkipped(let verb, let src, let dst, let reason, let size):
            r = rec(event: "op.skipped", src: src.path, dst: dst.path, size: size, verb: verb.rawValue, reason: reason)
        case .opWouldDo(let verb, let src, let dst, let size):
            r = rec(event: "op.would", src: src.path, dst: dst.path, size: size, verb: verb.rawValue)
        }
        try Output.printJSONLine(r)
    }

    func finish() throws {}

    private func rec(event: String, phase: String? = nil, total: Int? = nil, src: String? = nil, dst: String? = nil, url: String? = nil, size: Int64? = nil, verb: String? = nil, elapsed: Double? = nil, needsDownload: Bool? = nil, reason: String? = nil, error: String? = nil) -> Record {
        Record(event: event, phase: phase, total: total, src: src, dst: dst, url: url, size: size, verb: verb, elapsed: elapsed, needsDownload: needsDownload, reason: reason, error: error)
    }
}
