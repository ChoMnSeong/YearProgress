import SwiftUI
import ServiceManagement
import WidgetKit

/// 메뉴 막대 항목을 클릭하면 열리는 팝오버 내용.
struct PopoverContent: View {
    let onOpenWindow: () -> Void
    let onQuit: () -> Void

    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @AppStorage("showTime") private var showTime = false
    @AppStorage(ThemeColor.storageKey)
    private var themeHex = ThemeColor.defaultHex
    @AppStorage(AppSettings.displayModeKey)
    private var displayRaw = DisplayMode.dots.rawValue
    @AppStorage(AppSettings.dotGroupingKey)
    private var groupingRaw = DotGrouping.continuous.rawValue
    @AppStorage(AppSettings.periodKey)
    private var periodRaw = Period.year.rawValue
    @AppStorage(AppSettings.birthDateKey)
    private var birthDateStr = ""
    @AppStorage(AppSettings.lifeExpectancyKey)
    private var lifeExpStr = "80"
    @AppStorage(AppSettings.eventTitleKey)
    private var eventTitleStr = ""
    @AppStorage(AppSettings.eventDateKey)
    private var eventDateStr = ""

    @State private var zoomMonth: Int? = nil
    @StateObject private var calendar = CalendarAccess()

    // 컨트롤·바인딩에서 쓰는 파생값. (date 파싱은 currentInputs/ProgressInputs 로 일원화)
    private var period: Period { Period(rawValue: periodRaw) ?? .year }
    private var birthDate: Date? { birthDateStr.isEmpty ? nil : AppSettings.birthFormatter.date(from: birthDateStr) }
    private var lifeExpectancy: Int { Int(lifeExpStr) ?? 80 }

    private var birthBinding: Binding<Date> {
        Binding(
            get: { birthDate ?? Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date() },
            set: { birthDateStr = AppSettings.birthFormatter.string(from: $0); pushToWidget() }
        )
    }
    private var lifeExpBinding: Binding<Int> {
        Binding(get: { lifeExpectancy }, set: { lifeExpStr = String($0); pushToWidget() })
    }

    private var accent: Color { Color(hex: themeHex) ?? .blue }
    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: themeHex) ?? .blue },
            set: { newColor in
                let hex = newColor.toHexString() ?? themeHex
                themeHex = hex   // 앱 UI 는 즉시 반영
                // 컬러 휠 드래그 중 파일 쓰기/위젯 리로드가 폭주하지 않도록 디바운스
                Debouncer.shared.call {
                    let d = UserDefaults.standard
                    AppSettings.push(
                        theme: d.string(forKey: ThemeColor.storageKey) ?? hex,
                        displayMode: d.string(forKey: AppSettings.displayModeKey) ?? DisplayMode.dots.rawValue,
                        dotGrouping: d.string(forKey: AppSettings.dotGroupingKey) ?? DotGrouping.continuous.rawValue,
                        period: d.string(forKey: AppSettings.periodKey) ?? Period.year.rawValue,
                        birthDate: d.string(forKey: AppSettings.birthDateKey) ?? "",
                        lifeExpectancy: d.string(forKey: AppSettings.lifeExpectancyKey) ?? "80",
                        eventTitle: d.string(forKey: AppSettings.eventTitleKey) ?? "",
                        eventDate: d.string(forKey: AppSettings.eventDateKey) ?? ""
                    ) {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
            }
        )
    }
    private var displayMode: DisplayMode { DisplayMode(rawValue: displayRaw) ?? .dots }
    private var dotGrouping: DotGrouping { DotGrouping(rawValue: groupingRaw) ?? .continuous }

    @ViewBuilder
    private func visualization(_ progress: PeriodProgress) -> some View {
        switch displayMode {
        case .graph:
            RingGraphView(fraction: progress.fraction, accent: accent)
                .frame(height: 150)
        case .dots:
            if (progress.period == .year || progress.period == .event) && dotGrouping == .monthly {
                let refs = progress.monthRefs
                if let zm = zoomMonth, zm >= 1, zm <= refs.count {
                    let ref = refs[zm - 1]
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Button { zoomMonth = nil } label: {
                                Label(L.t("전체 보기", "All months"), systemImage: "chevron.left")
                            }
                            .buttonStyle(.borderless)
                            Text(YearMath.monthName(ref.month)).font(.headline)
                            Spacer()
                        }
                        SingleMonthView(month: ref.month, year: ref.year, today: progress.date, accent: accent)
                            .frame(height: 190)
                    }
                } else {
                    MonthOverviewGrid(months: refs, today: progress.date, accent: accent) { idx, mini in
                        mini.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .contentShape(Rectangle())
                            .onTapGesture { zoomMonth = idx }
                    }
                    .frame(height: 230)
                }
            } else {
                // 올해(365)는 촘촘하게, 그 외(달/주/일/인생)는 점이 적으니 크고 간격 넓게.
                // 이벤트도 1년(365점) 기준이라 올해처럼 다룹니다.
                let yearLike = progress.period == .year || progress.period == .event
                DotGridView(dayOfYear: progress.elapsed, totalDays: progress.total, accent: accent,
                            columns: yearLike ? 24 : 0,
                            spacing: yearLike ? 2 : 4)
                    .frame(height: yearLike ? 150 : 180)
            }
        }
    }

    var body: some View {
        // @AppStorage 문자열을 매초가 아니라 '여기서 한 번' 파싱(특히 날짜 DateFormatter).
        let inputs = currentInputs
        VStack(spacing: 12) {
            // 시간에 따라 변하는 부분(시계·퍼센트·시각화)만 매초 타임라인 안에 둡니다.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                progressSection(inputs.progress(at: context.date), accent: inputs.accent)
            }

            Divider()

            // 설정 컨트롤은 date 와 무관 → 타임라인 밖에 둬서 매초 재평가되지 않게 합니다.
            controlsSection
        }
        .padding()
        .frame(width: 260)
        .tint(inputs.accent)
        .task { if calendar.authorized { await calendar.loadUpcoming() } }
    }

    private var currentInputs: ProgressInputs {
        ProgressInputs(themeHex: themeHex, periodRaw: periodRaw, birthDateStr: birthDateStr,
                       lifeExpStr: lifeExpStr, eventTitleStr: eventTitleStr, eventDateStr: eventDateStr)
    }

    /// 매초 갱신되는 진행 표시(헤더 + 시각화 + 상세). 시간 의존부만 여기 모읍니다.
    @ViewBuilder
    private func progressSection(_ progress: PeriodProgress, accent: Color) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(progress.headline)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }

            visualization(progress)

            Text(progress.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// date 와 무관한 설정 컨트롤 모음 (타임라인 밖 = 매초 재평가 제외).
    @ViewBuilder
    private var controlsSection: some View {
        colorPicker

        // 기간 선택 (올해 / 이번 달 / 이번 주 / 오늘 / 인생)
        Picker(L.t("기간", "Period"), selection: $periodRaw) {
            ForEach(Period.allCases) { Text($0.label).tag($0.rawValue) }
        }
        .pickerStyle(.menu)
        .onChange(of: periodRaw) { _, _ in resetMonthAndReload() }

        // 인생: 생년월일 + 기대수명
        if period == .life {
            BirthDatePicker(date: birthBinding)
            Stepper(L.t("기대수명 \(lifeExpectancy)세", "Life expectancy \(lifeExpectancy)"),
                    value: lifeExpBinding, in: 1...120)
        }

        if period == .event {
            eventControls
        }

        Picker("", selection: $displayRaw) {
            ForEach(DisplayMode.allCases) { Text($0.label).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: displayRaw) { _, _ in resetMonthAndReload() }

        // 365/월별 전환은 "올해"·"이벤트" + 점 모드에서
        if displayMode == .dots && (period == .year || period == .event) {
            Picker("", selection: $groupingRaw) {
                ForEach(DotGrouping.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: groupingRaw) { _, _ in resetMonthAndReload() }
        }

        Toggle(L.t("메뉴 막대에 시간 표시", "Show time in menu bar"), isOn: $showTime)
            .toggleStyle(.checkbox)

        Toggle(L.t("로그인 시 자동 실행", "Launch at login"), isOn: $launchAtLogin)
            .toggleStyle(.checkbox)
            .onChange(of: launchAtLogin) { _, newValue in
                setLaunchAtLogin(newValue)
            }

        Button(L.t("앱 창 열기", "Open Window"), action: onOpenWindow)
        Button(L.t("종료", "Quit"), action: onQuit)
    }

    @ViewBuilder
    private var eventControls: some View {
        if calendar.authorized {
            Menu {
                if calendar.events.isEmpty {
                    Text(L.t("다가오는 이벤트 없음", "No upcoming events"))
                }
                ForEach(calendar.events) { ev in
                    Button {
                        eventTitleStr = ev.title
                        eventDateStr = AppSettings.birthFormatter.string(from: ev.date)
                        pushToWidget()
                    } label: {
                        Text("\(ev.title) · \(eventShort(ev.date))")
                    }
                }
            } label: {
                Text(eventTitleStr.isEmpty ? L.t("이벤트 선택", "Pick event") : eventTitleStr)
                    .lineLimit(1)
            }
        } else {
            Button(L.t("캘린더 접근 허용", "Allow Calendar access")) {
                calendar.requestAndLoad()
            }
        }
    }

    private static let eventShortFormatter = DateFormatter().then {
        $0.locale = L.locale
        $0.setLocalizedDateFormatFromTemplate("MMM d")
    }

    private func eventShort(_ d: Date) -> String {
        Self.eventShortFormatter.string(from: d)
    }

    private var colorPicker: some View {
        HStack(spacing: 7) {
            // 커스텀 색상(무지개 원형 → 시스템 색상 패널)
            CustomColorButton(color: colorBinding)

            Divider().frame(height: 18)

            // 빠른 프리셋
            ForEach(ThemeColor.allCases) { t in
                Circle()
                    .fill(t.color)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.85),
                                                   lineWidth: themeHex.caseInsensitiveCompare(t.hex) == .orderedSame ? 2 : 0))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .contentShape(Circle())
                    .onTapGesture {
                        themeHex = t.hex
                        pushToWidget()
                    }
                    .help(t.label)
            }
        }
    }

    private func pushToWidget() {
        AppSettings.push(theme: themeHex, displayMode: displayRaw, dotGrouping: groupingRaw,
                         period: periodRaw, birthDate: birthDateStr, lifeExpectancy: lifeExpStr,
                         eventTitle: eventTitleStr, eventDate: eventDateStr) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func resetMonthAndReload() {
        zoomMonth = nil
        pushToWidget()   // push 가 selectedMonth 을 0(개요)으로 초기화
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 실패하면 실제 상태로 토글을 되돌립니다.
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}
