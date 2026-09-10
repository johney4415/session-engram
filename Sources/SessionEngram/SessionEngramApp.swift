import AppKit
import SwiftUI

@main
struct SessionEngramApp: App {
    @StateObject private var model = SessionListModel()

    init() {
        // The menu bar UI belongs to the .app bundle. Anything else is a terminal
        // run, so a bare invocation there opens the interactive browser instead.
        let arguments = Array(CommandLine.arguments.dropFirst())
        if !arguments.isEmpty || !LaunchContext.isAppBundle {
            Self.runCLI(arguments.isEmpty ? ["browse"] : arguments)
        }
    }

    private static func runCLI(_ arguments: [String]) -> Never {
        do {
            try CLI.run(arguments: arguments)
            Foundation.exit(EXIT_SUCCESS)
        } catch let error as CLI.ExitError {
            if !error.message.isEmpty {
                FileHandle.standardError.write(Data("session-engram: \(error.message)\n".utf8))
            }
            Foundation.exit(error.code)
        } catch {
            FileHandle.standardError.write(Data("session-engram: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            SessionListView(model: model)
        } label: {
            Image(systemName: "list.bullet.rectangle")
        }
        .menuBarExtraStyle(.window)
    }
}

enum LaunchContext {
    /// True when the running binary sits inside `Session Engram.app`, which is the
    /// only place the menu bar scene should come up.
    static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
