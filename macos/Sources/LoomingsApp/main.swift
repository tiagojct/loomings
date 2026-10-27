import AppKit

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--self-test") {
        NSApplication.shared.setActivationPolicy(.accessory)
        exit(SelfTest.run())
    }

    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
}
