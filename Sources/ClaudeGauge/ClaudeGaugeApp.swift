import AppKit
import SwiftUI

@main
struct ClaudeGaugeApp: App {
    @StateObject private var model = AppModel()

    init() {
        // `swift run` で起動した場合も Dock に出さない (.app では LSUIElement が同じ役割)。
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
