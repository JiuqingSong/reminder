import SwiftUI
import SwiftData

struct ReminderListView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case pending = "待办"
        case done = "已完成"
        var id: String { rawValue }
    }

    let now: Date

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Reminder> { $0.isDone == false && $0.isShopping == false }) private var active: [Reminder]
    @Query(filter: #Predicate<Reminder> { $0.isDone == true && $0.isShopping == false }) private var completed: [Reminder]
    @Query(filter: #Predicate<Reminder> { $0.isShopping == true }) private var shopping: [Reminder]

    @State private var tab: Tab = .pending
    @State private var searchText = ""
    @State private var dateFilter: DateFilter?
    @State private var showingEditor = false
    @State private var showingSettings = false
    @State private var showingDateFilter = false
    @State private var editMode: EditMode = .inactive
    @State private var navigator = Navigator()

    var body: some View {
        NavigationStack(path: $navigator.path) {
            List {
                if isSearching {
                    searchSection
                } else if tab == .pending {
                    pendingSections
                } else {
                    completedSection
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, $editMode)
            .overlay { emptyState }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索关键词")
            .navigationDestination(for: Reminder.self) { reminder in
                ReminderDetailView(reminder: reminder, now: now)
            }
            .navigationDestination(for: ShoppingRoute.self) { route in
                switch route {
                case .list: ShoppingListView()
                case .bought: BoughtListView()
                }
            }
            .toolbar { toolbar }
            .sheet(isPresented: $showingEditor) {
                ReminderEditView(reminder: nil)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingDateFilter) {
                DateFilterSheet(filter: $dateFilter)
                    .presentationDetents([.medium, .large])
            }
            .onChange(of: tab) { _, _ in editMode = .inactive }
        }
        .environment(navigator)
    }

    // MARK: - 数据分组

    private var pinned: [Reminder] {
        active.filter(\.isPinned).sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    private func dated(_ phase: ReminderPhase) -> [Reminder] {
        active.filter { !$0.isPinned && $0.phase(on: now) == phase }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var completedSorted: [Reminder] {
        completed.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || dateFilter != nil
    }

    private var searchResults: [Reminder] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        return (active + completed + shopping)
            .filter { r in
                (keyword.isEmpty || r.text.localizedStandardContains(keyword))
                    && (dateFilter?.contains(r.dueDate) ?? true)
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    // MARK: - 列表内容

    @ViewBuilder
    private var pendingSections: some View {
        let pinnedItems = pinned
        // 待买固定在常年分组第一行，即使是空的也显示
        Section {
            NavigationLink(value: ShoppingRoute.list) {
                HStack {
                    Label("待买", systemImage: "cart")
                    Spacer()
                    let count = shopping.filter(\.isShopNeeded).count
                    if count > 0 {
                        Text("\(count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .moveDisabled(true)
            ForEach(pinnedItems) { row($0) }
                .onMove(perform: movePinned)
        } header: {
            HStack {
                Label("常年", systemImage: "pin.fill")
                Spacer()
                if pinnedItems.count > 1 {
                    Button(editMode.isEditing ? "完成" : "排序") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .font(.footnote)
                    .textCase(nil)
                }
            }
        }

        datedSection(.overdue, title: "已过期", icon: "exclamationmark.triangle.fill", tint: .red)
        datedSection(.alerting, title: "近期", icon: "bell.fill", tint: .orange)
        datedSection(.later, title: "以后", icon: "calendar", tint: .secondary)
    }

    @ViewBuilder
    private func datedSection(_ phase: ReminderPhase, title: String, icon: String, tint: Color) -> some View {
        let items = dated(phase)
        if !items.isEmpty {
            Section {
                ForEach(items) { row($0) }
            } header: {
                Label(title, systemImage: icon).foregroundStyle(tint)
            }
        }
    }

    @ViewBuilder
    private var completedSection: some View {
        let items = completedSorted
        if !items.isEmpty {
            Section {
                ForEach(items) { row($0) }
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        if let dateFilter {
            Section {
                HStack {
                    Label(dateFilter.label, systemImage: "calendar")
                    Spacer()
                    Button {
                        self.dateFilter = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .font(.subheadline)
            }
        }
        let results = searchResults
        if !results.isEmpty {
            Section("找到 \(results.count) 条") {
                ForEach(results) { row($0) }
            }
        }
    }

    private func row(_ reminder: Reminder) -> some View {
        NavigationLink(value: reminder) {
            ReminderRow(reminder: reminder, now: now)
        }
        // 待买物品只会出现在搜索结果里，它的已买等操作在待买页和详情页中
        .swipeActions(edge: .leading) {
            if reminder.isShopping {
                EmptyView()
            } else if reminder.isDone {
                Button {
                    ReminderActions.restore(reminder, in: context)
                } label: {
                    Label("恢复", systemImage: "arrow.uturn.backward")
                }
                .tint(.blue)
            } else {
                Button {
                    ReminderActions.complete(reminder, in: context)
                } label: {
                    Label("完成", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                ReminderActions.delete(reminder, in: context)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .contextMenu {
            if reminder.isShopping {
                EmptyView()
            } else if reminder.isDone {
                Button("恢复为待办", systemImage: "arrow.uturn.backward") {
                    ReminderActions.restore(reminder, in: context)
                }
            } else {
                Button("标记完成", systemImage: "checkmark") {
                    ReminderActions.complete(reminder, in: context)
                }
                if reminder.dueDate != nil {
                    Button("推迟一天", systemImage: "clock.arrow.circlepath") {
                        ReminderActions.postpone(reminder, days: 1, in: context)
                    }
                    Button("推迟一周", systemImage: "calendar.badge.clock") {
                        ReminderActions.postpone(reminder, days: 7, in: context)
                    }
                }
            }
            Button("复制文字", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = reminder.text
            }
            Divider()
            Button("删除", systemImage: "trash", role: .destructive) {
                ReminderActions.delete(reminder, in: context)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isSearching {
            if searchResults.isEmpty { ContentUnavailableView.search }
        } else if tab == .done, completed.isEmpty {
            ContentUnavailableView("还没有已完成的事项", systemImage: "tray")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
        ToolbarItem(placement: .principal) {
            Picker("视图", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                showingDateFilter = true
            } label: {
                Image(systemName: dateFilter == nil ? "calendar" : "calendar.badge.checkmark")
            }
            Button {
                showingEditor = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    private func movePinned(from source: IndexSet, to destination: Int) {
        var items = pinned
        items.move(fromOffsets: source, toOffset: destination)
        for (index, reminder) in items.enumerated() {
            reminder.sortOrder = Double(index)
        }
        try? context.save()
    }
}

// MARK: - 行

struct ReminderRow: View {
    let reminder: Reminder
    let now: Date
    /// 在待买页里不再标"待买"
    var inShoppingList = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .lineLimit(2)
                    .strikethrough(reminder.isDone && !reminder.isShopping, color: .secondary)
                    .foregroundStyle(reminder.isDone || reminder.isShopLater ? Color.secondary : Color.primary)
                subtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let first = reminder.sortedAttachments.first, let thumb = AttachmentStore.thumbnail(first.fileName) {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if !reminder.isDone, let days = reminder.daysUntilDue(from: now) {
                Text(DueFormat.relative(days: days))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(relativeColor(days))
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var subtitle: some View {
        if reminder.isShopping {
            shopSubtitle
        } else if reminder.isDone, let completedAt = reminder.completedAt {
            Text("完成于 " + DueFormat.timestamp(completedAt))
        } else if let due = reminder.dueDate {
            HStack(spacing: 4) {
                Text(DueFormat.date(due, hasTime: reminder.hasTime, now: now))
                if reminder.recurrence != .none {
                    Image(systemName: "repeat")
                    Text(reminder.recurrence.description(interval: reminder.recurrenceInterval))
                }
            }
        }
    }

    @ViewBuilder
    private var shopSubtitle: some View {
        let parts: [String] = [
            inShoppingList ? nil : (reminder.isDone ? "已买" : "待买"),
            reminder.shopRecurring ? "循环" : nil,
            reminder.isShopLater ? "以后检查" : nil,
            reminder.isDone ? reminder.completedAt.map { "买于 " + DueFormat.timestamp($0) } : nil,
        ].compactMap { (part: String?) in part }
        if !parts.isEmpty {
            HStack(spacing: 4) {
                if !inShoppingList { Image(systemName: "cart") }
                if reminder.shopRecurring { Image(systemName: "arrow.triangle.2.circlepath") }
                Text(parts.joined(separator: " · "))
            }
        }
    }

    private func relativeColor(_ days: Int) -> Color {
        if days < 0 { return .red }
        if days <= reminder.leadDays { return .orange }
        return .secondary
    }
}
