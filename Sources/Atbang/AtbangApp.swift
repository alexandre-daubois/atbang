import AppKit
import SwiftUI

@main
struct AtbangApp: App {
    @State private var model = AppModel()

    init() {
        // Menu bar only, also when launched through `swift run` without the bundle's LSUIElement.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            Image(systemName: model.highPriorityCount > 0 ? "tray.full" : "tray")
            if model.showsMenuBarCount, !model.items.isEmpty {
                Text(String(model.items.count))
            }
        }
        .menuBarExtraStyle(.window)
    }
}
