import ClaudeGaugeCore
import SwiftUI

/// ポップオーバー内の設定。Settings シーンは LSUIElement アプリでは前面に出にくいので使わない。
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Menu bar") {
                Picker("Menu bar", selection: $model.settings.style) {
                    Text("Donut").tag(MenuBarStyle.donut)
                    Text("Bars").tag(MenuBarStyle.bar)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }

            Toggle("Show percentages", isOn: $model.settings.showsPercentText)

            LabeledContent("Refresh every") {
                Picker("Refresh every", selection: $model.settings.refreshInterval) {
                    ForEach(AppSettings.intervalChoices, id: \.self) { seconds in
                        Text("\(Int(seconds / 60)) min").tag(seconds)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }

            launchAtLogin
        }
        .font(.system(size: 12))
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
