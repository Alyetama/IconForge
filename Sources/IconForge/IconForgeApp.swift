import SwiftUI

@main
struct IconForgeApp: App {
    @StateObject private var model = GeneratorModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 660)
                .task {
                    model.reloadHistory()
                    model.loadModels()
                }
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Reveal Output Folder") { model.revealInFinder() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
