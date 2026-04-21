import Foundation

enum SummaryFormatter {
    /// TTY: human summary to stdout (matches existing success/skip lines).
    /// Dim separator, color-coded counts. Rows with 0 count are hidden.
    static func printTTY(_ s: OpSummary) {
        if s.isEmpty { return }
        var rows: [(Int, String, String)] = []
        if s.copied > 0 { rows.append((s.copied, "copied", Output.green)) }
        if s.moved > 0 { rows.append((s.moved, "moved", Output.green)) }
        if s.pruned > 0 {
            rows.append((s.pruned, "pruned (\(Output.humanSize(s.prunedBytes)) freed)", Output.cyan))
        }
        if s.skipped > 0 { rows.append((s.skipped, "skipped", Output.yellow)) }
        if s.failed > 0 { rows.append((s.failed, "failed", Output.red)) }
        if s.timedOut > 0 { rows.append((s.timedOut, "timed out", Output.red)) }
        if s.notFound > 0 { rows.append((s.notFound, "not found", Output.yellow)) }
        if s.wouldDo > 0 {
            let label = s.verb.map { "would \($0.present)" } ?? "would do"
            rows.append((s.wouldDo, label, Output.dim))
        }

        print("\(Output.dim)────────\(Output.reset)")
        let width = rows.map { String($0.0).count }.max() ?? 1
        for (count, label, color) in rows {
            let padded = String(repeating: " ", count: width - String(count).count) + "\(count)"
            print("  \(color)\(padded) \(label)\(Output.reset)")
        }
    }

    /// Pipe mode: single grep-friendly key=value line.
    static func printLineStream(_ s: OpSummary) {
        if s.isEmpty { return }
        var parts: [String] = []
        if s.copied > 0 { parts.append("copied=\(s.copied)") }
        if s.moved > 0 { parts.append("moved=\(s.moved)") }
        if s.pruned > 0 { parts.append("pruned=\(s.pruned)") }
        if s.skipped > 0 { parts.append("skipped=\(s.skipped)") }
        if s.failed > 0 { parts.append("failed=\(s.failed)") }
        if s.timedOut > 0 { parts.append("timed-out=\(s.timedOut)") }
        if s.notFound > 0 { parts.append("not-found=\(s.notFound)") }
        if s.wouldDo > 0 { parts.append("would=\(s.wouldDo)") }
        print("SUMMARY \(parts.joined(separator: " "))")
    }
}
