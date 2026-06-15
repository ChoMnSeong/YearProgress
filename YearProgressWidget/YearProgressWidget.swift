import WidgetKit
import SwiftUI
import AppIntents

/// 위젯에서 달을 탭하면 해당 월만 확대(0 = 개요로 복귀). App Group 에 저장.
struct SelectMonthIntent: AppIntent {
    static var title: LocalizedStringResource = "Select Month"

    @Parameter(title: "Month") var month: Int

    init() {}
    init(month: Int) { self.month = month }

    func perform() async throws -> some IntentResult {
        SharedStore.set(AppSettings.selectedMonthKey, String(month))
        return .result()
    }
}

// MARK: - Timeline

struct YearProgressEntry: TimelineEntry {
    let date: Date
    let progress: PeriodProgress
    // 설정값을 엔트리에 구워넣어 리로드 때 확실히 반영합니다.
    let accent: Color
    let mode: DisplayMode
    let grouping: DotGrouping
    let selectedMonth: Int
}

struct YearProgressProvider: TimelineProvider {
    private func makeEntry(date: Date, _ s: AppSettings.Snapshot) -> YearProgressEntry {
        YearProgressEntry(
            date: date,
            progress: PeriodProgress.current(period: s.period, date: date,
                                             birthDate: s.birthDate, lifeExpectancy: s.lifeExpectancy,
                                             eventTitle: s.eventTitle, eventDate: s.eventDate),
            accent: s.accent,
            mode: s.mode,
            grouping: s.grouping,
            selectedMonth: s.selectedMonth
        )
    }

    func placeholder(in context: Context) -> YearProgressEntry {
        // 갤러리/리덕션용 — 즉시 반환해야 하므로 디스크(설정 파일)를 읽지 않습니다.
        YearProgressEntry(date: Date(),
                          progress: PeriodProgress.current(period: .year),
                          accent: Color(hex: ThemeColor.defaultHex) ?? .blue,
                          mode: .dots, grouping: .continuous, selectedMonth: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (YearProgressEntry) -> Void) {
        completion(makeEntry(date: Date(), AppSettings.snapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<YearProgressEntry>) -> Void) {
        // 설정은 타임라인당 한 번만 읽습니다.
        let snapshot = AppSettings.snapshot()
        let calendar = Calendar.current
        let now = Date()
        // 지금 즉시 1개 + 이후 24개는 '정각'에 맞춰 — 시간 단위 표시(오늘 기간 등)가
        // 정각에 바로 갱신되도록 합니다. (기존엔 임의 분 오프셋이라 최대 59분 늦게 갱신)
        var entries = [makeEntry(date: now, snapshot)]
        if let hourStart = calendar.dateInterval(of: .hour, for: now)?.start {
            for hourOffset in 1...24 {
                if let date = calendar.date(byAdding: .hour, value: hourOffset, to: hourStart) {
                    entries.append(makeEntry(date: date, snapshot))
                }
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Widget

struct YearProgressWidget: Widget {
    let kind = "com.ensnif.YearProgress.YearProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: YearProgressProvider()) { entry in
            YearProgressWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(L.t("올해 진행률", "Year Progress"))
        .description(L.t("이번 해가 얼마나 지났는지 점으로 보여줍니다.", "See the year pass, one dot per day."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry View

struct YearProgressWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: YearProgressEntry

    private var p: PeriodProgress { entry.progress }
    private var accent: Color { entry.accent }

    var body: some View {
        switch entry.mode {
        case .graph:
            graphLayout()
        case .dots:
            dotsLayout()
        }
    }

    // MARK: 그래프 모드

    @ViewBuilder
    private func graphLayout() -> some View {
        switch family {
        case .systemSmall:
            VStack(spacing: 8) {
                RingGraphView(fraction: p.fraction, accent: accent)
                Text(p.remainingText)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        default:
            HStack(spacing: 18) {
                RingGraphView(fraction: p.fraction, accent: accent)
                    .frame(maxWidth: family == .systemLarge ? 230 : 130)
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.title)
                        .font(.title3.weight(.bold))
                    Text(p.detail)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 점 모드

    @ViewBuilder
    private func dotsLayout() -> some View {
        switch family {
        case .systemSmall:
            dotsContent(columns: 19, yearFont: .subheadline, pctFont: .headline, showFooter: false)
        case .systemLarge:
            dotsContent(columns: 22, yearFont: .title3, pctFont: .title2, showFooter: true)
        default:
            dotsContent(columns: 31, yearFont: .headline, pctFont: .title3, showFooter: false)
        }
    }

    private func dotsContent(columns: Int,
                             yearFont: Font, pctFont: Font, showFooter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(p.title)
                    .font(yearFont.weight(.bold))
                    .lineLimit(1)
                Spacer()
                Text(p.headline)
                    .font(pctFont.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }

            dotsVisualization(columns: columns)

            if showFooter {
                Text(p.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func dotsVisualization(columns: Int) -> some View {
        // 월별 개요/확대는 "올해"·"이벤트" 기간 + 월별 모드에서. 그 외엔 단위 점 그리드.
        if (p.period == .year || p.period == .event) && entry.grouping == .monthly {
            monthlyView()
        } else {
            // 이벤트도 1년(365점) 기준이라 올해처럼 다룹니다.
            let yearLike = p.period == .year || p.period == .event
            DotGridView(dayOfYear: p.elapsed, totalDays: p.total, accent: accent,
                        columns: yearLike ? columns : 0,
                        spacing: yearLike ? 2 : 3)
        }
    }

    @ViewBuilder
    private func monthlyView() -> some View {
        let refs = p.monthRefs
        Group {
            if entry.selectedMonth >= 1, entry.selectedMonth <= refs.count {
                let ref = refs[entry.selectedMonth - 1]
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Button(intent: SelectMonthIntent(month: 0)) {
                            Label(L.t("전체 보기", "All months"), systemImage: "chevron.left")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(accent)
                                .padding(.vertical, 5)
                                .padding(.trailing, 6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Text(YearMath.monthName(ref.month))
                            .font(.headline)
                        Spacer()
                    }
                    SingleMonthView(month: ref.month, year: ref.year, today: entry.date, accent: accent)
                }
            } else {
                // 중간 위젯은 가로로 넓고 낮아 6열×2행, 그 외(작은/큰)는 3열×4행.
                let wide = family == .systemMedium
                MonthOverviewGrid(months: refs, today: entry.date, accent: accent,
                                  cols: wide ? 6 : 3, rows: wide ? 2 : 4) { idx, mini in
                    Button(intent: SelectMonthIntent(month: idx)) { mini }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview(as: .systemMedium) {
    YearProgressWidget()
} timeline: {
    YearProgressEntry(date: .now, progress: PeriodProgress.current(period: .year), accent: .blue, mode: .dots, grouping: .monthly, selectedMonth: 0)
}
