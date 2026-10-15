import SwiftUI
import SwiftData

/// 待买相关页面。都用 value 方式跳转，由主列表的 NavigationStack 统一注册目标页，
/// 不和 NavigationLink { 目标页 } 混用（之前混用时，从待买页工具栏进入已买会卡死后闪退）
enum ShoppingRoute: Hashable {
    case list, bought
}

/// 主列表 NavigationStack 的导航路径，子页面用按钮跳转时往里追加
@Observable
final class Navigator {
    var path = NavigationPath()
}

/// 待买：需要买的在上，"以后检查"的循环物品灰色排在最下面
struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Environment(Navigator.self) private var navigator
    @Query(filter: #Predicate<Reminder> { $0.isShopping == true }) private var items: [Reminder]

    @State private var showingEditor = false
    @State private var showingBatch = false
    @State private var editMode: EditMode = .inactive

    var body: some View {
        let neededItems = needed
        let laterItems = later
        List {
            if !neededItems.isEmpty {
                Section {
                    ForEach(neededItems) { row($0) }
                        .onMove { move(neededItems, from: $0, to: $1) }
                }
            }
            if !laterItems.isEmpty {
                Section {
                    ForEach(laterItems) { row($0) }
                        .onMove { move(laterItems, from: $0, to: $1) }
                } header: {
                    Label("以后检查", systemImage: "clock")
                } footer: {
                    Text("用完了左划或在详情里改为\"需要买\"。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .overlay {
            if neededItems.isEmpty, laterItems.isEmpty {
                ContentUnavailableView("没有待买物品", systemImage: "cart",
                                       description: Text("点右上角 ＋ 添加，或用\"批量添加\"一次加多项"))
            }
        }
        .navigationTitle("待买")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if neededItems.count + laterItems.count > 1 {
                    Button(editMode.isEditing ? "完成" : "排序") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("批量添加", systemImage: "text.badge.plus") { showingBatch = true }
                    .labelStyle(.titleAndIcon)
                Spacer()
                // 工具栏里不放 NavigationLink：它会打乱导航栈，点物品时详情页一闪就被盖住
                Button {
                    navigator.path.append(ShoppingRoute.bought)
                } label: {
                    Label("已买 \(boughtCount)", systemImage: "bag")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ReminderEditView(reminder: nil, newShoppingItem: true)
        }
        .sheet(isPresented: $showingBatch) {
            BatchAddView()
        }
    }

    private func ordered(_ list: [Reminder]) -> [Reminder] {
        list.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    private var needed: [Reminder] { ordered(items.filter(\.isShopNeeded)) }
    private var later: [Reminder] { ordered(items.filter(\.isShopLater)) }
    private var boughtCount: Int { items.filter(\.isDone).count }

    private func row(_ item: Reminder) -> some View {
        NavigationLink(value: item) {
            ReminderRow(reminder: item, now: Date(), inShoppingList: true)
        }
        .swipeActions(edge: .trailing) {
            swipeButton(item)
        }
        .contextMenu {
            swipeButton(item)
            Button(item.shopRecurring ? "改为普通物品" : "改为循环物品", systemImage: "arrow.triangle.2.circlepath") {
                ShoppingActions.setRecurring(item, !item.shopRecurring, in: context)
            }
            Button("复制文字", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = item.text
            }
            Divider()
            Button("删除", systemImage: "trash", role: .destructive) {
                ReminderActions.delete(item, in: context)
            }
        }
    }

    @ViewBuilder
    private func swipeButton(_ item: Reminder) -> some View {
        if !item.shopRecurring {
            Button {
                ShoppingActions.markBought(item, in: context)
            } label: {
                Label("已买", systemImage: "checkmark")
            }
            .tint(.green)
        } else if item.shopNeeded {
            Button {
                ShoppingActions.setNeeded(item, false, in: context)
            } label: {
                Label("以后检查", systemImage: "clock")
            }
            .tint(.gray)
        } else {
            Button {
                ShoppingActions.setNeeded(item, true, in: context)
            } label: {
                Label("需要买", systemImage: "cart.badge.plus")
            }
            .tint(.orange)
        }
    }

    private func move(_ section: [Reminder], from source: IndexSet, to destination: Int) {
        var list = section
        list.move(fromOffsets: source, toOffset: destination)
        for (index, item) in list.enumerated() {
            item.sortOrder = Double(index)
        }
        try? context.save()
    }
}

// MARK: - 已买

struct BoughtListView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Reminder> { $0.isShopping == true && $0.isDone == true }) private var bought: [Reminder]
    @State private var confirmingClear = false

    var body: some View {
        let items = bought.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        List {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    ReminderRow(reminder: item, now: Date(), inShoppingList: true)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        ReminderActions.restore(item, in: context)
                    } label: {
                        Label("恢复", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        ReminderActions.delete(item, in: context)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button("恢复为待买", systemImage: "arrow.uturn.backward") {
                        ReminderActions.restore(item, in: context)
                    }
                    Button("复制文字", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = item.text
                    }
                    Divider()
                    Button("删除", systemImage: "trash", role: .destructive) {
                        ReminderActions.delete(item, in: context)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("没有已买物品", systemImage: "bag")
            }
        }
        .navigationTitle("已买")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清空", role: .destructive) { confirmingClear = true }
                    .disabled(items.isEmpty)
            }
        }
        .confirmationDialog("永久删除全部 \(items.count) 件已买物品？", isPresented: $confirmingClear,
                            titleVisibility: .visible) {
            Button("全部删除", role: .destructive) {
                ShoppingActions.clearBought(in: context)
            }
        } message: {
            Text("图片也会一起删除，无法恢复。")
        }
    }
}

// MARK: - 批量添加

struct BatchAddView: View {
    private struct Duplicates {
        /// 输入里与现有物品同名的
        let names: [String]
        /// 其中对应"以后检查"循环物品的现有物品
        let laterItems: [Reminder]
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var duplicates: Duplicates?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 240)
                        .focused($focused)
                } footer: {
                    Text("每行一项，添加为普通待买物品。空行会忽略，同一次输入里重复的只加一次。")
                }
            }
            .navigationTitle("批量添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(names.isEmpty ? "添加" : "添加 \(names.count) 项") { add() }
                        .disabled(names.isEmpty)
                }
            }
            .onAppear { focused = true }
            .alert(duplicates.map { "有 \($0.names.count) 项已在待买列表中" } ?? "",
                   isPresented: Binding(get: { duplicates != nil }, set: { if !$0 { duplicates = nil } }),
                   presenting: duplicates) { dup in
                Button("跳过这些") { commit(skipping: dup) }
                if !dup.laterItems.isEmpty {
                    Button("跳过，并把 \(dup.laterItems.count) 件循环物品改为需要买") {
                        for item in dup.laterItems { item.shopNeeded = true; item.updatedAt = Date() }
                        commit(skipping: dup)
                    }
                }
                Button("重复添加") { commit(names) }
                Button("返回修改", role: .cancel) {}
            } message: { dup in
                Text(dup.names.joined(separator: "、"))
            }
        }
    }

    /// 去掉空行和本次输入内的重复
    private var names: [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert(Reminder.shopKey($0)).inserted }
    }

    private func add() {
        let list = names
        let existing = ShoppingActions.existing(matching: list, in: context)
        let dupNames = list.filter { existing[Reminder.shopKey($0)] != nil }
        if dupNames.isEmpty {
            commit(list)
        } else {
            let later = dupNames.compactMap { existing[Reminder.shopKey($0)] }.filter(\.isShopLater)
            duplicates = Duplicates(names: dupNames, laterItems: later)
        }
    }

    private func commit(skipping dup: Duplicates) {
        let skip = Set(dup.names.map(Reminder.shopKey))
        commit(names.filter { !skip.contains(Reminder.shopKey($0)) })
    }

    private func commit(_ list: [String]) {
        ShoppingActions.add(list, in: context)
        dismiss()
    }
}
