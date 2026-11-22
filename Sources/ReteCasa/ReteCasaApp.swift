import SwiftUI

@main
struct ReteCasaApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updater = Updater()
    @State private var showUpdateSheet = false

    init() {
        if CommandLine.arguments.contains("--selftest") {
            let args = CommandLine.arguments
            Task { await SelfTest.run(args: args); exit(0) }
        }
        WindowSnapshot.schedule(args: CommandLine.arguments)
    }

    var body: some Scene {
        WindowGroup("Rete Casa") {
            ContentView(showUpdateSheet: $showUpdateSheet)
                .environmentObject(model)
                .environmentObject(updater)
                .sheet(isPresented: $showUpdateSheet) { UpdateSheet(updater: updater) }
                .task {
                    // Controllo silenzioso all'avvio: il pannello compare solo se c'è una novità.
                    await updater.check()
                    if updater.isUpdateAvailable { showUpdateSheet = true }
                }
                .frame(minWidth: 860, minHeight: 600)
        }
        .defaultSize(width: 1040, height: 740)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Verifica aggiornamenti…") {
                    showUpdateSheet = true
                    Task { await updater.check() }
                }
            }
        }
    }
}
