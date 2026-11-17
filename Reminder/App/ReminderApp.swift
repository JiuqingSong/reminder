import SwiftUI
import SwiftData
import UserNotifications
import CoreData
import Combine

@main
struct ReminderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(AppModel.container)
        // 系统不定期在后台唤醒：循环物品满天数转回需要买、重建通知和小组件
        .backgroundTask(.appRefresh(BackgroundRefresh.taskID)) {
            await BackgroundRefresh.run()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // App 在前台时也显示通知横幅
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .badge, .sound]
    }

    // 点击到店提醒：打开待买页，筛选到通知对应的地点
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let openShopping = userInfo[NotificationScheduler.openShoppingKey] as? Bool ?? false
        let placeID = (userInfo[NotificationScheduler.placeIDKey] as? String).flatMap(UUID.init(uuidString:))
        if openShopping {
            await MainActor.run { Navigator.shared.openShopping(placeID: placeID) }
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()

    var body: some View {
        ReminderListView(now: now)
            .task {
                AttachmentStore.reconcile(context: context)
                await NotificationScheduler.requestAuthorization()
                refresh()
            }
            // iCloud 同步来了别的设备上的修改：补齐图片文件，重建通知和小组件。
            // 同步时这个通知会连着来好几次，等安静一秒再处理
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
                .debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in
                AttachmentStore.reconcile(context: context)
                refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    now = Date()
                    refresh()
                } else if phase == .background {
                    BackgroundRefresh.schedule()
                }
            }
            // 跨过午夜、修改系统时间时刷新分组和角标
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                now = Date()
                refresh()
            }
    }

    private func refresh() {
        BackgroundRefresh.refresh(context: context)
    }
}
