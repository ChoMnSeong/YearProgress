import SwiftUI

/// 생년월일 선택 (연/월/일 드롭다운)
struct BirthDatePicker: View {
    @Binding var date: Date
    private let cal = Calendar.current

    private var currentYear: Int { cal.component(.year, from: Date()) }
    private var year: Int { cal.component(.year, from: date) }
    private var month: Int { cal.component(.month, from: date) }
    private var day: Int { cal.component(.day, from: date) }
    private var daysInMonth: Int { cal.range(of: .day, in: .month, for: date)?.count ?? 31 }

    private func update(year: Int? = nil, month: Int? = nil, day: Int? = nil) {
        var c = cal.dateComponents([.year, .month, .day], from: date)
        if let year { c.year = year }
        if let month { c.month = month }
        if let day { c.day = day }
        // 말일 보정 (예: 2월 30일 방지)
        if let y = c.year, let m = c.month,
           let first = cal.date(from: DateComponents(year: y, month: m, day: 1)),
           let maxDay = cal.range(of: .day, in: .month, for: first)?.count {
            c.day = min(c.day ?? 1, maxDay)
        }
        if let d = cal.date(from: c) { date = d }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.t("생년월일", "Birth date"))
                .font(.callout)
            HStack(spacing: 6) {
                Picker("", selection: Binding(get: { year }, set: { update(year: $0) })) {
                    ForEach(1920...currentYear, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                }
                .labelsHidden().frame(maxWidth: .infinity)
                Picker("", selection: Binding(get: { month }, set: { update(month: $0) })) {
                    ForEach(1...12, id: \.self) { Text(L.t("\($0)월", "\($0)")).tag($0) }
                }
                .labelsHidden().frame(maxWidth: .infinity)
                Picker("", selection: Binding(get: { day }, set: { update(day: $0) })) {
                    ForEach(1...daysInMonth, id: \.self) { Text(L.t("\($0)일", "\($0)")).tag($0) }
                }
                .labelsHidden().frame(maxWidth: .infinity)
            }
        }
    }
}
