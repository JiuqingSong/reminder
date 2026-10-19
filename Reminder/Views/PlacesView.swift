import SwiftUI
import SwiftData
import MapKit

// MARK: - 常用地点

/// 管理常用购物地点。以 sheet 打开，自带 NavigationStack
struct PlacesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Place.createdAt) private var places: [Place]

    @State private var path: [Place] = []
    @State private var searching = false
    @State private var addingText = false
    @State private var newName = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(places) { place in
                    NavigationLink(value: place) {
                        PlaceRow(place: place)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            PlaceActions.delete(place, in: context)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .overlay {
                if places.isEmpty {
                    ContentUnavailableView("没有常用地点", systemImage: "mappin.and.ellipse",
                                           description: Text("点右上角 ＋ 在地图上搜索，或添加纯文字地点"))
                }
            }
            .navigationTitle("常用购物地点")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Place.self) { PlaceEditView(place: $0) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    AddPlaceMenu(searching: $searching, addingText: $addingText)
                }
            }
            .sheet(isPresented: $searching) {
                LocationSearchView { item in
                    path.append(PlaceActions.create(from: item, in: context))
                }
            }
            .alert("纯文字地点", isPresented: $addingText) {
                TextField("名称，例如 菜市场", text: $newName)
                Button("添加") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { _ = PlaceActions.findOrCreate(name: name, in: context) }
                    newName = ""
                }
                Button("取消", role: .cancel) { newName = "" }
            } message: {
                Text("不关联地图，不能开启到店提醒。")
            }
        }
    }
}

struct AddPlaceMenu: View {
    @Binding var searching: Bool
    @Binding var addingText: Bool

    var body: some View {
        Menu {
            Button("在地图上搜索", systemImage: "magnifyingglass") { searching = true }
            Button("纯文字地点", systemImage: "character.cursor.ibeam") { addingText = true }
        } label: {
            Image(systemName: "plus")
        }
    }
}

struct PlaceRow: View {
    let place: Place

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.isTextOnly ? "character.cursor.ibeam" : "mappin.circle.fill")
                .foregroundStyle(place.isTextOnly ? Color.secondary : Color.red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                Text(place.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if place.isAlerting {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }
}

// MARK: - 编辑地点

struct PlaceEditView: View {
    @Bindable var place: Place

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var searching = false
    private let auth = LocationAuthorization.shared

    var body: some View {
        let locations = place.sortedLocations
        Form {
            Section("名称") {
                TextField("名称", text: $place.name)
            }

            Section {
                if !locations.isEmpty {
                    Map(initialPosition: .automatic) {
                        ForEach(locations) { location in
                            Marker(location.title, coordinate: location.coordinate)
                            if place.alertEnabled {
                                MapCircle(center: location.coordinate, radius: place.radius)
                                    .foregroundStyle(.orange.opacity(0.2))
                            }
                        }
                    }
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                    // 位置或范围变化时重建地图，让视野重新包含所有位置
                    .id(locations.map(\.id.uuidString).joined() + "\(place.radius)\(place.alertEnabled)")
                }
                ForEach(locations) { location in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(location.title)
                        Text(location.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            PlaceActions.delete(location, in: context)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
                Button("添加地图位置", systemImage: "plus") { searching = true }
            } header: {
                Text("地图位置")
            } footer: {
                Text(locations.isEmpty
                     ? String(localized: "没有地图位置的是纯文字地点，不能开启到店提醒。")
                     : String(localized: "同一家店的几个分店都可以加进来，到达任何一个都会提醒。"))
            }

            Section {
                Toggle("到店提醒", isOn: Binding(get: { place.alertEnabled }, set: { on in
                    if on { auth.request() }
                    place.alertEnabled = on
                    ReminderActions.save(context)
                }))
                .disabled(locations.isEmpty)
                if place.alertEnabled {
                    Picker("提醒范围", selection: $place.radius) {
                        ForEach(PlaceRadius.options, id: \.self) { Text(PlaceRadius.label($0)).tag($0) }
                    }
                }
            } footer: {
                alertFooter
            }

            let count = place.items?.filter { !$0.isDone }.count ?? 0
            if count > 0 {
                Section {
                    Text("待买列表中有 \(count) 件物品可以在这里买")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(place.name.isEmpty ? String(localized: "地点") : place.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $searching) {
            LocationSearchView(initialQuery: place.name) { item in
                PlaceActions.addLocation(item, to: place, in: context)
            }
        }
        .onChange(of: place.radius) { _, _ in ReminderActions.save(context) }
        .onDisappear {
            if place.name.trimmingCharacters(in: .whitespaces).isEmpty {
                place.name = place.sortedLocations.first?.title ?? String(localized: "未命名地点")
            }
            ReminderActions.save(context)
        }
    }

    @ViewBuilder
    private var alertFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("到达这个地点、并且有需要在这里买的物品时，马上提醒你。每次到达都会提醒。")
            if place.alertEnabled {
                if auth.status == .denied || auth.status == .restricted {
                    Text("定位权限已关闭，到店提醒不会生效。")
                        .foregroundStyle(.red)
                    Button("前往系统设置开启") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.footnote)
                }
                if NotificationScheduler.alertLocationCount(context: context) > NotificationScheduler.maxLocations {
                    Text("已开启提醒的地图位置超过 \(NotificationScheduler.maxLocations) 个（iOS 的限制），超出的位置不会提醒。")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: - 地图搜索

/// 搜索地点并在地图上显示，选中一个后添加
struct LocationSearchView: View {
    var initialQuery = ""
    var onPick: (MKMapItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var selected: MKMapItem?
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $position, selection: $selected) {
                    UserAnnotation()
                    ForEach(results, id: \.self) { item in
                        Marker(item: item).tag(item)
                    }
                }
                .frame(height: 280)
                .onMapCameraChange(frequency: .onEnd) { visibleRegion = $0.region }

                List(results, id: \.self) { item in
                    Button {
                        select(item)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? String(localized: "未命名地点")).foregroundStyle(Color.primary)
                                Text(item.placemark.title ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if selected == item {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if results.isEmpty {
                        ContentUnavailableView(failed ? String(localized: "没有找到") : String(localized: "搜索地点"),
                                               systemImage: "magnifyingglass",
                                               description: Text(failed ? String(localized: "换个关键词试试") : String(localized: "例如 Costco、大华超市，会优先显示地图当前区域附近的结果")))
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索地点")
            .navigationTitle("选择位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            // 新版 iOS 的搜索框会占掉导航栏，右上角的按钮显示不出来，所以确认按钮放在底部
            .safeAreaInset(edge: .bottom) {
                if let selected {
                    Button {
                        onPick(selected)
                        dismiss()
                    } label: {
                        Label("添加 \(selected.name ?? String(localized: "这个位置"))", systemImage: "plus.circle.fill")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                    .background(.bar)
                }
            }
            .onAppear {
                LocationAuthorization.shared.request()
                if query.isEmpty { query = initialQuery }
            }
            // 输入停顿后自动搜索
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await search()
            }
            .onChange(of: selected) { _, item in
                if let item { position = .item(item) }
            }
        }
    }

    private func select(_ item: MKMapItem) {
        selected = item
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            results = []
            failed = false
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        if let visibleRegion { request.region = visibleRegion }
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard text == query.trimmingCharacters(in: .whitespaces) else { return }
            results = response.mapItems
            failed = results.isEmpty
            selected = nil
            if !results.isEmpty { position = .automatic }
        } catch {
            results = []
            failed = true
        }
    }
}

// MARK: - 给物品选地点

/// 多选购买地点，也可以在这里新建
struct PlacePickerView: View {
    @Binding var selection: [Place]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Place.createdAt) private var places: [Place]
    @State private var searching = false
    @State private var addingText = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(places) { place in
                    Button {
                        toggle(place)
                    } label: {
                        HStack {
                            PlaceRow(place: place)
                                .foregroundStyle(Color.primary)
                            if isSelected(place) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .overlay {
                if places.isEmpty {
                    ContentUnavailableView("没有常用地点", systemImage: "mappin.and.ellipse",
                                           description: Text("点右上角 ＋ 在地图上搜索，或添加纯文字地点"))
                }
            }
            .navigationTitle("购买地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    AddPlaceMenu(searching: $searching, addingText: $addingText)
                }
            }
            .sheet(isPresented: $searching) {
                LocationSearchView { item in
                    add(PlaceActions.create(from: item, in: context))
                }
            }
            .alert("纯文字地点", isPresented: $addingText) {
                TextField("名称，例如 菜市场", text: $newName)
                Button("添加") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { add(PlaceActions.findOrCreate(name: name, in: context)) }
                    newName = ""
                }
                Button("取消", role: .cancel) { newName = "" }
            } message: {
                Text("不关联地图，不能开启到店提醒。会同时加入常用地点。")
            }
        }
    }

    private func isSelected(_ place: Place) -> Bool {
        selection.contains { $0.id == place.id }
    }

    private func toggle(_ place: Place) {
        if isSelected(place) {
            selection.removeAll { $0.id == place.id }
        } else {
            selection.append(place)
        }
    }

    private func add(_ place: Place) {
        if !isSelected(place) { selection.append(place) }
    }
}
