import ArgumentParser

@main
struct ICloud: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "icloud",
        abstract: "Manage iCloud Drive files.",
        discussion: "Replacement for brctl download/evict (removed in macOS 14+).",
        version: "0.4.0",
        subcommands: [StatusCommand.self, DownloadCommand.self, EvictCommand.self, MoveCommand.self, CopyCommand.self],
        defaultSubcommand: StatusCommand.self
    )
}
