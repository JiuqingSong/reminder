import SwiftUI
import SwiftData

struct ReminderDetailView: View {
    let reminder: Reminder
    let now: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var viewerStart: ImageViewerStart?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !reminder.text.isEmpty {
                    Text(ContentDetector.attributed(reminder.text))
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                let attachments = reminder.sortedAttachments
                if !attachments.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                            Button {
                                viewerStart = ImageViewerStart(index: index)
                            } label: {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        if let thumb = AttachmentStore.thumbnail(attachment.fileName) {
                                            Image(uiImage: thumb).resizable().scaledToFill()
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                infoCard
            }
            .padding()
        }
        // 地址交给 Google 地图，其余链接（网页、电话）走系统默认处理
        .environment(\.openURL, OpenURLAction { url in
            if let address = ContentDetector.address(from: url) {
                MapOpener.open(address: address)
                return .handled
            }
            return .systemAction
        })
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") { editing = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("删除", systemImage: "trash", role: .destructive) {
                        confirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomButton
        }
        .sheet(isPresented: $editing) {
            ReminderEditView(reminder: reminder)
        }
        .fullScreenCover(item: $viewerStart) { start in
            ImageViewer(fileNames: reminder.sortedAttachments.map(\.fileName), startIndex: start.index)
        }
        .confirmationDialog("删除这条提醒？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                dismiss()
                // 等返回动画结束再删，避免视图访问已删除的对象
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    ReminderActions.delete(reminder, in: context)
                }
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let due = reminder.dueDate {
                infoRow("calendar", "到期", DueFormat.date(due, hasTime: reminder.hasTime, now: now))
                if !reminder.isDone, let days = reminder.daysUntilDue(from: now) {
                    infoRow("hourglass", "剩余", DueFormat.relative(days: days))
                }
                infoRow("bell", "提醒", LeadDays.label(reminder.leadDays))
                if reminder.recurrence != .none {
                    infoRow("repeat", "重复", reminder.recurrence.description(interval: reminder.recurrenceInterval))
                }
            } else {
                infoRow("pin", "类型", "常年提醒")
            }
            if let completedAt = reminder.completedAt {
                infoRow("checkmark.circle", "完成于", DueFormat.timestamp(completedAt))
            }
            infoRow("clock", "创建于", DueFormat.timestamp(reminder.createdAt))
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func infoRow(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private var bottomButton: some View {
        Button {
            if reminder.isDone {
                ReminderActions.restore(reminder, in: context)
            } else {
                ReminderActions.complete(reminder, in: context)
            }
            dismiss()
        } label: {
            Label(reminder.isDone ? "恢复为待办" : "标记完成",
                  systemImage: reminder.isDone ? "arrow.uturn.backward" : "checkmark")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(reminder.isDone ? .blue : .green)
        .controlSize(.large)
        .padding()
        .background(.bar)
    }
}

struct ImageViewerStart: Identifiable {
    let index: Int
    var id: Int { index }
}
