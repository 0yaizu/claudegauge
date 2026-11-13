import AppKit
import SwiftUI

@main
struct ClaudeGaugeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // `swift run` で起動した場合も Dock に出さない (.app では LSUIElement が同じ役割)。
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    /// 画面に出すものは、すべて `StatusItemController` が作る (メニューバーのアイコンと、その詳細)。
    /// SwiftUI の App は、最低 1 つのシーンを要求するので、何も出さない設定のシーンだけを置く。
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model
        statusItemController = StatusItemController(model: model)
    }
}
