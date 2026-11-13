import Foundation

public enum UsageMapper {
    private static let scopedKind = "weekly_scoped"

    public static func snapshot(from response: UsageResponse, fetchedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            fiveHour: window(response.fiveHour),
            weekly: window(response.sevenDay),
            scopedLimits: (response.limits ?? []).compactMap(scopedLimit),
            breakdown: (response.sevenDayBreakdown?.rows ?? []).compactMap(breakdownRow),
            fetchedAt: fetchedAt
        )
    }

    private static func window(_ window: UsageResponse.Window?) -> WindowUsage? {
        guard let utilization = window?.utilization else { return nil }
        return WindowUsage(utilization: utilization, resetsAt: window?.resetsAt.flatMap(FlexibleISO8601.parse))
    }

    private static func scopedLimit(_ limit: UsageResponse.Limit) -> ScopedLimit? {
        guard limit.kind == scopedKind,
              let name = limit.scope?.model?.displayName,
              let percent = limit.percent
        else { return nil }
        return ScopedLimit(name: name, percent: percent, resetsAt: limit.resetsAt.flatMap(FlexibleISO8601.parse))
    }

    private static func breakdownRow(_ row: UsageResponse.Breakdown.Row) -> BreakdownRow? {
        guard let key = row.key, let percent = row.percent else { return nil }
        return BreakdownRow(key: key, displayName: row.displayName ?? key, percent: percent)
    }
}
