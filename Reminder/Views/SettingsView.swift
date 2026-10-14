import SwiftUI
import SwiftData
import UserNotifications
import UniformTypeIdentifiers

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
            .sheet(item: $exported) { file in
                ShareSheet(items: [file.url])
                    .presentationDetents([.medium, .large])
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    pendingBackup = try BackupService.read(result.get())
                } catch {
                    message = "无法读取备份文件：\(error.localizedDescription)"
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
            ? "还没有导出过备份。"
            : "上次导出：\(DueFormat.timestamp(Date(timeIntervalSince1970: lastBackupAt)))。"
        return last + "备份是一个包含文字和图片的文件，可以存到“文件”App、iCloud Drive，或者用隔空投送发到 Mac。"
    }

    private func exportBackup() {
        do {
            exported = ExportedFile(url: try BackupService.export(context: context))
            lastBackupAt = Date().timeIntervalSince1970
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    private func restore(_ backup: BackupFile, mode: BackupService.ImportMode) {
        do {
            let count = try BackupService.restore(backup, mode: mode, context: context)
            message = "已恢复 \(count) 条提醒。"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
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
