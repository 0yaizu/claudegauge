// アプリアイコン (採用: A) と、不採用の候補 (B〜E) を PNG に書き出す開発用スクリプト (アプリ本体には含めない)。
//   swiftc -swift-version 5 -o /tmp/make_icon make_icon.swift && /tmp/make_icon <出力ディレクトリ>
// 採用した icon-A-Rings.png を design/AppIcon-1024.png に置き、iconutil で Resources/AppIcon.icns にする。
import AppKit
import SwiftUI

// MARK: - 描画の部品 (座標は 1024x1024 のキャンバス。角度は度で、画面上で時計回りに増える)

typealias Ctx = GraphicsContext

func arcPath(center: CGPoint, r: CGFloat, from: Double, to: Double) -> Path {
    var p = Path()
    let steps = max(2, Int(abs(to - from) * 2))
    for i in 0...steps {
        let a = (from + (to - from) * Double(i) / Double(steps)) * .pi / 180
        let pt = CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    return p
}

func strokeArc(_ ctx: inout Ctx, center: CGPoint, r: CGFloat, from: Double, to: Double, width: CGFloat, shading: GraphicsContext.Shading) {
    ctx.stroke(arcPath(center: center, r: r, from: from, to: to), with: shading,
               style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
}

func conic(_ colors: [Color], center: CGPoint, from: Double) -> GraphicsContext.Shading {
    .conicGradient(Gradient(colors: colors), center: center, angle: .degrees(from))
}

/// 円弧用の円周グラデーション。始点の丸いキャップは、始点より手前にはみ出す。
/// 円周を一周するグラデーションは、その手前で終点側の色に回り込み、キャップが単色の別の色になってしまう。
/// そこで、始点の手前 (キャップの範囲) だけを始点の色にそろえる。境界は、円弧が通らない側に置く。
func arcShading(_ colors: [Color], center: CGPoint, from: Double, r: CGFloat, width: CGFloat) -> GraphicsContext.Shading {
    let capDegrees = asin(Double(width / 2 / r)) * 180 / .pi + 2
    let usable = 1 - capDegrees / 360
    var stops = colors.enumerated().map { index, color in
        Gradient.Stop(color: color, location: usable * Double(index) / Double(colors.count - 1))
    }
    stops.append(Gradient.Stop(color: colors[0], location: usable))
    stops.append(Gradient.Stop(color: colors[0], location: 1))
    return .conicGradient(Gradient(stops: stops), center: center, angle: .degrees(from))
}

/// macOS のアイコンの枠 (1024 の中に 824 の角丸を置く)。
func drawBody(_ ctx: inout Ctx, fill: GraphicsContext.Shading) -> Path {
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let body = RoundedRectangle(cornerRadius: 185, style: .continuous).path(in: rect)
    ctx.drawLayer { layer in
        layer.addFilter(.shadow(color: .black.opacity(0.30), radius: 24, x: 0, y: 16))
        layer.fill(body, with: fill)
    }
    ctx.stroke(body, with: .color(.white.opacity(0.14)), lineWidth: 3)
    return body
}

func linear(_ colors: [Color], _ a: CGPoint, _ b: CGPoint) -> GraphicsContext.Shading {
    .linearGradient(Gradient(colors: colors), startPoint: a, endPoint: b)
}

let c = CGPoint(x: 512, y: 512)

// MARK: - 5 案

/// A: 入れ子リング (メニューバーのドーナツと同じ)
func drawA(_ ctx: inout Ctx) {
    _ = drawBody(&ctx, fill: linear([Color(red: 0.13, green: 0.17, blue: 0.25), Color(red: 0.05, green: 0.07, blue: 0.11)], CGPoint(x: 300, y: 100), CGPoint(x: 700, y: 924)))
    let outer: (CGFloat, Double) = (292, 0.68), inner: (CGFloat, Double) = (188, 0.38)
    let width: CGFloat = 72
    for r in [outer.0, inner.0] { strokeArc(&ctx, center: c, r: r, from: 0, to: 360, width: width, shading: .color(.white.opacity(0.10))) }
    let green = [Color(red: 0.42, green: 0.93, blue: 0.62), Color(red: 0.13, green: 0.77, blue: 0.37)]
    let amber = [Color(red: 1.0, green: 0.85, blue: 0.40), Color(red: 1.0, green: 0.62, blue: 0.11)]
    let endOuter = -90 + 360 * outer.1, endInner = -90 + 360 * inner.1
    ctx.drawLayer { layer in   // 発光
        layer.addFilter(.blur(radius: 22)); layer.opacity = 0.55
        strokeArc(&layer, center: c, r: outer.0, from: -90, to: endOuter, width: width, shading: arcShading(green, center: c, from: -90, r: outer.0, width: width))
        strokeArc(&layer, center: c, r: inner.0, from: -90, to: endInner, width: width, shading: arcShading(amber, center: c, from: -90, r: inner.0, width: width))
    }
    strokeArc(&ctx, center: c, r: outer.0, from: -90, to: endOuter, width: width, shading: arcShading(green, center: c, from: -90, r: outer.0, width: width))
    strokeArc(&ctx, center: c, r: inner.0, from: -90, to: endInner, width: width, shading: arcShading(amber, center: c, from: -90, r: inner.0, width: width))
}

/// B: 計器 (針つきの半円メーター)
func drawB(_ ctx: inout Ctx) {
    _ = drawBody(&ctx, fill: linear([Color(red: 1.0, green: 0.62, blue: 0.38), Color(red: 0.92, green: 0.33, blue: 0.22), Color(red: 0.60, green: 0.14, blue: 0.22)], CGPoint(x: 160, y: 100), CGPoint(x: 800, y: 924)))
    let center = CGPoint(x: 512, y: 548)
    let start = 150.0, sweep = 240.0, level = 0.70
    for i in 0...10 {   // 目盛り
        let a = (start + sweep * Double(i) / 10) * .pi / 180
        var p = Path()
        p.move(to: CGPoint(x: center.x + 318 * CGFloat(cos(a)), y: center.y + 318 * CGFloat(sin(a))))
        p.addLine(to: CGPoint(x: center.x + 346 * CGFloat(cos(a)), y: center.y + 346 * CGFloat(sin(a))))
        ctx.stroke(p, with: .color(.white.opacity(i % 5 == 0 ? 0.85 : 0.45)), style: StrokeStyle(lineWidth: i % 5 == 0 ? 14 : 9, lineCap: .round))
    }
    strokeArc(&ctx, center: center, r: 262, from: start, to: start + sweep, width: 66, shading: .color(.white.opacity(0.24)))
    strokeArc(&ctx, center: center, r: 262, from: start, to: start + sweep * level, width: 66, shading: .color(.white))
    let na = (start + sweep * level) * .pi / 180
    var needle = Path()
    needle.move(to: center)
    needle.addLine(to: CGPoint(x: center.x + 200 * CGFloat(cos(na)), y: center.y + 200 * CGFloat(sin(na))))
    ctx.drawLayer { layer in
        layer.addFilter(.shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6))
        layer.stroke(needle, with: .color(.white), style: StrokeStyle(lineWidth: 30, lineCap: .round))
        layer.fill(Path(ellipseIn: CGRect(x: center.x - 50, y: center.y - 50, width: 100, height: 100)), with: .color(.white))
    }
    ctx.fill(Path(ellipseIn: CGRect(x: center.x - 20, y: center.y - 20, width: 40, height: 40)), with: .color(Color(red: 0.78, green: 0.24, blue: 0.20)))
}

/// C: 横棒 2 本 (メニューバーのバー表示と同じ)
func drawC(_ ctx: inout Ctx) {
    _ = drawBody(&ctx, fill: linear([Color(red: 0.99, green: 0.99, blue: 1.0), Color(red: 0.86, green: 0.90, blue: 0.96)], CGPoint(x: 400, y: 100), CGPoint(x: 624, y: 924)))
    let x0: CGFloat = 232, w: CGFloat = 560, h: CGFloat = 100
    let rows: [(CGFloat, Double, [Color])] = [
        (380, 0.74, [Color(red: 0.20, green: 0.83, blue: 0.60), Color(red: 0.06, green: 0.65, blue: 0.45)]),
        (544, 0.36, [Color(red: 0.99, green: 0.80, blue: 0.22), Color(red: 0.96, green: 0.58, blue: 0.06)]),
    ]
    for (y, f, colors) in rows {
        ctx.fill(Capsule().path(in: CGRect(x: x0, y: y, width: w, height: h)), with: .color(Color(red: 0.80, green: 0.84, blue: 0.91)))
        let fill = Capsule().path(in: CGRect(x: x0, y: y, width: w * f, height: h))
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: colors[1].opacity(0.45), radius: 16, x: 0, y: 8))
            layer.fill(fill, with: linear(colors, CGPoint(x: x0, y: y), CGPoint(x: x0 + w * f, y: y)))
        }
        ctx.fill(Capsule().path(in: CGRect(x: x0 + 14, y: y + 12, width: w * f - 28, height: 18)), with: .color(.white.opacity(0.28)))
    }
}

/// D: C の字のリング (ゲージ + Claude の頭文字)
func drawD(_ ctx: inout Ctx) {
    _ = drawBody(&ctx, fill: linear([Color(red: 0.24, green: 0.17, blue: 0.52), Color(red: 0.07, green: 0.05, blue: 0.20)], CGPoint(x: 250, y: 100), CGPoint(x: 780, y: 924)))
    let from = 42.0, to = 318.0, r: CGFloat = 250
    strokeArc(&ctx, center: c, r: 120, from: 0, to: 360, width: 16, shading: .color(.white.opacity(0.10)))
    let colors = [Color(red: 1.0, green: 0.95, blue: 0.84), Color(red: 1.0, green: 0.70, blue: 0.54), Color(red: 1.0, green: 0.48, blue: 0.35)]
    ctx.drawLayer { layer in
        layer.addFilter(.blur(radius: 26)); layer.opacity = 0.5
        strokeArc(&layer, center: c, r: r, from: from, to: to, width: 128, shading: arcShading(colors, center: c, from: from, r: r, width: 128))
    }
    strokeArc(&ctx, center: c, r: r, from: from, to: to, width: 128, shading: arcShading(colors, center: c, from: from, r: r, width: 128))
    let a = to * .pi / 180   // 針の先に当たる光点
    let tip = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
    ctx.drawLayer { layer in
        layer.addFilter(.shadow(color: Color(red: 1.0, green: 0.6, blue: 0.4).opacity(0.9), radius: 18, x: 0, y: 0))
        layer.fill(Path(ellipseIn: CGRect(x: tip.x - 26, y: tip.y - 26, width: 52, height: 52)), with: .color(.white))
    }
}

/// E: ガラス (macOS 26 の Liquid Glass 風)
func drawE(_ ctx: inout Ctx) {
    _ = drawBody(&ctx, fill: linear([Color(red: 0.22, green: 0.50, blue: 0.96), Color(red: 0.24, green: 0.80, blue: 0.86), Color(red: 0.12, green: 0.30, blue: 0.72)], CGPoint(x: 120, y: 100), CGPoint(x: 880, y: 924)))
    let disc = Path(ellipseIn: CGRect(x: c.x - 318, y: c.y - 318, width: 636, height: 636))
    ctx.drawLayer { layer in
        layer.addFilter(.shadow(color: .black.opacity(0.22), radius: 26, x: 0, y: 18))
        layer.fill(disc, with: linear([.white.opacity(0.34), .white.opacity(0.10)], CGPoint(x: 260, y: 200), CGPoint(x: 760, y: 840)))
    }
    ctx.stroke(disc, with: linear([.white.opacity(0.95), .white.opacity(0.10), .white.opacity(0.45)], CGPoint(x: 240, y: 190), CGPoint(x: 800, y: 850)), lineWidth: 7)
    for (r, f, a) in [(CGFloat(228), 0.66, 0.96), (CGFloat(140), 0.36, 0.80)] as [(CGFloat, Double, Double)] {
        strokeArc(&ctx, center: c, r: r, from: 0, to: 360, width: 46, shading: .color(.white.opacity(0.22)))
        strokeArc(&ctx, center: c, r: r, from: -90, to: -90 + 360 * f, width: 46, shading: .color(.white.opacity(a)))
    }
    ctx.drawLayer { layer in   // 左上の反射
        layer.addFilter(.blur(radius: 10)); layer.opacity = 0.6
        strokeArc(&layer, center: c, r: 296, from: 195, to: 262, width: 14, shading: .color(.white))
    }
}

// MARK: - 出力

let candidates: [(String, String, (inout Ctx) -> Void)] = [
    ("A", "Rings", drawA), ("B", "Dial", drawB), ("C", "Bars", drawC), ("D", "C-gauge", drawD), ("E", "Glass", drawE),
]

struct IconView: View {
    let draw: (inout Ctx) -> Void
    let size: CGFloat
    var body: some View {
        Canvas { ctx, canvas in
            var ctx = ctx
            ctx.scaleBy(x: canvas.width / 1024, y: canvas.height / 1024)
            draw(&ctx)
        }
        .frame(width: size, height: size)
    }
}

@MainActor func writePNG<V: View>(_ view: V, to url: URL) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let cg = renderer.cgImage else { print("render failed:", url.lastPathComponent); return }
    let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    try? data?.write(to: url)
    print("wrote", url.lastPathComponent, "\(cg.width)x\(cg.height)")
}

@MainActor func main() {
    let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (id, name, draw) in candidates {
        writePNG(IconView(draw: draw, size: 1024), to: out.appending(path: "icon-\(id)-\(name).png"))
    }
    // 見比べ用の一覧: 大 (200) と、実際の使用サイズ (64 / 32 / 16) を明るい面と暗い面で並べる
    let sheet = VStack(spacing: 26) {
        HStack(alignment: .top, spacing: 28) {
            ForEach(candidates, id: \.0) { id, name, draw in
                VStack(spacing: 8) { IconView(draw: draw, size: 200); Text("\(id)  \(name)").font(.system(size: 15, weight: .semibold)) }
            }
        }
        // 実際の使用サイズ (64 / 32 / 16) を、明るい面と暗い面で見比べる (メニューバーや Dock の背景は両方ありうる)
        VStack(spacing: 14) {
            ForEach([false, true], id: \.self) { dark in
                HStack(spacing: 40) {
                    ForEach(candidates, id: \.0) { id, _, draw in
                        HStack(alignment: .bottom, spacing: 8) {
                            IconView(draw: draw, size: 64); IconView(draw: draw, size: 32); IconView(draw: draw, size: 16)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color.white, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    .padding(32)
    .frame(width: 1240)
    .background(Color(red: 0.91, green: 0.92, blue: 0.94))
    .environment(\.colorScheme, .light)
    writePNG(sheet, to: out.appending(path: "contact-sheet.png"))
}

MainActor.assumeIsolated { main() }
