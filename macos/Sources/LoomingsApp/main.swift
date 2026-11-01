import AppKit

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--self-test") {
        NSApplication.shared.setActivationPolicy(.accessory)
        exit(SelfTest.run())
    }
    if CommandLine.arguments.contains("--snapshot") {
        NSApplication.shared.setActivationPolicy(.accessory)
        exit(Snapshot.run(arguments: CommandLine.arguments))
    }

    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
}
