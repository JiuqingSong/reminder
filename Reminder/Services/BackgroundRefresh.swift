import Foundation
import SwiftData
import BackgroundTasks

/// 定时刷新：循环物品满天数转回"需要买"，然后重建通知、角标、到店提醒和小组件。
/// App 在前台时由 RootView 调用；不在前台时靠系统的后台刷新，
/// 每次进入后台都申请"零点过后"唤醒一次（系统会根据使用习惯决定实际时间，不保证准时）。
@MainActor
enum BackgroundRefresh {
    /// 和 Info.plist 的 BGTaskSchedulerPermittedIdentifiers 一致
    nonisolated static let taskID = "com.songthin.willdo.refresh"

    static func refresh(context: ModelContext) {
        if ShoppingActions.applyCycles(in: context) {
            try? context.save()
        }
        NotificationScheduler.reschedule(context: context)
    }

    static func run() async {
        schedule()
        let context = AppModel.container.mainContext
        if ShoppingActions.applyCycles(in: context) {
            try? context.save()
        }
        // 等通知排好再返回，返回后 App 马上会被挂起
        await NotificationScheduler.reschedule(context: context).value
    }

    nonisolated static func schedule() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = tomorrow.addingTimeInterval(5 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
