import SwiftUI
import AppKit

@main
struct ScreenshotSyncApp: App {
    @StateObject private var serverController: ServerController

    init() {
        setvbuf(stdout, nil, _IONBF, 0)
        NSApplication.shared.setActivationPolicy(.accessory)
        let controller = ServerController()
        _serverController = StateObject(wrappedValue: controller)
        controller.start()
    }

    var body: some Scene {
        MenuBarExtra("Screenshot Sync", systemImage: "photo.on.rectangle.angled") {
            ContentView()
                .environmentObject(serverController)
        }
        .menuBarExtraStyle(.window)
    }
}
