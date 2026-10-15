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
        .confirmationDialog(reminder.isShopping ? "删除这件物品？" : "删除这条提醒？", isPresented: $confirmingDelete, titleVisibility: .visible) {
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
            if reminder.isShopping {
                infoRow("cart", "类别", "待买物品")
                Toggle(isOn: Binding(get: { reminder.shopRecurring },
                                     set: { ShoppingActions.setRecurring(reminder, $0, in: context) })) {
                    Label("循环", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                }
                infoRow("info.circle", "状态", shopStatus)
            } else if let due = reminder.dueDate {
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
                infoRow("checkmark.circle", reminder.isShopping ? "已买于" : "完成于", DueFormat.timestamp(completedAt))
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

    private var shopStatus: String {
        if reminder.isDone { return "已买" }
        if reminder.isShopLater { return "以后检查" }
        return "需要买"
    }

    @ViewBuilder
    private var bottomButton: some View {
        if reminder.isShopping {
            shopButton
        } else {
            reminderButton
        }
    }

    private var shopButton: some View {
        let (title, icon, tint): (String, String, Color) =
            reminder.isDone ? ("恢复为待买", "arrow.uturn.backward", Color.blue)
            : reminder.isShopLater ? ("需要买", "cart.badge.plus", Color.orange)
            : reminder.shopRecurring ? ("以后检查", "clock", Color.gray)
            : ("已买", "checkmark", Color.green)
        return Button {
            if reminder.isDone {
                ReminderActions.restore(reminder, in: context)
            } else {
                ShoppingActions.swipe(reminder, in: context)
            }
            dismiss()
        } label: {
            Label(title, systemImage: icon).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.large)
        .padding()
        .background(.bar)
    }

    private var reminderButton: some View {
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
