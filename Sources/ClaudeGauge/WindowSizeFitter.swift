import AppKit
import SwiftUI

/// MenuBarExtra (.window) のウィンドウは、中身が増えると広がるが、減っても元の高さに戻らない。
/// 戻らないと中身の上下に余白が残り、背景のない部分から壁紙が透けて見える。
/// SwiftUI で測った中身の高さに、ウィンドウの高さを合わせる。上端 (メニューバー側) は動かさない。
///
/// - AppKit 側の大きさ (`contentView.fittingSize`) は、このウィンドウでは常に 0 で当てにならない。
/// - 高さは `PreferenceKey` で受け渡さず、`GeometryReader` の中から直接渡す
///   (`onPreferenceChange` は最初の 1 回しか呼ばれなかった)。
struct WindowSizeFitter: NSViewRepresentable {
    /// SwiftUI で測った、中身 (余白を含む) の高さ。
    let height: CGFloat

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        let height = height
        // ウィンドウはビューが画面に載ったあとに決まるので、次の実行ループまで待つ。
        Task { @MainActor [weak view] in
            await Task.yield()
            guard let window = view?.window else { return }
            Self.fit(window, toContentHeight: height)
        }
    }

    @MainActor
    private static func fit(_ window: NSWindow, toContentHeight height: CGFloat) {
        guard height > 0 else { return }
        // 測った高さは小数 (204.48 など) になるので、切り上げてウィンドウ (整数) と比べる。
        let content = NSRect(
            x: 0, y: 0,
            width: window.contentRect(forFrameRect: window.frame).width,
            height: height.rounded(.up)
        )
        let target = window.frameRect(forContentRect: content).height
        let current = window.frame
        guard abs(current.height - target) >= 1 else { return }

        var frame = current
        frame.size.height = target
        // 上端を固定する (frame の原点は左下なので、縮んだ分だけ原点を上げる)。
        frame.origin.y = current.maxY - target
        window.setFrame(frame, display: true, animate: false)
    }
}

extension View {
    /// このビューの高さを測り、その高さにウィンドウを合わせる。
    func fitsWindowToContent() -> some View {
        background {
            GeometryReader { proxy in
                WindowSizeFitter(height: proxy.size.height)
            }
        }
    }
}
