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
    /// 常年提醒的手动排序
    var sortOrder: Double = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Attachment.reminder)
    var attachments: [Attachment]? = []

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

    var isPinned: Bool { dueDate == nil }

    var sortedAttachments: [Attachment] {
        (attachments ?? []).sorted { $0.order < $1.order }
    }

    /// 列表和通知里显示的标题：第一行非空文字
    var title: String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        if let line { return line }
        return (attachments?.isEmpty == false) ? "［图片］" : "（无内容）"
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

extension Calendar {
    /// 两个时刻之间相差的自然日数（忽略时分）
    func dayDistance(from a: Date, to b: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: a), to: startOfDay(for: b)).day ?? 0
    }
}
