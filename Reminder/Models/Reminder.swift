import Foundation
import SwiftData

// 所有属性都有默认值、关系可选、无唯一约束：保持与 CloudKit 同步兼容，以后接 iCloud 不用改模型。
@Model
final class Reminder {
    var id: UUID = UUID()
    var text: String = ""
    /// nil 表示常年提醒
    var dueDate: Date?
    /// false 时只使用 dueDate 的日期部分
    var hasTime: Bool = false
    /// 到期前几天开始提醒，0 表示仅当天
    var leadDays: Int = 1
    var recurrenceRaw: String = Recurrence.none.rawValue
    var recurrenceInterval: Int = 1
    var isDone: Bool = false
    var completedAt: Date?
    /// 常年提醒、待买物品的手动排序
    var sortOrder: Double = 0
    /// 待买物品。待买物品没有日期，isDone 表示已买
    var isShopping: Bool = false
    /// 循环物品：左划不会变成已买，只在"需要买"和"以后检查"之间切换
    var shopRecurring: Bool = false
    /// 循环物品的状态：true 需要买，false 以后检查。普通物品不看这个字段
    var shopNeeded: Bool = true
    /// 循环物品改为"以后检查"后满多少天自动转回"需要买"，0 表示不自动
    var shopCycleDays: Int = 0
    /// 循环物品改为"以后检查"的时刻，自动转回的天数从这里算起；"需要买"时为 nil
    var shopLaterSince: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Attachment.reminder)
    var attachments: [Attachment]? = []

    /// 待买物品的购买地点，可以有多个
    var places: [Place]? = []

    init(text: String = "", dueDate: Date? = nil, hasTime: Bool = false, leadDays: Int = 1) {
        self.text = text
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.leadDays = leadDays
    }
}

enum ReminderPhase {
    case pinned     // 常年
    case overdue    // 已过期
    case alerting   // 已进入提醒区间（计入角标）
    case later      // 以后
}

extension Reminder {
    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }

    /// 常年提醒（不含待买物品）
    var isPinned: Bool { dueDate == nil && !isShopping }

    /// 待买物品当前需要买：普通物品未买，或循环物品状态为"需要买"
    var isShopNeeded: Bool { isShopping && !isDone && (!shopRecurring || shopNeeded) }

    /// 循环物品状态为"以后检查"
    var isShopLater: Bool { isShopping && !isDone && shopRecurring && !shopNeeded }

    /// 切换循环物品的状态。所有改 shopNeeded 的地方都走这里，好记下开始"以后检查"的时刻
    func setShopNeeded(_ needed: Bool, now: Date = Date()) {
        if needed {
            shopLaterSince = nil
        } else if shopNeeded || shopLaterSince == nil {
            shopLaterSince = now
        }
        shopNeeded = needed
    }

    /// "以后检查"的循环物品还有几天自动转为"需要买"；没设天数、或不在"以后检查"时为 nil
    func daysUntilShopNeeded(from now: Date = Date()) -> Int? {
        guard isShopLater, shopCycleDays > 0 else { return nil }
        let elapsed = Calendar.current.dayDistance(from: shopLaterSince ?? now, to: now)
        return max(0, shopCycleDays - elapsed)
    }

    var sortedAttachments: [Attachment] {
        (attachments ?? []).sorted { $0.order < $1.order }
    }

    var sortedPlaces: [Place] {
        (places ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    /// 列表和通知里显示的标题：第一行非空文字
    var title: String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        if let line { return line }
        return (attachments?.isEmpty == false) ? String(localized: "［图片］") : String(localized: "（无内容）")
    }

    /// 判断待买物品是否同名：去掉首尾空格，不区分大小写和全半角
    static func shopKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
    }

    func daysUntilDue(from day: Date) -> Int? {
        guard let dueDate else { return nil }
        return Calendar.current.dayDistance(from: day, to: dueDate)
    }

    func phase(on day: Date) -> ReminderPhase {
        guard let days = daysUntilDue(from: day) else { return .pinned }
        if days < 0 { return .overdue }
        if days <= leadDays { return .alerting }
        return .later
    }
}
