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
                LocationSearchView(asksAlert: true) { item, alert in
                    path.append(PlaceActions.create(from: item, alert: alert, in: context))
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
    /// 选地点时右边有铃铛按钮，就不再显示这个小铃铛
    var showsAlertBadge = true

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
            if showsAlertBadge && place.isAlerting {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }
}

/// 列表行右边的铃铛：一点就开关这个地点的到店提醒。纯文字地点不显示
struct PlaceAlertButton: View {
    let place: Place
    @Environment(\.modelContext) private var context

    var body: some View {
        if !place.isTextOnly {
            Button {
                PlaceActions.setAlert(place, on: !place.alertEnabled, in: context)
            } label: {
                Image(systemName: place.alertEnabled ? "bell.fill" : "bell.slash")
                    .foregroundStyle(place.alertEnabled ? Color.orange : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(place.alertEnabled ? Color.orange.opacity(0.18) : Color.clear, in: Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(place.alertEnabled ? String(localized: "关闭到店提醒") : String(localized: "开启到店提醒"))
            .sensoryFeedback(.selection, trigger: place.alertEnabled)
        }
    }
}

/// 有地点开启了到店提醒、但定位权限被关掉时的提示
struct LocationDeniedWarning: View {
    @Environment(\.openURL) private var openURL

    static var isDenied: Bool {
        let status = LocationAuthorization.shared.status
        return status == .denied || status == .restricted
    }

    var body: some View {
        if Self.isDenied {
            VStack(alignment: .leading, spacing: 6) {
                Label("定位权限已关闭，到店提醒不会生效。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("前往系统设置开启") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderless)
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
                    PlaceActions.setAlert(place, on: on, in: context)
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
            LocationSearchView(initialQuery: place.name) { item, _ in
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
    /// 新建地点时在底部一起设置到店提醒；给已有地点加位置时不需要
    var asksAlert = false
    /// 第二个参数是选的到店提醒设置，asksAlert 为 false 时是 nil
    var onPick: (MKMapItem, PlaceAlertChoice?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var alert = PlaceAlertChoice()
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var selected: MKMapItem?
    @State private var position: MapCameraPosition = LocationSearchView.initialPosition
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var failed = false
    /// 用户按了搜索或选了地点后，地图就停在那里，不再跟着当前位置走
    @State private var placed = false
    private let auth = LocationAuthorization.shared

    private static func region(around location: CLLocation) -> MKCoordinateRegion {
        MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
    }

    private static var initialPosition: MapCameraPosition {
        if let location = LocationAuthorization.shared.location {
            return .region(region(around: location))
        }
        return .userLocation(fallback: .automatic)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $position, selection: $selected) {
                    UserAnnotation()
                    ForEach(results, id: \.self) { item in
                        Marker(item: item).tag(item)
                    }
                    if asksAlert, alert.enabled, let selected {
                        MapCircle(center: selected.placemark.coordinate, radius: alert.radius)
                            .foregroundStyle(.orange.opacity(0.2))
                            .stroke(.orange, lineWidth: 2)
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
                    VStack(spacing: 12) {
                        if asksAlert { alertOptions }
                        Button {
                            onPick(selected, asksAlert ? alert : nil)
                            dismiss()
                        } label: {
                            Label("添加 \(selected.name ?? String(localized: "这个位置"))", systemImage: "plus.circle.fill")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding()
                    .background(.bar)
                }
            }
            .onAppear {
                auth.requestLocation()
                if query.isEmpty { query = initialQuery }
            }
            // 第一次进来时位置可能还没拿到，拿到后再把地图移到当前位置
            .onChange(of: auth.location) { _, location in
                if let location, !placed { position = .region(Self.region(around: location)) }
            }
            // 输入停顿后自动搜索，只更新下面的列表，地图不动
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await search()
            }
            // 按键盘上的搜索键才把地图移到搜索结果
            .onSubmit(of: .search) {
                Task {
                    await search()
                    if !results.isEmpty {
                        placed = true
                        position = .automatic
                    }
                }
            }
            .onChange(of: selected) { _, item in
                if let item {
                    placed = true
                    position = .item(item)
                }
            }
        }
    }

    private func select(_ item: MKMapItem) {
        selected = item
    }

    /// 到店提醒开关和范围，地图上的橙色圈跟着变
    private var alertOptions: some View {
        VStack(spacing: 10) {
            Toggle(isOn: $alert.enabled.animation()) {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("到店提醒")
                        Text("到了这里且有要买的东西就通知")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell").foregroundStyle(.orange)
                }
            }
            if alert.enabled {
                Picker("提醒范围", selection: $alert.radius) {
                    ForEach(PlaceRadius.options, id: \.self) { Text(PlaceRadius.label($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
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
        // 优先搜地图当前区域附近；地图还没报告区域时用当前位置
        if let visibleRegion {
            request.region = visibleRegion
        } else if let location = auth.location {
            request.region = Self.region(around: location)
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard text == query.trimmingCharacters(in: .whitespaces) else { return }
            results = response.mapItems
            failed = results.isEmpty
            selected = nil
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
                // 条件放在外面，权限正常时列表顶部不留空行
                if LocationDeniedWarning.isDenied && places.contains(where: \.isAlerting) {
                    LocationDeniedWarning()
                }
                Section {
                    ForEach(places) { place in
                        // 两个按钮分开点：点地点选中或取消，点铃铛开关提醒
                        HStack(spacing: 8) {
                            Button {
                                toggle(place)
                            } label: {
                                HStack {
                                    PlaceRow(place: place, showsAlertBadge: false)
                                        .foregroundStyle(Color.primary)
                                    if isSelected(place) {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            PlaceAlertButton(place: place)
                        }
                    }
                } footer: {
                    if places.contains(where: { !$0.isTextOnly }) {
                        Text("点地点选中或取消。点右侧铃铛开关到店提醒。")
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
                LocationSearchView(asksAlert: true) { item, alert in
                    add(PlaceActions.create(from: item, alert: alert, in: context))
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
