import ClaudeGaugeCore
import SwiftUI

/// メニューバーのラベル。絵 (ドーナツまたは横棒) + 縦 2 行の % を 1 枚の画像にして出す。
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    /// メニューバーの背景色はシステムの外観 (ライト / ダーク) とは別に、壁紙で決まる。
    /// 外観から文字色を推測すると外れるため、白に固定する。
    private static let ink = Color.white

    var body: some View {
        // 前回の値を使う。ただしリセット時刻を過ぎた枠は「—」にする。
        let menuBar = MenuBarModel.make(snapshot: model.state.snapshot?.activeWindows(at: model.now))
        let gauge = MenuBarGaugeView(
            model: menuBar,
            style: model.settings.style,
            showsText: model.settings.showsPercentText,
            ink: Self.ink
        )
        Image(nsImage: StatusImageRenderer.render(gauge))
            .accessibilityLabel(
                "5-hour usage \(menuBar.fiveHour.text), weekly usage \(menuBar.weekly.text)"
            )
    }
}
