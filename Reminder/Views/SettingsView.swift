import SwiftUI
import SwiftData
import UserNotifications
import UniformTypeIdentifiers
import CoreLocation

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(AppSettings.notifyMinutesKey) private var notifyMinutes = AppSettings.defaultNotifyMinutes
    @AppStorage(AppSettings.defaultLeadDaysKey) private var defaultLeadDays = 1
    @AppStorage("lastBackupAt") private var lastBackupAt: Double = 0
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var exported: ExportedFile?
    @State private var importing = false
    @State private var pendingBackup: BackupFile?
    @State private var message: String?
    @State private var showingPlaces = false
    private let location = LocationAuthorization.shared

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

                Section {
                    Button("常用购物地点", systemImage: "mappin.and.ellipse") { showingPlaces = true }
                    HStack {
                        Text("定位权限")
                        Spacer()
                        Text(locationLabel).foregroundStyle(.secondary)
                    }
                    if location.status == .denied || location.status == .restricted {
                        Button("前往系统设置开启") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                } header: {
                    Text("购物地点")
                } footer: {
                    Text("给购物地点开启到店提醒后，到了那里会提醒你可以买的物品。只需要\"使用 App 期间\"的定位权限。")
                }

                Section {
                    Button("导出备份", systemImage: "square.and.arrow.up", action: exportBackup)
                    Button("从备份恢复", systemImage: "square.and.arrow.down") { importing = true }
                } header: {
                    Text("备份")
                } footer: {
                    Text(backupFooter)
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
                    Text("所有提醒都是普通的 iPhone 通知，Apple Watch 会自动显示：iPhone 锁屏或黑屏、手表戴在手上时，通知出现在手表上；正在用 iPhone 时只出现在手机上。这是系统规则，App 无法改变。\n\n是否在手表上显示，在 iPhone 的 Watch App 里设置：我的手表 → 通知 → 瘦子提醒，选\"镜像我的 iPhone\"或关闭。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("打开 Watch App") {
                        if let url = URL(string: "itms-watchs://") { openURL(url) }
                    }
                } header: {
                    Text("Apple Watch")
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
            .sheet(isPresented: $showingPlaces) {
                PlacesView()
            }
            .sheet(item: $exported) { file in
                ShareSheet(items: [file.url])
                    .presentationDetents([.medium, .large])
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    pendingBackup = try BackupService.read(result.get())
                } catch {
                    message = String(localized: "无法读取备份文件：\(error.localizedDescription)")
                }
            }
            .confirmationDialog(
                "从备份恢复",
                isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }),
                titleVisibility: .visible,
                presenting: pendingBackup
            ) { backup in
                Button("合并（保留现有数据）") { restore(backup, mode: .merge) }
                Button("替换全部现有数据", role: .destructive) { restore(backup, mode: .replace) }
            } message: { backup in
                Text("备份中有 \(backup.reminders.count) 条提醒，导出于 \(DueFormat.timestamp(backup.exportedAt))。合并时会跳过已存在的事项。")
            }
            .alert(
                message ?? "",
                isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
            ) {
                Button("好") {}
            }
        }
    }

    private var backupFooter: String {
        let last = lastBackupAt == 0
            ? String(localized: "还没有导出过备份。")
            : String(localized: "上次导出：\(DueFormat.timestamp(Date(timeIntervalSince1970: lastBackupAt)))。")
        return last + String(localized: "备份是一个包含文字和图片的文件，可以存到“文件”App、iCloud Drive，或者用隔空投送发到 Mac。")
    }

    private func exportBackup() {
        do {
            exported = ExportedFile(url: try BackupService.export(context: context))
            lastBackupAt = Date().timeIntervalSince1970
        } catch {
            message = String(localized: "导出失败：\(error.localizedDescription)")
        }
    }

    private func restore(_ backup: BackupFile, mode: BackupService.ImportMode) {
        do {
            let count = try BackupService.restore(backup, mode: mode, context: context)
            message = String(localized: "已恢复 \(count) 条提醒。")
        } catch {
            message = String(localized: "恢复失败：\(error.localizedDescription)")
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

    private var locationLabel: String {
        switch location.status {
        case .authorizedWhenInUse: String(localized: "使用 App 期间")
        case .authorizedAlways: String(localized: "始终")
        case .denied, .restricted: String(localized: "已关闭")
        default: String(localized: "未设置")
        }
    }

    private var authLabel: String {
        switch authStatus {
        case .authorized, .provisional, .ephemeral: String(localized: "已开启")
        case .denied: String(localized: "已关闭")
        default: String(localized: "未设置")
        }
    }
}

struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// 系统分享面板：存储到“文件”、隔空投送等
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
