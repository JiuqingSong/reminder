import AppIntents
import SwiftData

/// Siri："用瘦子提醒记一下" → "要提醒什么？" → "明天下午2点去洗车"
struct AddReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "添加提醒"
    static let description = IntentDescription("说一句话添加提醒，会自动识别里面的日期和时间。")

    @Parameter(title: "内容", requestValueDialog: "要提醒什么？")
    var content: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let parsed = SpokenDateParser.parse(content)
        let context = AppModel.container.mainContext

        let reminder = Reminder(text: parsed.text, dueDate: parsed.dueDate,
                                hasTime: parsed.hasTime, leadDays: AppSettings.defaultLeadDays)
        // 新加入常年列表的排在最后
        if parsed.dueDate == nil { reminder.sortOrder = Date().timeIntervalSince1970 }
        context.insert(reminder)
        try context.save()
        // 等通知排好再返回，Siri 结束后 App 可能马上被挂起
        await NotificationScheduler.reschedule(context: context).value

        return .result(dialog: IntentDialog(stringLiteral: confirmation(parsed)))
    }

    private func confirmation(_ parsed: SpokenDateParser.Result) -> String {
        guard let due = parsed.dueDate else {
            return "已添加到常年提醒：\(parsed.text)"
        }
        let days = Calendar.current.dayDistance(from: Date(), to: due)
        var when = (0...2).contains(days)
            ? DueFormat.relative(days: days)
            : DueFormat.date(due, hasTime: false)
        if parsed.hasTime {
            when += " " + DueFormat.clock(due)
        }
        return "已添加：\(when)，\(parsed.text)"
    }
}

struct ReminderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddReminderIntent(),
            phrases: [
                "用\(.applicationName)记一下",
                "用\(.applicationName)添加",
                "用\(.applicationName)添加待办",
                "用\(.applicationName)添加提醒",
                "\(.applicationName)记一下",
                "\(.applicationName)添加",
                "\(.applicationName)添加待办",
                "\(.applicationName)添加提醒",
            ],
            shortTitle: "添加提醒",
            systemImageName: "plus.circle"
        )
    }
}
