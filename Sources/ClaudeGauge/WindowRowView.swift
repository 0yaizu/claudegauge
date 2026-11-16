import ClaudeGaugeCore
import SwiftUI

/// 1 枠分の表示。文字列と割合は `WindowRowModel` が組み立て済みで、ここでは並べるだけ。
///
///     5h session                 60%  Forecast: 120% (100% at 21:40)
///     [██████████░░░░░░░░░░]
///     Resets at 21:40 (3h30m remain)
struct WindowRowView: View {
    let row: WindowRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(row.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text(row.percentText)
                        .fontWeight(.semibold)
                    Text(row.forecastText)
                        .foregroundStyle(.secondary)
                    if let reach = row.reachText {
                        Text(reach)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12).monospacedDigit())
                .lineLimit(1)
            }

            UsageBar(fraction: row.fraction, level: row.level)

            if let resets = row.resetsText {
                Text(resets)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
