import AppKit
import ClaudeGaugeCore
import SwiftUI

/// 取得ループ・Reload・設定を受け持つ。表示内容の組み立ては Core のモデルに任せる。
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state = UsageState() {
        didSet { scheduleExpiryTick() }
    }
    /// 表示用の現在時刻。枠のリセット時刻を過ぎた瞬間に更新され、メニューバーの表示を「—」へ切り替える。
    @Published private(set) var now = Date()
    @Published private(set) var isReloading = false
    @Published private(set) var loginItemStatus = LoginItem.status
    @Published private(set) var loginItemError: String?

    /// 変更するとすぐ保存し、更新間隔が変わった場合は次の取得までの待ち時間を計算し直す。
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: defaults)
            if settings.refreshInterval != oldValue.refreshInterval { restartRefreshLoop() }
        }
    }

    private let service: UsageService
    private let defaults: UserDefaults
    private var refreshLoop: Task<Void, Never>?
    private var expiryTick: Task<Void, Never>?

    /// 前回の使用率・試行時刻・429 の連続回数を引き継ぐ。
    /// 取得するのは、自動更新の時刻が来たときと、Reload を押したときだけ。起動のたびには取得しない。
    init(defaults: UserDefaults = .standard) {
        let store = UserDefaultsUsageStore(defaults: defaults)
        let restored = UsageState(persisted: store.load())
        service = UsageService(
            credentials: KeychainCredentialSource(),
            api: UsageAPIClient(),
            initialState: restored,
            store: store
        )
        self.defaults = defaults
        state = restored
        settings = AppSettings(defaults: defaults)
        restartRefreshLoop()
        scheduleExpiryTick()
    }

    /// 手動の Reload。前回の試行から 60 秒未満なら Core 側で拒否される。
    func reload() async {
        guard !isReloading else { return }
        isReloading = true
        defer { isReloading = false }
        apply(await service.reload())
        restartRefreshLoop()  // 試行時刻が進んだので、次の自動更新までの待ち時間を計算し直す
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't change Launch at login."
        }
        loginItemStatus = LoginItem.status
    }

    /// 設定を開いたとき、システム設定側で変えられた登録状態に追従する。
    func refreshLoginItemStatus() {
        loginItemStatus = LoginItem.status
    }

    private func refresh() async {
        apply(await service.refresh())
    }

    /// `@Published` は同じ値を代入しても通知するため、変わったときだけ代入する
    /// (メニューバーの画像の描き直しが走る)。
    private func apply(_ newState: UsageState) {
        if newState != state { state = newState }
    }

    /// 前回の試行から間隔が経った時点で取得する (前回の試行時刻は再起動しても引き継ぐ)。
    /// 前回の取得から間隔が経っていれば、起動直後でもすぐ取得する。429 が続くと間隔が延びる。
    private func restartRefreshLoop() {
        refreshLoop?.cancel()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = await service.nextInterval(base: settings.refreshInterval)
                // 取得中の試行も含めた時刻を、サービス側から読む (表示用の state は取得の完了まで古いまま)。
                let delay = RefreshPolicy.delayUntilNextRefresh(
                    lastAttemptAt: await service.state.lastAttemptAt, interval: interval, now: Date()
                )
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }

    /// 次のリセット時刻になったら表示を更新する (リセット済みの枠を「—」に切り替えるため)。
    private func scheduleExpiryTick() {
        expiryTick?.cancel()
        now = Date()
        guard let next = state.snapshot?.nextResetAt(after: now) else { return }
        expiryTick = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0) + 0.5))
            guard !Task.isCancelled else { return }
            self?.scheduleExpiryTick()
        }
    }
}
