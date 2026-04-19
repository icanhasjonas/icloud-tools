import ArgumentParser

@main
struct ICloud: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "icloud",
        abstract: "Manage iCloud Drive files from the command line.",
        subcommands: [StatusCommand.self],
        defaultSubcommand: StatusCommand.self
    )
}
