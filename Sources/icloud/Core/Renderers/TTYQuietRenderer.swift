import Foundation

final class TTYQuietRenderer: OpRenderer {
    var rebase: PathResolver.Rebase?
    private var summary = OpSummary()

    func handle(_ event: OpEvent) throws {
        summary.record(event)
        switch event {
        case .downloadStart(let url, let size):
            print("\(Output.yellow)⇣\(Output.reset) \(rel(url)) \(Output.dim)(\(Output.humanSize(size)))\(Output.reset)")
        case .downloadDone(let url, _, let elapsed):
            print("\(Output.green)✓\(Output.reset) \(rel(url)) \(Output.dim)(\(String(format: "%.1fs", elapsed)))\(Output.reset)")
        case .downloadFail(let url, let error):
            print("\(Output.red)✗\(Output.reset) \(rel(url)): \(error.localizedDescription)")
        case .opDone(_, let src, let dst, _):
            print("\(rel(src)) \(Output.green)=>\(Output.reset) \(rel(dst))")
        case .opFail(_, let src, let dst, let error):
            print("\(rel(src)) \(Output.red)-x>\(Output.reset) \(rel(dst)) \(Output.red)(\(error.localizedDescription))\(Output.reset)")
        case .opSkipped(_, let src, let dst, let reason, _):
            print("\(rel(src)) \(Output.dim)->\(Output.reset) \(rel(dst)) \(Output.yellow)(skipped: \(reason))\(Output.reset)")
        case .opPruned(_, let src, let dst, let size):
            print("\(rel(src)) \(Output.cyan)~>\(Output.reset) \(rel(dst)) \(Output.dim)(pruned, \(Output.humanSize(size)) freed)\(Output.reset)")
        case .opUpdated(_, let src, let dst, let size):
            print("\(rel(src)) \(Output.green)=>\(Output.reset) \(rel(dst)) \(Output.dim)(updated, \(Output.humanSize(size)))\(Output.reset)")
        case .opWouldDo(let verb, let src, let dst, _):
            print("\(rel(src)) \(Output.dim)->\(Output.reset) \(rel(dst)) \(Output.dim)(would \(verb.present))\(Output.reset)")
        case .sourceMissing(let src):
            FileHandle.standardError.write(Data("\(Output.yellow)⚠\(Output.reset) \(rel(src)) \(Output.yellow)(not found, skipped)\(Output.reset)\n".utf8))
        case .phaseStart, .phaseEnd, .discovered, .downloadTick:
            break
        }
    }

    func finish() throws {
        SummaryFormatter.printTTY(summary)
    }

    private func rel(_ url: URL) -> String {
        PathResolver.relativePath(url, rebase: rebase)
    }
}
