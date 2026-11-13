import Foundation
import Testing
@testable import ClaudeGaugeCore

struct AppSettingsTests {
    /// テストごとに独立した UserDefaults を使い、終わったら消す。
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "claudegauge.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test("初期値: ドーナツ / 3 分 / % 表示あり")
    func defaults() {
        let settings = AppSettings()

        #expect(settings.style == .donut)
        #expect(settings.refreshInterval == 180)
        #expect(settings.showsPercentText)
    }

    @Test("何も保存されていなければ初期値で読み込む")
    func loadsDefaultsWhenEmpty() {
        withDefaults { defaults in
            #expect(AppSettings(defaults: defaults) == AppSettings())
        }
    }

    @Test("保存した内容をそのまま読み戻せる")
    func roundTrip() {
        withDefaults { defaults in
            let saved = AppSettings(style: .bar, refreshInterval: 300, showsPercentText: false)
            saved.save(to: defaults)

            #expect(AppSettings(defaults: defaults) == saved)
        }
    }

    @Test("更新間隔は 1〜10 分に丸める", arguments: [(5.0, 60.0), (60.0, 60.0), (300.0, 300.0), (9999.0, 600.0)])
    func clampsInterval(stored: Double, expected: Double) {
        withDefaults { defaults in
            defaults.set(stored, forKey: AppSettings.Keys.refreshInterval)
            #expect(AppSettings(defaults: defaults).refreshInterval == expected)
        }
    }

    @Test("壊れた値は初期値に戻す (知らない形式・型違い)")
    func ignoresInvalidValues() {
        withDefaults { defaults in
            defaults.set("sparkline", forKey: AppSettings.Keys.style)
            defaults.set("often", forKey: AppSettings.Keys.refreshInterval)
            defaults.set("yes", forKey: AppSettings.Keys.showsPercentText)

            #expect(AppSettings(defaults: defaults) == AppSettings())
        }
    }

    @Test("選べる更新間隔は 1 / 3 / 5 / 10 分で、初期値を含む")
    func intervalChoices() {
        #expect(AppSettings.intervalChoices == [60, 180, 300, 600])
        #expect(AppSettings.intervalChoices.contains(AppSettings().refreshInterval))
    }

    @Test("表示形式はドーナツと棒の 2 種類")
    func styles() {
        #expect(MenuBarStyle.allCases == [.donut, .bar])
    }
}
