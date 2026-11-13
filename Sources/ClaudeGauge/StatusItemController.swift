import AppKit
import Combine
import ClaudeGaugeCore
import SwiftUI

/// メニューバーのアイコン (ステータス項目) と、クリックで開く詳細を受け持つ。
///
/// 詳細は、`MenuBarExtra` のウィンドウや `NSPopover` ではなく、`NSMenu` の項目の中に入れる。
/// 「メニューバーを自動的に隠す」を有効にしていると、メニューバーは、マウスが画面の上端から離れた
/// (おおよそ 130〜160pt を超えた) 時点で隠れる。ウィンドウや `NSPopover` では、詳細の下のほう
/// (ボタンの行) に移っただけでアイコンが消えるが、`NSMenu` は、開いている間 (メニューの操作中)
/// メニューバーを出したままにする。
///
/// メニューの項目の中では、プルダウン (ポップアップボタン) が開かない。設定は、セグメント型にしてある。
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    /// メニューバーの背景色はシステムの外観 (ライト / ダーク) とは別に、壁紙で決まる。
    /// 外観から文字色を推測すると外れるため、白に固定する。
    private static let ink = Color.white

    private struct ImageInputs: Equatable {
        let menuBar: MenuBarModel
        let style: MenuBarStyle
        let showsText: Bool
    }

    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let contentItem = NSMenuItem()
    private var subscriptions = Set<AnyCancellable>()
    private var renderedInputs: ImageInputs?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        menu.delegate = self
        menu.addItem(contentItem)
        statusItem.menu = menu
        refreshContent()

        // `@Published` は値が入る前に通知するので、受け取った値をそのまま使う。
        Publishers.CombineLatest3(model.$state, model.$settings, model.$now)
            .sink { [weak self] state, settings, now in
                MainActor.assumeIsolated { self?.updateImage(state: state, settings: settings, now: now) }
            }
            .store(in: &subscriptions)
    }

    // MARK: - アイコン

    /// 前回の値を使う。ただしリセット時刻を過ぎた枠は「—」にする。
    /// 画像を作り直すのは、見た目が変わるときだけ (ImageRenderer は軽くない)。
    private func updateImage(state: UsageState, settings: AppSettings, now: Date) {
        let menuBar = MenuBarModel.make(snapshot: state.snapshot?.activeWindows(at: now))
        let inputs = ImageInputs(menuBar: menuBar, style: settings.style, showsText: settings.showsPercentText)
        guard inputs != renderedInputs, let button = statusItem.button else { return }
        renderedInputs = inputs

        let gauge = MenuBarGaugeView(
            model: menuBar, style: settings.style, showsText: settings.showsPercentText, ink: Self.ink
        )
        button.image = StatusImageRenderer.render(gauge)
        button.setAccessibilityLabel(
            "5-hour usage \(menuBar.fiveHour.text), weekly usage \(menuBar.weekly.text)"
        )
    }

    // MARK: - 詳細 (メニューの項目)

    /// 閉じるたびに作り直す。設定パネルの開閉などの状態が、前回のまま残らない (開き直すと、常に閉じた状態)。
    private func refreshContent() {
        let hosting = MenuContentHostingView(rootView: PopoverView(model: model))
        hosting.onSizeChange = { [weak menu] in menu?.update() }
        // メニューが開く前に、最初の大きさを決めておく (メニューは、開いた時点の大きさを使う)。
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        contentItem.view = hosting
    }

    func menuDidClose(_ menu: NSMenu) {
        refreshContent()
    }
}

/// メニューの項目に入れる SwiftUI のビュー。
/// `NSMenu` は、項目のビューの大きさを開いた時点で決めるので、設定パネルを開閉して中身の高さが変わったら、
/// 自分で大きさを更新して、メニューに伝える。
private final class MenuContentHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?

    override func layout() {
        super.layout()
        // 幅は、メニューに任せる (メニューが独自の幅を決めても、取り合いにならない)。高さだけを追従させる。
        let height = fittingSize.height
        guard abs(height - frame.height) >= 1 else { return }
        frame.size.height = height
        // レイアウトの途中でメニューを更新しない。
        DispatchQueue.main.async { [weak self] in self?.onSizeChange?() }
    }
}
