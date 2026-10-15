import SwiftUI
import SwiftData
import PhotosUI

struct ReminderEditView: View {
    /// nil 表示新建
    let reminder: Reminder?
    /// 新建时：true 表示新建待买物品
    var newShoppingItem = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.defaultLeadDaysKey) private var defaultLeadDays = 1

    @State private var text = ""
    @State private var hasDate = false
    @State private var date = Date()
    @State private var hasTime = false
    @State private var leadDays = 1
    @State private var recurrence: Recurrence = .none
    @State private var interval = 1
    @State private var images: [DraftImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var shopRecurring = false
    @State private var shopNeeded = true
    @State private var duplicate: Reminder?
    @State private var loaded = false
    @FocusState private var textFocused: Bool

    private var isShopping: Bool { reminder?.isShopping ?? newShoppingItem }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(isShopping ? "物品名称（第一行），可以附上链接、说明" : "写点什么……链接、地址会自动识别",
                              text: $text, axis: .vertical)
                        .lineLimit(isShopping ? 2...20 : 4...20)
                        .focused($textFocused)
                }

                imageSection

                if isShopping {
                    shopSection
                } else {
                    dateSection
                    if hasDate {
                        reminderSection
                    }
                }
            }
            .navigationTitle(isShopping
                             ? (reminder == nil ? "新物品" : "编辑物品")
                             : (reminder == nil ? "新提醒" : "编辑提醒"))
            .alert("已有同名物品", isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } }),
                   presenting: duplicate) { existing in
                Button("仍然添加") { save() }
                if existing.isShopLater {
                    Button("不添加，把原有的改为需要买") {
                        ShoppingActions.setNeeded(existing, true, in: context)
                        dismiss()
                    }
                }
                Button("不添加") { dismiss() }
                Button("返回修改", role: .cancel) {}
            } message: { existing in
                Text(existing.isShopLater
                     ? "「\(existing.title)」已在待买列表中（循环，以后检查）。"
                     : "「\(existing.title)」已在待买列表中。")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { checkThenSave() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            images.append(DraftImage(source: .new(image)))
                        }
                    }
                    pickerItems = []
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    images.append(DraftImage(source: .new(image)))
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - 分区

    private var imageSection: some View {
        Section("图片") {
            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(images) { item in
                            ZStack(alignment: .topTrailing) {
                                Group {
                                    if let thumb = item.thumbnail {
                                        Image(uiImage: thumb).resizable().scaledToFill()
                                    } else {
                                        Color.gray.opacity(0.2)
                                    }
                                }
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                Button {
                                    images.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                                .padding(3)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                    Label("相册", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderless)
                Spacer()
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("拍照", systemImage: "camera")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var dateSection: some View {
        Section {
            Toggle("设置日期", isOn: $hasDate.animation())
            if hasDate {
                DatePicker("日期", selection: $date, displayedComponents: .date)
                Toggle("具体时间", isOn: $hasTime.animation())
                if hasTime {
                    DatePicker("时间", selection: $date, displayedComponents: .hourAndMinute)
                }
            }
        } footer: {
            if !hasDate {
                Text("不设日期即为常年提醒，固定显示在列表顶部，不发通知。")
            }
        }
    }

    private var reminderSection: some View {
        Section {
            Picker("提醒", selection: $leadDays) {
                ForEach(leadOptions, id: \.self) { Text(LeadDays.label($0)).tag($0) }
            }
            Picker("重复", selection: $recurrence) {
                ForEach(Recurrence.allCases) { Text($0.label).tag($0) }
            }
            if recurrence != .none {
                Stepper("每 \(interval) \(recurrence.unitLabel)", value: $interval, in: 1...99)
            }
        } footer: {
            Text(leadDays == 0
                 ? "到期当天提醒；过期后每天继续提醒，直到标记完成。"
                 : "从到期前 \(leadDays) 天起每天提醒；过期后每天继续提醒，直到标记完成。")
        }
    }

    private var shopSection: some View {
        Section {
            Picker("类别", selection: $shopRecurring.animation()) {
                Text("普通").tag(false)
                Text("循环").tag(true)
            }
            if shopRecurring {
                Picker("状态", selection: $shopNeeded) {
                    Text("需要买").tag(true)
                    Text("以后检查").tag(false)
                }
            }
        } footer: {
            Text(shopRecurring
                 ? "循环物品左划不会变成已买，而是改为\"以后检查\"，灰色显示在列表最下面，用完了再改回\"需要买\"。"
                 : "普通物品左划即标记为已买。")
        }
    }

    private var leadOptions: [Int] {
        LeadDays.options.contains(leadDays) ? LeadDays.options : (LeadDays.options + [leadDays]).sorted()
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty
    }

    // MARK: - 读取与保存

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let reminder {
            text = reminder.text
            hasDate = reminder.dueDate != nil
            date = reminder.dueDate ?? Date()
            hasTime = reminder.hasTime
            leadDays = reminder.leadDays
            recurrence = reminder.recurrence
            interval = max(1, reminder.recurrenceInterval)
            images = reminder.sortedAttachments.map { DraftImage(source: .existing($0)) }
            shopRecurring = reminder.shopRecurring
            shopNeeded = reminder.shopNeeded
        } else {
            leadDays = defaultLeadDays
            textFocused = true
        }
    }

    /// 新建待买物品时先检查同名
    private func checkThenSave() {
        if isShopping, reminder == nil {
            let name = text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            if let name, let existing = ShoppingActions.existing(matching: [name], in: context).values.first {
                duplicate = existing
                return
            }
        }
        save()
    }

    private func save() {
        let target: Reminder
        if let reminder {
            target = reminder
        } else {
            target = isShopping ? ShoppingActions.makeItem(text: "") : Reminder()
            context.insert(target)
        }
        let wasPinned = reminder?.isPinned ?? false

        target.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isShopping {
            target.dueDate = nil
            target.hasTime = false
            target.recurrence = .none
            target.shopRecurring = shopRecurring
            target.shopNeeded = shopRecurring ? shopNeeded : true
            // 循环物品不会处于已买状态
            if shopRecurring {
                target.isDone = false
                target.completedAt = nil
            }
        } else if hasDate {
            target.dueDate = hasTime ? date : Calendar.current.startOfDay(for: date)
            target.hasTime = hasTime
            target.leadDays = leadDays
            target.recurrence = recurrence
            target.recurrenceInterval = interval
        } else {
            target.dueDate = nil
            target.hasTime = false
            target.recurrence = .none
            // 新加入常年列表的排在最后
            if !wasPinned { target.sortOrder = Date().timeIntervalSince1970 }
        }

        // 附件：删除被移除的，保存新增的，按当前顺序编号
        let keptIDs = Set(images.compactMap { $0.existingID })
        for attachment in target.attachments ?? [] where !keptIDs.contains(attachment.id) {
            AttachmentStore.delete(attachment.fileName)
            target.attachments?.removeAll { $0.id == attachment.id }
            context.delete(attachment)
        }
        for (index, item) in images.enumerated() {
            switch item.source {
            case .existing(let attachment):
                attachment.order = index
            case .new(let image):
                guard let name = try? AttachmentStore.save(image) else { continue }
                let attachment = Attachment(fileName: name, order: index)
                context.insert(attachment)
                attachment.reminder = target
            }
        }

        target.updatedAt = Date()
        ReminderActions.save(context)
        dismiss()
    }
}

struct DraftImage: Identifiable {
    enum Source {
        case existing(Attachment)
        case new(UIImage)
    }

    let id = UUID()
    let source: Source

    var existingID: UUID? {
        if case .existing(let attachment) = source { return attachment.id }
        return nil
    }

    var thumbnail: UIImage? {
        switch source {
        case .existing(let attachment): AttachmentStore.thumbnail(attachment.fileName)
        case .new(let image): image
        }
    }
}

/// 系统相机
struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPick(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
