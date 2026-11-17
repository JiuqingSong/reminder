import WidgetKit
import SwiftUI

@main
struct ReminderWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReminderWidget()
    }
}

struct ReminderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: Provider()) { entry in
            ReminderWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("待办")
        .description("显示已过期、近期的事项和常年提醒。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - 数据

struct Entry: TimelineEntry {
    let date: Date
    /// nil：还没有数据（App 装好后还没打开过）
    let snapshot: WidgetSnapshot?
    var isPlaceholder = false

    var rows: [WidgetSnapshot.Row] { snapshot?.rows(on: date) ?? [] }
    var alertingCount: Int { snapshot?.alertingCount(on: date) ?? 0 }
    var overdueCount: Int { snapshot?.overdueCount(on: date) ?? 0 }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        let sample = WidgetSnapshot(items: (0..<6).map { i in
            WidgetSnapshot.Item(title: String(repeating: "—", count: 6 + i % 3 * 2),
                                due: i < 3 ? Date() : nil, hasTime: false, leadDays: 1)
        })
        return Entry(date: Date(), snapshot: sample, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: WidgetSnapshot.load()))
    }

    /// 现在一条，之后每天零点一条（"明天"变"今天"、过期天数加一），一周后再来要
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let calendar = Calendar.current
        let now = Date()
        var entries = [Entry(date: now, snapshot: snapshot)]
        let today = calendar.startOfDay(for: now)
        for offset in 1...7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                entries.append(Entry(date: day, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .after(entries.last?.date ?? now)))
    }
}

// MARK: - 界面

struct ReminderWidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            default: home
            }
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    private var maxRows: Int {
        switch family {
        case .systemSmall: 4
        case .systemMedium: 4
        default: 10
        }
    }

    // 桌面

    private var home: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 5) {
            header
            if entry.snapshot == nil {
                Spacer(minLength: 0)
                Text("打开 App 后显示").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if entry.rows.isEmpty {
                Spacer(minLength: 0)
                Label("没有要处理的事", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                let rows = Array(entry.rows.prefix(maxRows))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    rowView(row)
                }
                let more = entry.rows.count - rows.count
                if more > 0 {
                    Text("还有 \(more) 项")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("待办").font(.headline)
            Spacer(minLength: 0)
            if entry.overdueCount > 0 {
                countBadge(entry.overdueCount, color: .red)
            }
            if entry.alertingCount > 0 {
                countBadge(entry.alertingCount, color: .orange)
            }
        }
    }

    private func countBadge(_ count: Int, color: Color) -> some View {
        Text("\(count)")
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color, in: Capsule())
    }

    @ViewBuilder
    private func rowView(_ row: WidgetSnapshot.Row) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon(row.tone))
                .font(.system(size: 8))
                .foregroundStyle(color(row.tone))
                .frame(width: 10)
            Text(row.title)
                .font(.subheadline)
                .lineLimit(1)
            if family != .systemSmall, let label = row.label {
                Spacer(minLength: 4)
                Text(label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(color(row.tone))
                    .lineLimit(1)
            }
        }
    }

    private func icon(_ tone: WidgetSnapshot.Tone) -> String {
        tone == .pinned ? "pin.fill" : "circle.fill"
    }

    private func color(_ tone: WidgetSnapshot.Tone) -> Color {
        switch tone {
        case .overdue: .red
        case .alerting: .orange
        case .pinned: .secondary
        }
    }

    // 锁屏

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "bell.fill").font(.caption2)
                Text("\(entry.alertingCount + entry.overdueCount)")
                    .font(.title3.bold().monospacedDigit())
            }
        }
    }

    private var inline: some View {
        let dated = entry.rows.filter { $0.tone != .pinned }
        return Group {
            if let first = dated.first {
                Text(verbatim: [first.label, first.title].compactMap { $0 }.joined(separator: " "))
            } else {
                Text("没有要处理的事")
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            let rows = entry.rows
            if rows.isEmpty {
                Text("待办").font(.headline)
                Text("没有要处理的事").font(.caption)
            } else {
                ForEach(Array(rows.prefix(3).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        Image(systemName: icon(row.tone)).font(.system(size: 6))
                        Text(row.title).lineLimit(1)
                        if let label = row.label {
                            Spacer(minLength: 2)
                            Text(label).lineLimit(1)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
