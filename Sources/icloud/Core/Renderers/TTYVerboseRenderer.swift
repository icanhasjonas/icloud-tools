import Foundation

final class TTYVerboseRenderer: OpRenderer {
    var rebase: PathResolver.Rebase?
    private var lastHeader: String?

    func handle(_ event: OpEvent) throws {
        switch event {
        case .downloadStart(let url, let size):
            header(for: url)
            print("  \(Output.dim)(\(Output.humanSize(size)))\(Output.reset)")
            print("  \(Output.yellow)downloading...\(Output.reset)")
        case .downloadDone(let url, _, let elapsed):
            header(for: url)
            print("  \(Output.green)downloaded\(Output.reset) \(Output.dim)(\(String(format: "%.1fs", elapsed)))\(Output.reset)")
        case .downloadFail(let url, let error):
            header(for: url)
            print("  \(Output.red)download failed:\(Output.reset) \(error.localizedDescription)")
        case .opDone(let verb, let src, let dst, _):
            header(for: src)
            print("  \(Output.green)\(verb.past) to\(Output.reset) \(rel(dst))")
        case .opFail(let verb, let src, _, let error):
            header(for: src)
            print("  \(Output.red)\(verb.past) failed:\(Output.reset) \(error.localizedDescription)")
        case .opSkipped(_, let src, _, let reason, _):
            header(for: src)
            print("  \(Output.yellow)skipped:\(Output.reset) \(reason)")
        case .opWouldDo(let verb, let src, let dst, _):
            header(for: src)
            print("  \(Output.dim)would \(verb.present) to\(Output.reset) \(rel(dst))")
        case .phaseStart, .phaseEnd, .discovered, .downloadTick:
            break
        }
    }

    func finish() throws {}

    private func rel(_ url: URL) -> String {
        PathResolver.relativePath(url, rebase: rebase)
    }

    private func header(for url: URL) {
        if lastHeader != url.path {
            print(rel(url))
            lastHeader = url.path
        }
    }
}
