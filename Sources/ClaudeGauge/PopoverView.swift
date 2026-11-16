import ClaudeGaugeCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @State private var showsSettings = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .padding(16)
        .frame(width: 380)
        // メニューの項目のウィンドウは、キーウィンドウにならない。そのままだと、コントロールが
        // 「非アクティブ」の見た目 (選択色が青でなく灰色、ボタンが白っぽい灰色) で描かれてしまう。
        .environment(\.controlActiveState, .key)
        // システム設定側で変えられたログイン項目の状態に、開くたび追従する。
        .onAppear { model.refreshLoginItemStatus() }
    }

    private func content(now: Date) -> some View {
        // 前回の値を使う。ただしリセット時刻を過ぎた枠は「—」にする。
        let snapshot = model.state.snapshot?.activeWindows(at: now)
        return VStack(alignment: .leading, spacing: 16) {
            WindowRowView(row: .make(
                title: "5h session", usage: snapshot?.fiveHour,
                windowLength: WindowForecast.fiveHourLength, now: now
            ))
            WindowRowView(row: .make(
                title: "Weekly", usage: snapshot?.weekly,
                windowLength: WindowForecast.weeklyLength, now: now
            ))
            Divider()
            if showsSettings {
                SettingsView(model: model)
                Divider()
            }
            footer(now: now)
        }
    }

    private func footer(now: Date) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if model.state.showsRefreshNotice {
                    Text(DisplayFormatter.tokenExpiredNotice)
                        .foregroundStyle(.orange)
                }
                Text(lastUpdatedText(now: now))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Spacer(minLength: 8)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        Task { await model.reload() }
                    } label: {
                        reloadLabel
                    }
                    .accessibilityLabel("Reload")
                    .disabled(!canReload(now: now))

                    Button {
                        showsSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")

                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                }
                .buttonStyle(.glass)
                .controlSize(.regular)
            }
        }
    }

    @ViewBuilder
    private var reloadLabel: some View {
				/// トークンの期限切れの表示がある際、Reloadの文字が潰れてしまうのを防ぐために、ボタンのみの表示にする。
        if model.state.showsRefreshNotice {
            Image(systemName: "arrow.clockwise")
        } else {
            Label("Reload", systemImage: "arrow.clockwise")
        }
    }

    private func lastUpdatedText(now: Date) -> String {
        guard let snapshot = model.state.snapshot else { return "No data yet" }
        return DisplayFormatter.lastUpdated(snapshot.fetchedAt, now: now)
    }

    private func canReload(now: Date) -> Bool {
        !model.isReloading && RefreshPolicy.canReload(lastAttemptAt: model.state.lastAttemptAt, now: now)
    }
}
