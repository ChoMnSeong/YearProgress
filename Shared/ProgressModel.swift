import Foundation

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

// MARK: - 기간(올해/이번 달/주/오늘/인생/이벤트)

enum Period: String, CaseIterable, Identifiable {
    case year, month, week, day, life, event
    var id: String { rawValue }
    var label: String {
        switch self {
        case .year:  return L.t("올해", "Year")
        case .month: return L.t("이번 달", "Month")
        case .week:  return L.t("이번 주", "Week")
        case .day:   return L.t("오늘", "Day")
        case .life:  return L.t("인생", "Life")
        case .event: return L.t("이벤트", "Event")
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
    let headline: String      // 메뉴 막대/헤더 큰 글자 (보통 "41.78%", 이벤트는 "D-23")
    let dotColumns: Int
    let year: Int             // 연 단위 시각화(월별 개요)용
    let dayOfYear: Int
    let date: Date            // 기준(오늘) 시각 — 달력 채움 기준
    let eventDate: Date?      // 이벤트 기간일 때 그 이벤트 날짜 (월 그리드 구간 계산용)

    var percent: Double { fraction * 100 }
    var formattedPercent: String { String(format: "%.2f%%", percent) }

    static func current(period: Period,
                        date: Date = Date(),
                        birthDate: Date? = nil,
                        lifeExpectancy: Int = 80,
                        eventTitle: String? = nil,
                        eventDate: Date? = nil,
                        calendar: Calendar = .current) -> PeriodProgress {
        let yp = YearProgress.current(date: date, calendar: calendar)

        func clampFraction(_ start: Date, _ end: Date) -> Double {
            let span = end.timeIntervalSince(start)
            return span > 0 ? min(max(date.timeIntervalSince(start) / span, 0), 1) : 0
        }
        func build(fraction: Double, elapsed: Int, total: Int, title: String,
                   remainingUnit: String, cols: Int,
                   detail: String? = nil, headline: String? = nil, eventDate: Date? = nil) -> PeriodProgress {
            let rem = max(total - elapsed, 0)
            let remText = "\(rem)\(remainingUnit)"
            let pct = String(format: "%.2f%%", fraction * 100)
            return PeriodProgress(period: period, fraction: fraction, elapsed: elapsed, total: total,
                                  remaining: rem, title: title, remainingText: remText,
                                  detail: detail ?? "\(elapsed) / \(total) · \(remText)",
                                  headline: headline ?? pct,
                                  dotColumns: cols, year: yp.year, dayOfYear: yp.dayOfYear,
                                  date: date, eventDate: eventDate)
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
            // 시스템 설정과 무관하게 항상 월요일부터 시작하는 주로 계산합니다. (1=일 … 2=월)
            let weekCal = calendar.with { $0.firstWeekday = 2 }
            let interval = weekCal.dateInterval(of: .weekOfYear, for: date)
            let start = interval?.start ?? date
            let end = interval?.end ?? date
            let startOfDay = weekCal.startOfDay(for: date)
            let daysIn = (weekCal.dateComponents([.day], from: start, to: startOfDay).day ?? 0) + 1
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

        case .event:
            guard let ev = eventDate else {
                return build(fraction: 0, elapsed: 0, total: 1,
                             title: L.t("이벤트 미설정", "No event"),
                             remainingUnit: "", cols: 10,
                             detail: L.t("캘린더 이벤트를 선택하세요", "Pick a calendar event"),
                             headline: "—")
            }
            let startToday = calendar.startOfDay(for: date)
            let evDay = calendar.startOfDay(for: ev)
            let daysUntil = calendar.dateComponents([.day], from: startToday, to: evDay).day ?? 0

            let head: String
            if daysUntil > 0 { head = "D-\(daysUntil)" }
            else if daysUntil == 0 { head = L.t("D-DAY", "D-DAY") }
            else { head = L.t("지남", "Past") }

            let title = eventTitle ?? L.t("이벤트", "Event")
            let detail = "\(head) · \(AppSettings.eventDetailFormatter.string(from: ev))"

            // 작년 이벤트 "다음날" ~ 이벤트 날짜 (예: 2025-06-07 ~ 2026-06-06, 정확히 365일) 구간을 채웁니다.
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: ev) ?? ev
            let startDate = calendar.date(byAdding: .day, value: 1, to: oneYearAgo) ?? oneYearAgo
            let startDay = calendar.startOfDay(for: startDate)
            let total = max((calendar.dateComponents([.day], from: startDay, to: evDay).day ?? 364) + 1, 1)
            let elapsed = max(min((calendar.dateComponents([.day], from: startDay, to: startToday).day ?? 0) + 1, total), 0)
            let frac = clampFraction(startDate, ev)
            return build(fraction: frac, elapsed: elapsed, total: total, title: title,
                         remainingUnit: "", cols: 19, detail: detail, headline: head, eventDate: ev)
        }
    }
}

extension PeriodProgress {
    /// 월별 개요에 표시할 월 목록. 이벤트면 이벤트 달로 끝나는 12개월, 그 외엔 그 해 1~12월.
    var monthRefs: [MonthRef] {
        if period == .event, let ev = eventDate {
            return YearMath.monthsEndingAt(ev, count: 12)
        }
        return (1...12).map { MonthRef(year: year, month: $0) }
    }
}
