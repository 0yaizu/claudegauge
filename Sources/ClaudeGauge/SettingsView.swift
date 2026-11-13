import ClaudeGaugeCore
import SwiftUI

/// 詳細 (メニューの項目) の中の設定。Settings シーンは LSUIElement アプリでは前面に出にくいので使わない。
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Menu bar") {
                SegmentedChoice(
                    options: [
                        .init(label: "Donut", value: MenuBarStyle.donut),
                        .init(label: "Bars", value: MenuBarStyle.bar),
                    ],
                    selection: $model.settings.style
                )
                .frame(width: 140)
            }

            Toggle("Show percentages", isOn: $model.settings.showsPercentText)

            // メニューの項目の中では、プルダウン (ポップアップボタン) が開かないので、セグメント型にする。
            LabeledContent("Refresh every") {
                SegmentedChoice(
                    options: AppSettings.intervalChoices.map { .init(label: "\(Int($0 / 60)) min", value: $0) },
                    selection: $model.settings.refreshInterval
                )
                .frame(width: 210)
            }

            launchAtLogin
        }
        .font(.system(size: 12))
        .toggleStyle(AccentCheckboxToggleStyle())
    }

    @ViewBuilder
    private var launchAtLogin: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { model.loginItemStatus == .enabled || model.loginItemStatus == .needsApproval },
            set: { model.setLaunchAtLogin($0) }
        ))
        .disabled(model.loginItemStatus == .unavailable)

        if let note = loginItemNote {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var loginItemNote: String? {
        if let error = model.loginItemError { return error }
        switch model.loginItemStatus {
        case .needsApproval: return "Allow ClaudeGauge in System Settings › Login Items."
        case .unavailable: return "Available when running as ClaudeGauge.app."
        case .enabled, .disabled: return nil
        }
    }
}
