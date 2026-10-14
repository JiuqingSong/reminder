import Foundation

enum Recurrence: String, CaseIterable, Identifiable {
    case none, daily, weekly, monthly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "不重复"
        case .daily: "每天"
        case .weekly: "每周"
        case .monthly: "每月"
        case .yearly: "每年"
        }
    }

    var unitLabel: String {
        switch self {
        case .none: ""
        case .daily: "天"
        case .weekly: "周"
        case .monthly: "个月"
        case .yearly: "年"
        }
    }

    func description(interval: Int) -> String {
        interval <= 1 ? label : "每\(interval)\(unitLabel)"
    }

    private func advance(_ date: Date, periods: Int, calendar: Calendar) -> Date? {
        switch self {
        case .none: nil
        case .daily: calendar.date(byAdding: .day, value: periods, to: date)
        case .weekly: calendar.date(byAdding: .day, value: periods * 7, to: date)
        case .monthly: calendar.date(byAdding: .month, value: periods, to: date)
        case .yearly: calendar.date(byAdding: .year, value: periods, to: date)
        }
    }

    /// 下一次到期日：从 base 按周期递增，取第一个不早于今天的日期。
    /// 每次都从 base 直接加 k 个周期，避免 1/31 → 2/28 → 3/28 这样的日期漂移。
    func nextDate(after base: Date, interval: Int, notBefore today: Date, calendar: Calendar = .current) -> Date? {
        guard self != .none else { return nil }
        let step = max(1, interval)
        let todayStart = calendar.startOfDay(for: today)
        for k in 1...5000 {
            guard let candidate = advance(base, periods: step * k, calendar: calendar) else { return nil }
            if calendar.startOfDay(for: candidate) >= todayStart { return candidate }
        }
        return nil
    }
}

enum LeadDays {
    static let options = [0, 1, 2, 3, 5, 7, 14, 30]

    static func label(_ days: Int) -> String {
        days == 0 ? "仅当天" : "提前\(days)天"
    }
}
