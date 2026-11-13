import AppKit
import SwiftUI

/// ステータス項目のボタンには画像しか渡せないため、SwiftUI の View (ドーナツや横棒) を画像にする。
/// 色付き (輪を警告色で塗る) なのでテンプレート画像にはしない。
@MainActor
enum StatusImageRenderer {
    static func render(_ content: some View) -> NSImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: .zero)
        image.isTemplate = false
        return image
    }
}
