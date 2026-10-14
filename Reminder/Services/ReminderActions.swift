import Foundation
import SwiftData

/// 所有修改数据的操作都经过这里：保存后重建通知
@MainActor
enum ReminderActions {
    static func save(_ context: ModelContext) {
        try? context.save()
        NotificationScheduler.reschedule(context: context)
    }

    /// 普通事项：移入已完成。
    /// 重复事项：生成一条已完成的历史记录，原事项顺延到下一次。
    static func complete(_ reminder: Reminder, in context: ModelContext) {
        let now = Date()
        if reminder.recurrence != .none, let due = reminder.dueDate,
           let next = reminder.recurrence.nextDate(after: due, interval: reminder.recurrenceInterval, notBefore: now) {
            let record = Reminder(text: reminder.text, dueDate: due, hasTime: reminder.hasTime, leadDays: reminder.leadDays)
            record.isDone = true
            record.completedAt = now
            context.insert(record)
            for attachment in reminder.sortedAttachments {
                guard let copy = AttachmentStore.duplicate(attachment.fileName) else { continue }
                let a = Attachment(fileName: copy, order: attachment.order)
                context.insert(a)
                a.reminder = record
            }
            reminder.dueDate = next
        } else {
            reminder.isDone = true
            reminder.completedAt = now
        }
        reminder.updatedAt = now
        save(context)
    }

    static func restore(_ reminder: Reminder, in context: ModelContext) {
        reminder.isDone = false
        reminder.completedAt = nil
        reminder.updatedAt = Date()
        save(context)
    }

    static func delete(_ reminder: Reminder, in context: ModelContext) {
        for attachment in reminder.attachments ?? [] {
            AttachmentStore.delete(attachment.fileName)
        }
        context.delete(reminder)
        save(context)
    }
}
