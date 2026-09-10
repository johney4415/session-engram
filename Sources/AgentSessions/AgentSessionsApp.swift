import AppKit
import SwiftUI

@main
struct AgentSessionsApp: App {
    @StateObject private var model = SessionListModel()

    init() {
        // Arguments mean the CLI was invoked; the menu bar app only opens on a bare run.
        let arguments = Array(CommandLine.arguments.dropFirst())
        if !arguments.isEmpty {
            do {
                try CLI.run(arguments: arguments)
                Foundation.exit(EXIT_SUCCESS)
            } catch let error as CLI.ExitError {
                if !error.message.isEmpty {
                    FileHandle.standardError.write(Data("agent-sessions: \(error.message)\n".utf8))
                }
                Foundation.exit(error.code)
            } catch {
                FileHandle.standardError.write(Data("agent-sessions: \(error.localizedDescription)\n".utf8))
                Foundation.exit(EXIT_FAILURE)
            }
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
