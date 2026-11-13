import AppKit
import SwiftUI

/// このビューが載っているウィンドウが、画面から消えたとき (ポップオーバーを閉じたとき) に呼ぶ。
/// MenuBarExtra (.window) のウィンドウは閉じても中身の SwiftUI の状態が残るため、
/// 設定パネルの開閉のような「開くたびに初期状態に戻したい」状態を、ここで戻す。
/// 閉じた後 (見えていない間) に戻すので、次に開いたとき、元の状態が一瞬見えることがない。
///
/// キーウィンドウでなくなったとき (`didResignKey`) ではなく、見えなくなったとき (`occlusionState`) を使う。
/// ポップアップメニュー (更新間隔の Picker など) を開いただけで、設定パネルが閉じないようにするため。
struct WindowHiddenObserver: NSViewRepresentable {
    let onHidden: @MainActor () -> Void

    func makeNSView(context: Context) -> ObserverView {
        ObserverView(onHidden: onHidden)
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onHidden = onHidden
    }

    final class ObserverView: NSView {
        var onHidden: @MainActor () -> Void
        private var token: NSObjectProtocol?

        init(onHidden: @escaping @MainActor () -> Void) {
            self.onHidden = onHidden
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObserver()
            guard let window else { return }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let window, !window.occlusionState.contains(.visible) else { return }
                    self?.onHidden()
                }
            }
        }

        private func removeObserver() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
        }

        isolated deinit { removeObserver() }
    }
}

extension View {
    /// ウィンドウが見えなくなったときに `action` を呼ぶ。
    func onWindowHidden(perform action: @escaping @MainActor () -> Void) -> some View {
        background { WindowHiddenObserver(onHidden: action) }
    }
}
