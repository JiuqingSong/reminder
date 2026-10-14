import SwiftUI

struct DateFilter: Equatable {
    var start: Date
    var end: Date

    func contains(_ date: Date?) -> Bool {
        guard let date else { return false }
        let calendar = Calendar.current
        let lower = calendar.startOfDay(for: min(start, end))
        let upperDay = calendar.startOfDay(for: max(start, end))
        let upper = calendar.date(byAdding: .day, value: 1, to: upperDay) ?? upperDay
        return date >= lower && date < upper
    }

    var label: String {
        "\(DueFormat.date(start, hasTime: false)) – \(DueFormat.date(end, hasTime: false))"
    }
}

struct DateFilterSheet: View {
    @Binding var filter: DateFilter?
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var end = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("从", selection: $start, displayedComponents: .date)
                    DatePicker("到", selection: $end, displayedComponents: .date)
                } footer: {
                    Text("按到期日期筛选，待办和已完成都会搜索。可与关键词同时使用。")
                }
                Section("快捷") {
                    Button("本周") { setRange(.weekOfYear) }
                    Button("本月") { setRange(.month) }
                    Button("今年") { setRange(.year) }
                }
                if filter != nil {
                    Section {
                        Button("清除日期筛选", role: .destructive) {
                            filter = nil
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("按日期筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        filter = DateFilter(start: start, end: end)
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let filter {
                    start = filter.start
                    end = filter.end
                }
            }
        }
    }

    private func setRange(_ component: Calendar.Component) {
        guard let interval = Calendar.current.dateInterval(of: component, for: Date()) else { return }
        start = interval.start
        end = interval.end.addingTimeInterval(-1)
    }
}
