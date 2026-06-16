import Foundation

/// (연, 월) 한 쌍. 월별 개요 격자의 각 칸을 식별합니다.
struct MonthRef: Identifiable {
    let year: Int
    let month: Int
    var id: String { "\(year)-\(month)" }
}

/// 연/월 계산 헬퍼
enum YearMath {
    // 월 길이는 불변이라 연도별로 캐싱 (미니 달력 12개가 매 렌더마다 호출)
    private static let lengthLock = NSLock()
    private static var lengthCache: [Int: [Int]] = [:]

    static func monthLengths(year: Int) -> [Int] {
        lengthLock.lock()
        defer { lengthLock.unlock() }
        if let cached = lengthCache[year] { return cached }
        let cal = Calendar(identifier: .gregorian).with { $0.locale = Locale(identifier: "en_US_POSIX") }
        let lengths = (1...12).map { m -> Int in
            guard let d = cal.date(from: DateComponents(year: year, month: m, day: 1)),
                  let r = cal.range(of: .day, in: .month, for: d) else { return 30 }
            return r.count
        }
        lengthCache[year] = lengths
        return lengths
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

    /// 그 달 1일이 들어갈 요일 칸(0부터). 달력처럼 1일을 제 요일 위치에 놓기 위함.
    static func weekdayOffset(year: Int, month: Int) -> Int {
        let c = Calendar.current
        guard let first = c.date(from: DateComponents(year: year, month: month, day: 1)) else { return 0 }
        let wd = c.component(.weekday, from: first)   // 1=일 … 7=토
        return (wd - c.firstWeekday + 7) % 7
    }

    /// 주어진 날짜의 달로 끝나는 `count`개월의 (연,월) 목록.
    static func monthsEndingAt(_ date: Date, count: Int) -> [MonthRef] {
        let c = Calendar.current
        guard let first = c.date(from: c.dateComponents([.year, .month], from: date)) else { return [] }
        return (0..<count).compactMap { i in
            let back = count - 1 - i
            guard let d = c.date(byAdding: .month, value: -back, to: first) else { return nil }
            let comp = c.dateComponents([.year, .month], from: d)
            return MonthRef(year: comp.year ?? 0, month: comp.month ?? 1)
        }
    }
}
