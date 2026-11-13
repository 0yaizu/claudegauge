import AppKit
import SwiftUI

/// MenuBarExtra のラベルは Shape を直接描けないため、SwiftUI の View を画像にして渡す。
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
