import SwiftUI
import AppKit
import ServiceManagement
import WidgetKit
import EventKit

@main
struct YearProgressApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 메뉴 막대 전용 앱이라 자동으로 열리는 창이 없는 Settings 씬만 둡니다.
        Settings { EmptyView() }
    }
}

// MARK: - 메뉴 막대 / 앱 본체 (AppKit)

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var timer: Timer?
    private var mainWindow: NSWindow?
    private var lastTitle = ""
    private var lastRingKey = -1
    // RunCat 방식: 링 이미지를 정수 %별로 캐싱해 재사용(매번 새로 그리지 않음).
    private var ringCache: [Int: NSImage] = [:]
    // 매초 UserDefaults 읽기 + 날짜 문자열 파싱을 피하기 위한 설정 캐시.
    private var settings = MenuBarSettings.load()
    private let calendar = Calendar.current

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 아이콘 숨김 + Command-Tab 전환기에서 제외 (메뉴 막대 전용)
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.imagePosition = .imageTrailing
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        // 팝오버 내용 뷰는 '열 때' 만들고 닫히면 버립니다(popoverDidClose).
        // 미리 만들어 두면 닫힌 뒤에도 SwiftUI TimelineView 가 매초 전체 UI 를
        // 재렌더해 CPU 를 계속 점유하는 문제가 있었습니다.
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 260, height: 660)
        popover.delegate = self

        // 저장된 설정을 공유 파일에서 불러와 앱 UI(표준 defaults)에 반영. (파일을 덮어쓰지 않음)
        let s = SharedStore.read()
        let std = UserDefaults.standard
        if let t = s[ThemeColor.storageKey] { std.set(t, forKey: ThemeColor.storageKey) }
        if let m = s[AppSettings.displayModeKey] { std.set(m, forKey: AppSettings.displayModeKey) }
        if let g = s[AppSettings.dotGroupingKey] { std.set(g, forKey: AppSettings.dotGroupingKey) }
        if let p = s[AppSettings.periodKey] { std.set(p, forKey: AppSettings.periodKey) }
        if let b = s[AppSettings.birthDateKey] { std.set(b, forKey: AppSettings.birthDateKey) }
        if let le = s[AppSettings.lifeExpectancyKey] { std.set(le, forKey: AppSettings.lifeExpectancyKey) }
        if let et = s[AppSettings.eventTitleKey] { std.set(et, forKey: AppSettings.eventTitleKey) }
        if let ed = s[AppSettings.eventDateKey] { std.set(ed, forKey: AppSettings.eventDateKey) }
        settings = MenuBarSettings.load()
        WidgetCenter.shared.reloadAllTimelines()

        // 설정이 바뀌면 캐시를 갱신하고 즉시 다시 그립니다.
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)

        // 깨어남/디스플레이 재구성/외관 변화 시 강제 갱신 — 메뉴 막대 항목이
        // 이전 외관(예: 다크 막대에 검은 글자)으로 남는 문제를 막습니다.
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(forceRefresh), name: NSWorkspace.didWakeNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(forceRefresh), name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(forceRefresh),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // 주의: button.effectiveAppearance KVO 는 쓰지 않습니다 — AppKit 이 레플리컨트
        // 스냅샷을 뜰 때 외관을 임시로 바꿨다 되돌려서 KVO 가 진동하고, 강제 갱신과
        // 맞물리면 무한 재렌더(CPU 100%)가 됩니다. 일반 title + template 이미지는
        // 그릴 때마다 외관을 다시 해석하므로, 위의 깨어남/화면 알림 3개로 충분합니다.

        // 1초마다 메뉴 막대 텍스트를 갱신 — 정각 초에 맞춰 시작.
        let nextSecond = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down) + 1)
        let timer = Timer(fire: nextSecond, interval: 1, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
        timer.tolerance = 0.05   // 초 표시가 밀리지 않는 한도 내에서 전력 절약
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        updateStatusItem()
    }

    @objc private func settingsChanged() {
        // NSStatusItem 위치 저장 등 우리 설정과 무관한 defaults 변경도 이 알림으로 오므로,
        // 실제로 값이 바뀐 경우에만 다시 그립니다. (불필요한 항목 재렌더 방지)
        let loaded = MenuBarSettings.load()
        guard loaded != settings else { return }
        settings = loaded
        lastTitle = ""
        lastRingKey = -1
        updateStatusItem()
    }

    private var refreshPending = false

    /// 깨어남·디스플레이 재구성·외관 변화 후 항목을 강제로 다시 그립니다.
    /// 변경 가드(lastTitle/lastRingKey)가 "값이 같으면 그리지 않음"이라,
    /// 외관만 바뀐 경우 글자가 이전 색(검정)으로 남는 것을 여기서 풉니다.
    /// 알림이 짧은 시간에 몰려올 수 있어(깨어남 직후 폭주) 한 사이클로 합칩니다.
    /// 주의: button.appearance 는 절대 건드리지 않음 — 세팅하면 effectiveAppearance
    /// 재계산 → KVO 재발화 → 무한 갱신 루프(CPU 100%)가 됩니다.
    @objc private func forceRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.lastTitle = ""
            self.lastRingKey = -1
            self.ringCache.removeAll()   // 화면 배율이 바뀌었을 수 있어 함께 비움
            self.updateStatusItem()
            self.statusItem.button?.needsDisplay = true
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.contentViewController = NSHostingController(
                rootView: PopoverContent(
                    onOpenWindow: { [weak self] in self?.showMainWindow() },
                    onQuit: { NSApp.terminate(nil) }
                )
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// 닫힌 팝오버의 SwiftUI 가 백그라운드에서 계속 틱하지 않도록 내용을 버립니다.
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    private func showMainWindow() {
        if mainWindow == nil {
            let hosting = NSHostingController(rootView: ContentView())
            let window = NSWindow(contentViewController: hosting)
            window.title = L.t("올해 진행률", "Year Progress")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 360, height: 520))
            window.center()
            mainWindow = window
            // 창을 닫으면 해제 — 닫힌 창의 1초 TimelineView 가 계속 돌지 않도록.
            NotificationCenter.default.addObserver(self, selector: #selector(mainWindowClosed(_:)),
                                                   name: NSWindow.willCloseNotification, object: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func mainWindowClosed(_ note: Notification) {
        guard let w = note.object as? NSWindow, w === mainWindow else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: w)
        mainWindow = nil
    }

    /// 메뉴 막대 항목을 갱신합니다. (RunCat 방식)
    /// - 텍스트: monospaced 라 초가 바뀌어도 폭 동일 → 재배치 없음. 문자열이 실제로 바뀔 때만 세팅.
    /// - 링: 정수 % 가 바뀔 때만(=몇 분에 한 번) '캐시된' 이미지로 교체. 매번 새로 그리지 않음.
    /// - statusItem.length 는 절대 직접 세팅하지 않음(variableLength 자동) → 상태바 레이아웃 패스 강제 안 함.
    ///   이 세 가지가 제어센터 전체 리로드를 막는 핵심입니다.
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let now = Date()
        let s = settings   // 캐시된 설정 — 매초 defaults 읽기/날짜 파싱 없음
        let progress = PeriodProgress.current(period: s.period, date: now, birthDate: s.birthDate,
                                              lifeExpectancy: s.lifeExpectancy,
                                              eventTitle: s.eventTitle, eventDate: s.eventDate,
                                              calendar: calendar)

        // 초가 바뀔 때마다 호출되지만, 문자열이 같으면 건드리지 않습니다.
        let title = MenuBarFormat.title(date: now, showTime: s.showTime, percentText: progress.headline)
        if title != lastTitle {
            lastTitle = title
            button.title = title
        }

        // 링: 정수 % 가 바뀔 때만 캐시 이미지로 교체. (캐시 내용이 결정적이도록 버킷 값으로 그림)
        let ringKey = Int((progress.fraction * 100).rounded())
        if ringKey != lastRingKey {
            lastRingKey = ringKey
            let image = ringCache[ringKey] ?? {
                let img = Self.progressIcon(fraction: Double(ringKey) / 100)
                ringCache[ringKey] = img
                return img
            }()
            button.image = image
        }
    }

    /// 진행률만큼 채워지는 원형 링(도넛) 아이콘. drawingHandler 방식이라 화면 배율이
    /// 바뀌어도 AppKit 이 필요한 해상도로 다시 그리고, template 이라 메뉴 막대 명암에 자동 적응합니다.
    private static func progressIcon(fraction: Double) -> NSImage {
        let size: CGFloat = 14
        let lineWidth: CGFloat = 2.2
        let clamped = CGFloat(min(max(fraction, 0), 1))

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let center = NSPoint(x: size / 2, y: size / 2)
            let radius = size / 2 - lineWidth / 2 - 0.5
            let color = NSColor.black   // template 모드라 실제 색은 시스템이 입힘

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            color.withAlphaComponent(0.30).setStroke()
            track.stroke()

            if clamped > 0 {
                let start: CGFloat = 90
                let end = start - clamped * 360
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                color.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = true   // 메뉴 막대 명암 자동 적응(다크/라이트)
        return image
    }
}

/// 메뉴 막대 갱신에 필요한 설정 스냅샷. 설정이 바뀔 때만 다시 로드합니다.
private struct MenuBarSettings: Equatable {
    var showTime: Bool
    var period: Period
    var birthDate: Date?
    var lifeExpectancy: Int
    var eventTitle: String?
    var eventDate: Date?

    static func load() -> MenuBarSettings {
        let d = UserDefaults.standard
        func date(_ key: String) -> Date? {
            guard let s = d.string(forKey: key), !s.isEmpty else { return nil }
            return AppSettings.birthFormatter.date(from: s)
        }
        return MenuBarSettings(
            showTime: d.bool(forKey: "showTime"),
            period: Period(rawValue: d.string(forKey: AppSettings.periodKey) ?? "") ?? .year,
            birthDate: date(AppSettings.birthDateKey),
            lifeExpectancy: Int(d.string(forKey: AppSettings.lifeExpectancyKey) ?? "") ?? 80,
            eventTitle: d.string(forKey: AppSettings.eventTitleKey),
            eventDate: date(AppSettings.eventDateKey)
        )
    }
}

// MARK: - 날짜 포맷

enum MenuBarFormat {
    // 앱 창·메뉴 막대 공용: 초까지 (24시간제). 메뉴 막대 폭은 고정돼 있어 매초 갱신해도 재배치 안 됨.
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = L.locale
        f.setLocalizedDateFormatFromTemplate("EEE MMM d HH:mm:ss")
        return f
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = L.locale
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()

    /// 앱 창용. 예: "6월 1일 (월) 오후 4:21:18"
    static func dateTime(date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    /// 메뉴 막대용. 날짜(+선택적 시간) + 선택한 기간의 진행률.
    static func title(date: Date, showTime: Bool, percentText: String) -> String {
        let datePart = showTime ? dateTimeFormatter.string(from: date) : dateOnlyFormatter.string(from: date)
        return "\(datePart) · \(percentText)"
    }
}

// MARK: - 메뉴 막대 팝오버 내용

private struct PopoverContent: View {
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

    private var period: Period { Period(rawValue: periodRaw) ?? .year }
    private var birthDate: Date? { birthDateStr.isEmpty ? nil : AppSettings.birthFormatter.date(from: birthDateStr) }
    private var lifeExpectancy: Int { Int(lifeExpStr) ?? 80 }
    private var eventDate: Date? { eventDateStr.isEmpty ? nil : AppSettings.birthFormatter.date(from: eventDateStr) }
    private var eventTitleValue: String? { eventTitleStr.isEmpty ? nil : eventTitleStr }

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
                    )
                    WidgetCenter.shared.reloadAllTimelines()
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
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = PeriodProgress.current(period: period, date: context.date,
                                                  birthDate: birthDate, lifeExpectancy: lifeExpectancy,
                                                  eventTitle: eventTitleValue, eventDate: eventDate)

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

                Divider()

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
            .padding()
            .frame(width: 260)
            .tint(accent)
            .onAppear { if calendar.authorized { calendar.loadUpcoming() } }
        }
    }

    @ViewBuilder
    private var eventControls: some View {
        if calendar.authorized {
            Menu {
                if calendar.events.isEmpty {
                    Text(L.t("다가오는 이벤트 없음", "No upcoming events"))
                }
                ForEach(calendar.events, id: \.eventIdentifier) { ev in
                    Button {
                        eventTitleStr = ev.title ?? L.t("이벤트", "Event")
                        eventDateStr = AppSettings.birthFormatter.string(from: ev.startDate)
                        pushToWidget()
                    } label: {
                        Text("\(ev.title ?? "") · \(eventShort(ev.startDate))")
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

    private static let eventShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = L.locale
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

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
                         eventTitle: eventTitleStr, eventDate: eventDateStr)
        WidgetCenter.shared.reloadAllTimelines()
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

// MARK: - 캘린더(EventKit) 접근 + 다가오는 이벤트

@MainActor
final class CalendarAccess: ObservableObject {
    @Published var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var events: [EKEvent] = []
    private let store = EKEventStore()

    var authorized: Bool { status == .fullAccess }

    func requestAndLoad() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            Task { @MainActor in
                self?.status = EKEventStore.authorizationStatus(for: .event)
                self?.loadUpcoming()
            }
        }
    }

    func loadUpcoming() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .year, value: 2, to: now) ?? now
        let pred = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let cal = Calendar.current
        var seen = Set<String>()
        events = store.events(matching: pred)
            .sorted { $0.startDate < $1.startDate }
            // 여러 계정에 같은 공휴일이 중복되므로 제목+날짜 기준으로 하나만 남깁니다.
            .filter { ev in
                let day = Int(cal.startOfDay(for: ev.startDate).timeIntervalSince1970)
                let key = "\((ev.title ?? "").trimmingCharacters(in: .whitespaces))|\(day)"
                return seen.insert(key).inserted
            }
            .prefix(60)
            .map { $0 }
    }
}

// MARK: - 생년월일 선택 (연/월/일 드롭다운)

private struct BirthDatePicker: View {
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

// MARK: - 커스텀 색상 버튼 (무지개 원 → 시스템 색상 패널)

private struct CustomColorButton: View {
    @Binding var color: Color

    var body: some View {
        Button {
            ColorPanelController.shared.show(initial: color) { color = $0 }
        } label: {
            Circle()
                .fill(AngularGradient(
                    gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]),
                    center: .center
                ))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(L.t("색상 직접 선택", "Pick a custom color"))
    }
}

/// 연속 호출을 마지막 한 번으로 모으는 디바운서.
final class Debouncer {
    static let shared = Debouncer()
    private var work: DispatchWorkItem?

    func call(after: TimeInterval = 0.3, _ block: @escaping () -> Void) {
        work?.cancel()
        let w = DispatchWorkItem(block: block)
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: w)
    }
}

/// 시스템 색상 패널(NSColorPanel)을 띄우고 선택을 콜백으로 전달.
private final class ColorPanelController: NSObject {
    static let shared = ColorPanelController()
    private var onChange: ((Color) -> Void)?

    func show(initial: Color, onChange: @escaping (Color) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(initial)
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.isFloatingPanel = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(Color(nsColor: sender.color))
    }
}
