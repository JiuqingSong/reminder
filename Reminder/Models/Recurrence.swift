import Foundation

enum Recurrence: String, CaseIterable, Identifiable {
    case none, daily, weekly, monthly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: String(localized: "不重复")
        case .daily: String(localized: "每天")
        case .weekly: String(localized: "每周")
        case .monthly: String(localized: "每月")
        case .yearly: String(localized: "每年")
        }
    }

    func description(interval: Int) -> String {
        guard interval > 1 else { return label }
        return switch self {
        case .none: label
        case .daily: String(localized: "每\(interval)天")
        case .weekly: String(localized: "每\(interval)周")
        case .monthly: String(localized: "每\(interval)个月")
        case .yearly: String(localized: "每\(interval)年")
        }
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
        days == 0 ? String(localized: "仅当天") : String(localized: "提前\(days)天")
    }
}
