import Foundation

final class LineStreamRenderer: OpRenderer {
    var rebase: PathResolver.Rebase?

    func handle(_ event: OpEvent) throws {
        switch event {
        case .downloadStart(let url, _):
            print("DL-> \(url.path)")
        case .downloadDone(let url, _, let elapsed):
            print("DL✓  \(url.path) (\(String(format: "%.1fs", elapsed)))")
        case .downloadFail(let url, let error):
            print("DL✗  \(url.path): \(error.localizedDescription)")
        case .opDone(let verb, let src, let dst, _):
            let tag = verb == .move ? "MV" : "CP"
            print("\(tag)✓  \(src.path) => \(dst.path)")
        case .opFail(let verb, let src, let dst, let error):
            let tag = verb == .move ? "MV" : "CP"
            print("\(tag)✗  \(src.path) -> \(dst.path): \(error.localizedDescription)")
        case .opSkipped(let verb, let src, let dst, let reason, _):
            let tag = verb == .move ? "MV" : "CP"
            print("\(tag)?  \(src.path) -> \(dst.path) (skipped: \(reason))")
        case .opWouldDo(let verb, let src, let dst, _):
            let tag = verb == .move ? "MV" : "CP"
            print("\(tag)?  \(src.path) -> \(dst.path) (would \(verb.present))")
        case .phaseStart, .phaseEnd, .discovered, .downloadTick:
            break
        }
    }

    func finish() throws {}
}
