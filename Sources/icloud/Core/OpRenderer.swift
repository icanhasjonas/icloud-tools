import Foundation

protocol OpRenderer: AnyObject {
    var rebase: PathResolver.Rebase? { get set }
    func handle(_ event: OpEvent) throws
    func finish() throws
}

enum RendererFactory {
    static func make(verbose: Bool, json: Bool, dryRun: Bool) -> OpRenderer {
        if json { return JSONRenderer() }
        let tty = isatty(STDOUT_FILENO) != 0
        if !tty { return LineStreamRenderer() }
        if verbose { return TTYVerboseRenderer() }
        _ = dryRun
        return TTYQuietRenderer()
    }
}
