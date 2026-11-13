import Foundation
import ServiceManagement

/// ログイン時の自動起動 (システム設定の「ログイン時に開く」に入る)。
/// 登録状態は OS が持つので、アプリ側では保存せず都度読む。
@MainActor
enum LoginItem {
    enum Status: Equatable {
        case enabled
        /// 登録済みだが、システム設定の「ログイン項目」で許可が要る。
        case needsApproval
        case disabled
        /// `.app` として起動していない (`swift run` など)。
        case unavailable
    }

    private static var isAppBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var status: Status {
        guard isAppBundle else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .needsApproval
        // `notFound` は「OS がまだこのアプリを知らない」というだけで、登録すれば使える
        // (署名のない ad-hoc 署名のアプリでも `register()` が成功することを実機で確認した)。
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .unavailable
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
