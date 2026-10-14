import SwiftUI
import SwiftData
import UserNotifications

@main
struct ReminderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Reminder.self, Attachment.self])
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
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()

    var body: some View {
        ReminderListView(now: now)
            .task {
                await NotificationScheduler.requestAuthorization()
                NotificationScheduler.reschedule(context: context)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    now = Date()
                    NotificationScheduler.reschedule(context: context)
                }
            }
            // 跨过午夜、修改系统时间时刷新分组和角标
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                now = Date()
                NotificationScheduler.reschedule(context: context)
            }
    }
}
