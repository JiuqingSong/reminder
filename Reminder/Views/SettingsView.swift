import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(AppSettings.notifyMinutesKey) private var notifyMinutes = AppSettings.defaultNotifyMinutes
    @AppStorage(AppSettings.defaultLeadDaysKey) private var defaultLeadDays = 1
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("每日提醒时间", selection: notifyTime, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("每天在这个时间把需要注意的事项汇总成一条通知。")
                }

                Section {
                    Picker("新建时默认提醒", selection: $defaultLeadDays) {
                        ForEach(LeadDays.options, id: \.self) { Text(LeadDays.label($0)).tag($0) }
                    }
                } footer: {
                    Text("每条提醒都可以单独修改。")
                }

                Section("通知权限") {
                    HStack {
                        Text("状态")
                        Spacer()
                        Text(authLabel).foregroundStyle(.secondary)
                    }
                    if authStatus == .denied {
                        Button("前往系统设置开启") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }

                Section {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                authStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            }
            .onChange(of: notifyMinutes) { _, _ in
                NotificationScheduler.reschedule(context: context)
            }
        }
    }

    private var notifyTime: Binding<Date> {
        Binding {
            Calendar.current.date(byAdding: .minute, value: notifyMinutes, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            notifyMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
        }
    }

    private var authLabel: String {
        switch authStatus {
        case .authorized, .provisional, .ephemeral: "已开启"
        case .denied: "已关闭"
        default: "未设置"
        }
    }
}
