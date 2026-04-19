import ArgumentParser

@main
struct ICloud: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "icloud",
        abstract: "Manage iCloud Drive files from the command line.",
        subcommands: [StatusCommand.self, MoveCommand.self, CopyCommand.self],
        defaultSubcommand: StatusCommand.self
    )
}
