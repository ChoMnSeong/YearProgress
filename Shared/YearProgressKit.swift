import Foundation
import SwiftUI
import AppKit

extension Color {
    /// "#RRGGBB" → Color
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self = Color(.sRGB,
                     red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }

    /// 색을 더 어둡게 (오늘 표시용)
    func darker(by amount: Double = 0.24) -> Color {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return self }
        return Color(.sRGB,
                     red: Double(c.redComponent) * (1 - amount),
                     green: Double(c.greenComponent) * (1 - amount),
                     blue: Double(c.blueComponent) * (1 - amount),
                     opacity: Double(c.alphaComponent))
    }

    /// Color → "#RRGGBB"
    func toHexString() -> String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// 한 해의 진행 상황을 나타내는 모델. 앱과 위젯 익스텐션 양쪽에서 함께 사용합니다.
struct YearProgress {
    /// 연도 (예: 2026)
    let year: Int
    /// 0.0 ~ 1.0 사이의 진행률
    let fraction: Double
    /// 올해의 몇 번째 날인지 (1부터 시작)
    let dayOfYear: Int
    /// 올해 전체 일수 (윤년이면 366)
    let totalDays: Int
    /// 올해 남은 일수
    let daysRemaining: Int

    /// 0 ~ 100 사이의 퍼센트 값
    var percent: Double { fraction * 100 }

    /// "37.42%" 형태의 문자열
    var formattedPercent: String {
        String(format: "%.2f%%", percent)
    }

    /// 현재(또는 지정한) 시점의 진행 상황을 계산합니다.
    static func current(date: Date = Date(), calendar: Calendar = .current) -> YearProgress {
        let year = calendar.component(.year, from: date)

        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
            ?? date
        let startOfNextYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
            ?? date

        let totalInterval = startOfNextYear.timeIntervalSince(startOfYear)
        let elapsed = date.timeIntervalSince(startOfYear)
        let fraction = totalInterval > 0 ? min(max(elapsed / totalInterval, 0), 1) : 0

        let totalDays = calendar.dateComponents([.day], from: startOfYear, to: startOfNextYear).day ?? 365
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let daysRemaining = max(totalDays - dayOfYear, 0)

        return YearProgress(
            year: year,
            fraction: fraction,
            dayOfYear: dayOfYear,
            totalDays: totalDays,
            daysRemaining: daysRemaining
        )
    }
}

// MARK: - 기간(올해/이번 달/주/오늘/인생) 진행률

enum Period: String, CaseIterable, Identifiable {
    case year, month, week, day, life
    var id: String { rawValue }
    var label: String {
        switch self {
        case .year:  return L.t("올해", "Year")
        case .month: return L.t("이번 달", "Month")
        case .week:  return L.t("이번 주", "Week")
        case .day:   return L.t("오늘", "Day")
        case .life:  return L.t("인생", "Life")
        }
    }
}

struct PeriodProgress {
    let period: Period
    let fraction: Double
    let elapsed: Int          // 현재(진행 중) 단위 (1-based)
    let total: Int            // 전체 단위 수
    let remaining: Int        // 남은 단위 수
    let title: String         // 헤더 라벨 ("2026년", "6월", "이번 주", "오늘", "35세")
    let remainingText: String // "212일 남음" 등
    let detail: String        // 상세 줄 ("153 / 365 · 212일 남음", 인생은 더 자세히)
    let dotColumns: Int
    let year: Int             // 연 단위 시각화(월별 개요)용
    let dayOfYear: Int

    var percent: Double { fraction * 100 }
    var formattedPercent: String { String(format: "%.2f%%", percent) }

    static func current(period: Period,
                        date: Date = Date(),
                        birthDate: Date? = nil,
                        lifeExpectancy: Int = 80,
                        calendar: Calendar = .current) -> PeriodProgress {
        let yp = YearProgress.current(date: date, calendar: calendar)

        func clampFraction(_ start: Date, _ end: Date) -> Double {
            let span = end.timeIntervalSince(start)
            return span > 0 ? min(max(date.timeIntervalSince(start) / span, 0), 1) : 0
        }
        func build(fraction: Double, elapsed: Int, total: Int, title: String,
                   remainingUnit: String, cols: Int, detail: String? = nil) -> PeriodProgress {
            let rem = max(total - elapsed, 0)
            let remText = "\(rem)\(remainingUnit)"
            return PeriodProgress(period: period, fraction: fraction, elapsed: elapsed, total: total,
                                  remaining: rem, title: title, remainingText: remText,
                                  detail: detail ?? "\(elapsed) / \(total) · \(remText)",
                                  dotColumns: cols, year: yp.year, dayOfYear: yp.dayOfYear)
        }

        switch period {
        case .year:
            return build(fraction: yp.fraction, elapsed: yp.dayOfYear, total: yp.totalDays,
                         title: L.t("\(yp.year)년", "\(yp.year)"),
                         remainingUnit: L.t("일 남음", " days left"), cols: 19)

        case .month:
            let interval = calendar.dateInterval(of: .month, for: date)
            let start = interval?.start ?? date
            let end = interval?.end ?? date
            let total = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
            let elapsed = calendar.component(.day, from: date)
            let month = calendar.component(.month, from: date)
            return build(fraction: clampFraction(start, end), elapsed: elapsed, total: total,
                         title: YearMath.monthName(month),
                         remainingUnit: L.t("일 남음", " days left"), cols: 7)

        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: date)
            let start = interval?.start ?? date
            let end = interval?.end ?? date
            let startOfDay = calendar.startOfDay(for: date)
            let daysIn = (calendar.dateComponents([.day], from: start, to: startOfDay).day ?? 0) + 1
            return build(fraction: clampFraction(start, end), elapsed: min(max(daysIn, 1), 7), total: 7,
                         title: L.t("이번 주", "This week"),
                         remainingUnit: L.t("일 남음", " days left"), cols: 7)

        case .day:
            let interval = calendar.dateInterval(of: .day, for: date)
            let start = interval?.start ?? date
            let end = interval?.end ?? date
            let elapsed = calendar.component(.hour, from: date) + 1
            return build(fraction: clampFraction(start, end), elapsed: elapsed, total: 24,
                         title: L.t("오늘", "Today"),
                         remainingUnit: L.t("시간 남음", "h left"), cols: 12)

        case .life:
            guard let birth = birthDate else {
                return build(fraction: 0, elapsed: 0, total: lifeExpectancy,
                             title: L.t("나이 미설정", "Set age"),
                             remainingUnit: L.t("년 남음", "y left"), cols: 10,
                             detail: L.t("생년월일을 설정하세요", "Set your birth date"))
            }
            let exp = max(lifeExpectancy, 1)
            let comps = calendar.dateComponents([.year, .month], from: birth, to: date)
            let ageY = max(comps.year ?? 0, 0)
            let ageM = max(comps.month ?? 0, 0)
            let ageYears = date.timeIntervalSince(birth) / (365.2425 * 86400)
            let f = min(max(ageYears / Double(exp), 0), 1)
            let elapsed = min(max(ageY + 1, 1), exp)
            let daysLived = max(calendar.dateComponents([.day], from: birth, to: date).day ?? 0, 0)

            // 다음 생일까지 남은 일수
            let bm = calendar.component(.month, from: birth)
            let bd = calendar.component(.day, from: birth)
            let startToday = calendar.startOfDay(for: date)
            let thisYear = calendar.component(.year, from: date)
            var nextBday = calendar.date(from: DateComponents(year: thisYear, month: bm, day: bd)) ?? date
            if nextBday < startToday {
                nextBday = calendar.date(from: DateComponents(year: thisYear + 1, month: bm, day: bd)) ?? date
            }
            let dToB = max(calendar.dateComponents([.day], from: startToday, to: nextBday).day ?? 0, 0)

            let title = L.t("\(ageY)세 \(ageM)개월", "\(ageY)y \(ageM)m")
            let detail = L.t("\(daysLived.formatted())일 살았어요 · 다음 생일 D-\(dToB)",
                             "\(daysLived.formatted()) days lived · birthday in \(dToB)d")
            return build(fraction: f, elapsed: elapsed, total: exp, title: title,
                         remainingUnit: L.t("년 남음", "y left"), cols: 10, detail: detail)
        }
    }
}

/// 사용자가 고를 수 있는 강조 색상. 앱·위젯이 App Group 으로 선택값을 공유합니다.
enum ThemeColor: String, CaseIterable, Identifiable {
    case blue, teal, green, orange, pink, red, purple, indigo

    var id: String { rawValue }

    var hex: String {
        switch self {
        case .blue:   return "#3399F2"
        case .teal:   return "#2EB3B3"
        case .green:  return "#47B86B"
        case .orange: return "#F5992E"
        case .pink:   return "#F2669E"
        case .red:    return "#E65757"
        case .purple: return "#9966EB"
        case .indigo: return "#5766DB"
        }
    }

    var color: Color { Color(hex: hex) ?? .blue }

    var label: String {
        switch self {
        case .blue:   return "파랑"
        case .teal:   return "청록"
        case .green:  return "초록"
        case .orange: return "주황"
        case .pink:   return "분홍"
        case .red:    return "빨강"
        case .purple: return "보라"
        case .indigo: return "남색"
        }
    }

    static let storageKey = "themeColor"
    static let defaultHex = ThemeColor.blue.hex
}

/// 앱(비샌드박스)과 위젯(샌드박스)이 설정을 공유하는 저장소.
/// 무료 계정에선 App Group 을 못 쓰므로, **위젯 컨테이너 안의 JSON 파일**로 공유합니다.
/// - 위젯: 자기 컨테이너(NSHomeDirectory) 에서 직접 읽고 씀
/// - 앱(비샌드박스): 위젯 컨테이너 경로를 직접 구성해 같은 파일을 읽고 씀
enum SharedStore {
    static let widgetBundleID = "com.ensnif.YearProgress.YearProgressWidget"

    private static var fileURL: URL {
        let base: String
        if Bundle.main.bundleIdentifier == widgetBundleID {
            base = NSHomeDirectory() // 위젯 = 컨테이너 Data
        } else {
            base = NSHomeDirectory() + "/Library/Containers/\(widgetBundleID)/Data"
        }
        return URL(fileURLWithPath: base)
            .appendingPathComponent("Library/Application Support/YearProgress", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    static func read() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return dict
    }

    static func write(_ dict: [String: String]) {
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func set(_ key: String, _ value: String) {
        var d = read()
        d[key] = value
        write(d)
    }
}

/// 시스템 언어를 따라가는 아주 가벼운 현지화 헬퍼.
/// 시스템 언어가 한국어면 한국어, 그 외에는 영어로 표시합니다.
enum L {
    /// 시스템 "선호 언어" 1순위. (앱이 영어 전용으로 인식돼도 실제 시스템 언어를 따라가도록)
    static var preferred: String {
        Locale.preferredLanguages.first ?? "en"
    }

    static var isKorean: Bool {
        preferred.hasPrefix("ko")
    }

    /// 날짜 포맷 등에 쓸, 시스템 선호 언어 기반 로케일
    static var locale: Locale {
        Locale(identifier: preferred)
    }

    /// 한국어 / 영어 문자열을 시스템 언어에 맞춰 고릅니다.
    static func t(_ ko: String, _ en: String) -> String {
        isKorean ? ko : en
    }
}

// MARK: - 표시 설정 (앱·위젯이 App Group 으로 공유)

enum DisplayMode: String, CaseIterable, Identifiable {
    case dots, graph
    var id: String { rawValue }
    var label: String { self == .dots ? L.t("점", "Dots") : L.t("그래프", "Graph") }
}

enum DotGrouping: String, CaseIterable, Identifiable {
    case continuous, monthly
    var id: String { rawValue }
    var label: String { self == .continuous ? L.t("365 한눈에", "365 at once") : L.t("월별", "By month") }
}

enum AppSettings {
    static let displayModeKey = "displayMode"
    static let dotGroupingKey = "dotGrouping"
    static let selectedMonthKey = "selectedMonth"   // 0 = 개요, 1...12 = 확대된 달
    static let periodKey = "period"
    static let birthDateKey = "birthDate"           // "yyyy-MM-dd"
    static let lifeExpectancyKey = "lifeExpectancy" // 정수 문자열

    static let birthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 모든 설정을 공유 파일에서 **한 번만** 읽어 담는 스냅샷.
    struct Snapshot {
        let accent: Color
        let mode: DisplayMode
        let grouping: DotGrouping
        let selectedMonth: Int
        let period: Period
        let birthDate: Date?
        let lifeExpectancy: Int
    }

    static func snapshot() -> Snapshot {
        let d = SharedStore.read()
        let birth = (d[birthDateKey]).flatMap { $0.isEmpty ? nil : birthFormatter.date(from: $0) }
        return Snapshot(
            accent: Color(hex: d[ThemeColor.storageKey] ?? "") ?? ThemeColor.blue.color,
            mode: DisplayMode(rawValue: d[displayModeKey] ?? "") ?? .dots,
            grouping: DotGrouping(rawValue: d[dotGroupingKey] ?? "") ?? .continuous,
            selectedMonth: Int(d[selectedMonthKey] ?? "") ?? 0,
            period: Period(rawValue: d[periodKey] ?? "") ?? .year,
            birthDate: birth,
            lifeExpectancy: Int(d[lifeExpectancyKey] ?? "") ?? 80
        )
    }

    /// 앱이 현재 설정을 위젯과 공유하기 위해 한 번에 기록 (selectedMonth 는 개요로 초기화)
    static func push(theme: String, displayMode: String, dotGrouping: String,
                     period: String, birthDate: String, lifeExpectancy: String) {
        var d = SharedStore.read()
        d[ThemeColor.storageKey] = theme
        d[displayModeKey] = displayMode
        d[dotGroupingKey] = dotGrouping
        d[periodKey] = period
        d[birthDateKey] = birthDate
        d[lifeExpectancyKey] = lifeExpectancy
        d[selectedMonthKey] = "0"
        SharedStore.write(d)
    }
}

/// 올해를 하루 = 점 하나로 표현하는 그리드.
/// 365개 점을 SwiftUI 도형 대신 `Canvas` 로 한 번에 그려 위젯 렌더를 가볍게 합니다.
struct DotGridView: View {
    let dayOfYear: Int
    let totalDays: Int
    let accent: Color
    var columns: Int = 19   // 0 = 자동(영역을 꽉 채우도록 열 수 계산)
    var spacing: CGFloat = 2

    var body: some View {
        let past = accent
        let today = accent.darker()
        let future = accent.opacity(0.16)

        Canvas(opaque: false) { ctx, size in
            let cols = columns > 0 ? columns
                : Self.bestColumns(count: totalDays, size: size, spacing: spacing)
            let rows = max(Int(ceil(Double(totalDays) / Double(cols))), 1)
            let dotW = (size.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            let dotH = (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let dot = max(min(dotW, dotH), 1)
            let radius = dot * 0.28

            // 그리드를 가운데 정렬해 남는 여백을 양쪽으로 분산
            let gridW = CGFloat(cols) * dot + CGFloat(cols - 1) * spacing
            let gridH = CGFloat(rows) * dot + CGFloat(rows - 1) * spacing
            let ox = max((size.width - gridW) / 2, 0)
            let oy = max((size.height - gridH) / 2, 0)

            for i in 0..<totalDays {
                let row = i / cols
                let col = i % cols
                let x = ox + CGFloat(col) * (dot + spacing)
                let y = oy + CGFloat(row) * (dot + spacing)
                let rect = CGRect(x: x, y: y, width: dot, height: dot)
                let path = Path(roundedRect: rect, cornerRadius: radius)
                let day = i + 1
                let color: Color = (day == dayOfYear) ? today : (day < dayOfYear ? past : future)
                ctx.fill(path, with: .color(color))
            }
        }
    }

    /// 영역을 가장 꽉 채우는(=점이 가장 커지는) 열 수를 찾습니다.
    static func bestColumns(count: Int, size: CGSize, spacing: CGFloat) -> Int {
        guard count > 0, size.width > 0, size.height > 0 else { return max(count, 1) }
        var best = 1
        var bestDot: CGFloat = 0
        for c in 1...count {
            let rows = Int(ceil(Double(count) / Double(c)))
            let dw = (size.width - spacing * CGFloat(c - 1)) / CGFloat(c)
            let dh = (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let dot = min(dw, dh)
            if dot > bestDot { bestDot = dot; best = c }
        }
        return best
    }
}

/// 연/월 계산 헬퍼
enum YearMath {
    static func monthLengths(year: Int) -> [Int] {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        return (1...12).map { m in
            guard let d = cal.date(from: DateComponents(year: year, month: m, day: 1)),
                  let r = cal.range(of: .day, in: .month, for: d) else { return 30 }
            return r.count
        }
    }
    private static let shortSymbols = DateFormatter().shortStandaloneMonthSymbols ?? []
    private static let fullSymbols = DateFormatter().standaloneMonthSymbols ?? []

    static func monthShort(_ m: Int) -> String {
        if L.isKorean { return "\(m)월" }
        return shortSymbols.indices.contains(m - 1) ? shortSymbols[m - 1] : "\(m)"
    }
    static func monthName(_ m: Int) -> String {
        if L.isKorean { return "\(m)월" }
        return fullSymbols.indices.contains(m - 1) ? fullSymbols[m - 1] : "\(m)"
    }
}

/// 한 달을 7열 작은 점 격자로 표현 (개요용 미니 / 확대용 모두 dotSize 로 크기 조절)
struct MiniMonthView: View {
    let month: Int
    let year: Int
    let dayOfYear: Int
    let accent: Color
    var dotSize: CGFloat = 4
    var showsLabel: Bool = true

    var body: some View {
        let lengths = YearMath.monthLengths(year: year)
        let days = lengths[month - 1]
        let before = lengths.prefix(month - 1).reduce(0, +)
        let cols = 7
        let rows = Int(ceil(Double(days) / Double(cols)))
        let gap = max(dotSize * 0.22, 1)
        let labelFontSize = max(dotSize * 1.4, 7)
        let labelH = showsLabel ? labelFontSize + gap : 0

        let past = accent
        let today = accent.darker()
        let future = accent.opacity(0.18)
        let labelText = Text(YearMath.monthShort(month))
            .font(.system(size: labelFontSize, weight: .semibold))
            .foregroundStyle(.secondary)

        let width = CGFloat(cols) * (dotSize + gap) - gap
        let height = labelH + CGFloat(rows) * (dotSize + gap) - gap

        Canvas(opaque: false) { ctx, _ in
            if showsLabel {
                ctx.draw(ctx.resolve(labelText), at: CGPoint(x: 0, y: 0), anchor: .topLeading)
            }
            let r = dotSize * 0.3
            for i in 0..<days {
                let row = i / cols
                let col = i % cols
                let x = CGFloat(col) * (dotSize + gap)
                let y = labelH + CGFloat(row) * (dotSize + gap)
                let path = Path(roundedRect: CGRect(x: x, y: y, width: dotSize, height: dotSize), cornerRadius: r)
                let absDay = before + i + 1
                let color: Color = (absDay == dayOfYear) ? today : (absDay <= dayOfYear ? past : future)
                ctx.fill(path, with: .color(color))
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

/// 12개월을 cols × rows 미니 달력으로 보여주는 개요. (위젯 비율에 맞춰 열/행 조정)
/// 각 칸은 `cell` 클로저로 감싸 탭/인텐트를 붙입니다.
struct MonthOverviewGrid<Cell: View>: View {
    let year: Int
    let dayOfYear: Int
    let accent: Color
    var cols: Int = 3
    var rows: Int = 4
    var spacing: CGFloat = 6
    @ViewBuilder let cell: (Int, MiniMonthView) -> Cell

    var body: some View {
        GeometryReader { geo in
            let cellW = (geo.size.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            let cellH = (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            // 미니 달력: 라벨 + 최대 5행(31일). 라벨/여백까지 고려해 세로 여유를 둠.
            let dot = max(min(cellW / 7.4, cellH / 8.6), 1)

            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: spacing) {
                        ForEach(0..<cols, id: \.self) { c in
                            let m = r * cols + c + 1
                            if m <= 12 {
                                cell(m, MiniMonthView(month: m, year: year, dayOfYear: dayOfYear,
                                                      accent: accent, dotSize: dot))
                                    .frame(width: cellW, height: cellH, alignment: .top)
                            } else {
                                Color.clear.frame(width: cellW, height: cellH)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 한 달만 크게 보여주는 확대 달력(날짜 숫자 표시). 공간을 채우도록 스케일됩니다.
/// (부모가 높이를 정해줘야 함)
struct SingleMonthView: View {
    let month: Int
    let year: Int
    let dayOfYear: Int
    let accent: Color
    var spacing: CGFloat = 4

    var body: some View {
        let lengths = YearMath.monthLengths(year: year)
        let days = lengths[month - 1]
        let before = lengths.prefix(month - 1).reduce(0, +)
        let cols = 7
        let rows = Int(ceil(Double(days) / Double(cols)))

        GeometryReader { geo in
            // 셀이 영역(가로·세로)을 꽉 채우도록 직사각형으로 배치.
            let cellW = (geo.size.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            let cellH = (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)

            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: spacing) {
                        ForEach(0..<cols, id: \.self) { c in
                            let d = r * cols + c + 1
                            if d <= days {
                                dayCell(day: d, absDay: before + d, w: cellW, h: cellH)
                            } else {
                                Color.clear.frame(width: cellW, height: cellH)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(day: Int, absDay: Int, w: CGFloat, h: CGFloat) -> some View {
        let filled = absDay <= dayOfYear
        let isToday = absDay == dayOfYear
        let s = min(w, h)
        ZStack {
            RoundedRectangle(cornerRadius: s * 0.28, style: .continuous)
                .fill(filled ? accent : accent.opacity(0.15))
                .brightness(isToday ? -0.24 : 0)
            Text("\(day)")
                .font(.system(size: s * 0.46, weight: isToday ? .bold : .medium, design: .rounded))
                .minimumScaleFactor(0.5)
                .foregroundStyle(filled ? Color.white : accent.opacity(0.85))
        }
        .frame(width: w, height: h)
    }
}

/// 진행률을 원형 그래프로 표시 (가운데 퍼센트, 오른쪽에 % 기호).
struct RingGraphView: View {
    let fraction: Double
    let accent: Color
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [accent.opacity(0.55), accent]), center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(format: "%.2f", fraction * 100))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .padding(lineWidth + 6)
        }
    }
}

