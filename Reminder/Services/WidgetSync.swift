import Foundation
import SwiftData
import WidgetKit

/// 把未完成的提醒写给小组件。内容没变时不写、不刷新，省小组件的刷新次数。
@MainActor
enum WidgetSync {
    private static var last: WidgetSnapshot?

    static func update(context: ModelContext) {
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.isDone == false && $0.isShopping == false })
        let active = (try? context.fetch(descriptor)) ?? []
        let pinned = active.filter(\.isPinned)
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
        let dated = active.filter { $0.dueDate != nil }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let snapshot = WidgetSnapshot(items: (pinned + dated).map {
            WidgetSnapshot.Item(title: $0.title, due: $0.dueDate, hasTime: $0.hasTime, leadDays: $0.leadDays)
        })
        guard snapshot != last else { return }
        if snapshot.save() {
            last = snapshot
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
        }
    }
}
