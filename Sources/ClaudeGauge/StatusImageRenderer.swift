import AppKit
import SwiftUI

@MainActor
enum StatusImageRenderer {
    /// HiDPIでないモニターに接続するとretinaディスプレイ側のアイコンの解像度が落ちるのでサイズを2倍にしてレンダリングする
    private static let scale: CGFloat = 2

    static func render(_ content: some View) -> NSImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = Self.scale
        let image = renderer.nsImage ?? NSImage(size: .zero)
        image.isTemplate = false
        return image
    }
}
