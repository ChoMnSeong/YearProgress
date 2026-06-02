import SwiftUI
import AppKit
import ServiceManagement
import WidgetKit

@main
struct YearProgressApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 메뉴 막대 전용 앱이라 자동으로 열리는 창이 없는 Settings 씬만 둡니다.
        Settings { EmptyView() }
    }
}

// MARK: - 메뉴 막대 / 앱 본체 (AppKit)

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var timer: Timer?
    private var mainWindow: NSWindow?

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

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 260, height: 660)
        popover.contentViewController = NSHostingController(
            rootView: PopoverContent(
                onOpenWindow: { [weak self] in self?.showMainWindow() },
                onQuit: { NSApp.terminate(nil) }
            )
        )

        // 1초마다 메뉴 막대 아이콘·텍스트를 갱신합니다.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        updateStatusItem()

        // 저장된 설정을 공유 파일에서 불러와 앱 UI(표준 defaults)에 반영. (파일을 덮어쓰지 않음)
        let s = SharedStore.read()
        let std = UserDefaults.standard
        if let t = s[ThemeColor.storageKey] { std.set(t, forKey: ThemeColor.storageKey) }
        if let m = s[AppSettings.displayModeKey] { std.set(m, forKey: AppSettings.displayModeKey) }
        if let g = s[AppSettings.dotGroupingKey] { std.set(g, forKey: AppSettings.dotGroupingKey) }
        if let p = s[AppSettings.periodKey] { std.set(p, forKey: AppSettings.periodKey) }
        if let b = s[AppSettings.birthDateKey] { std.set(b, forKey: AppSettings.birthDateKey) }
        if let le = s[AppSettings.lifeExpectancyKey] { std.set(le, forKey: AppSettings.lifeExpectancyKey) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
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
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// 메뉴 막대 항목의 링 아이콘과 텍스트를 갱신합니다.
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let now = Date()
        let d = UserDefaults.standard
        let showTime = d.bool(forKey: "showTime")
        let period = Period(rawValue: d.string(forKey: AppSettings.periodKey) ?? "") ?? .year
        let birth = d.string(forKey: AppSettings.birthDateKey).flatMap {
            $0.isEmpty ? nil : AppSettings.birthFormatter.date(from: $0)
        }
        let lifeExp = Int(d.string(forKey: AppSettings.lifeExpectancyKey) ?? "") ?? 80
        let progress = PeriodProgress.current(period: period, date: now, birthDate: birth, lifeExpectancy: lifeExp)
        // 메뉴 막대 링은 흰색 고정 (테마 색과 무관).
        button.image = Self.progressIcon(fraction: progress.fraction, color: .white)
        button.title = MenuBarFormat.title(date: now, showTime: showTime, percentText: progress.formattedPercent) + " "
    }

    /// 진행률만큼 채워지는 원형 링(도넛) 아이콘. 선택한 테마 색으로 그립니다.
    private static func progressIcon(fraction: Double, color: NSColor) -> NSImage {
        let size: CGFloat = 14
        let lineWidth: CGFloat = 2.2
        let clamped = CGFloat(min(max(fraction, 0), 1))

        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let center = NSPoint(x: size / 2, y: size / 2)
        let radius = size / 2 - lineWidth / 2 - 0.5

        // 배경 트랙(옅게)
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        color.withAlphaComponent(0.28).setStroke()
        track.stroke()

        // 진행 호 (위쪽 12시에서 시계 방향)
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

        image.unlockFocus()
        // 색을 입히므로 템플릿 모드를 끕니다.
        image.isTemplate = false
        return image
    }
}

// MARK: - 날짜 포맷

enum MenuBarFormat {
    // 시스템 선호 언어를 따라가고, 시간은 24시간제(HH)로 고정합니다.
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

    @State private var zoomMonth: Int? = nil

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
                        lifeExpectancy: d.string(forKey: AppSettings.lifeExpectancyKey) ?? "80"
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
            if progress.period == .year && dotGrouping == .monthly {
                if let zm = zoomMonth {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Button { zoomMonth = nil } label: {
                                Label(L.t("전체 보기", "All months"), systemImage: "chevron.left")
                            }
                            .buttonStyle(.borderless)
                            Text(YearMath.monthName(zm)).font(.headline)
                            Spacer()
                        }
                        SingleMonthView(month: zm, year: progress.year, dayOfYear: progress.dayOfYear,
                                        accent: accent)
                            .frame(height: 190)
                    }
                } else {
                    MonthOverviewGrid(year: progress.year, dayOfYear: progress.dayOfYear,
                                      accent: accent) { m, mini in
                        mini.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .contentShape(Rectangle())
                            .onTapGesture { zoomMonth = m }
                    }
                    .frame(height: 230)
                }
            } else {
                // 올해(365)는 촘촘하게, 그 외(달/주/일/인생)는 점이 적으니 크고 간격 넓게.
                let isYear = progress.period == .year
                DotGridView(dayOfYear: progress.elapsed, totalDays: progress.total, accent: accent,
                            columns: isYear ? 24 : 0,
                            spacing: isYear ? 2 : 4)
                    .frame(height: isYear ? 150 : 180)
            }
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = PeriodProgress.current(period: period, date: context.date,
                                                  birthDate: birthDate, lifeExpectancy: lifeExpectancy)

            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(progress.title)
                        .font(.headline)
                    Spacer()
                    Text(progress.formattedPercent)
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

                Picker("", selection: $displayRaw) {
                    ForEach(DisplayMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: displayRaw) { _, _ in resetMonthAndReload() }

                // 365/월별 전환은 "올해" + 점 모드에서만
                if displayMode == .dots && period == .year {
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
        }
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
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
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
                         period: periodRaw, birthDate: birthDateStr, lifeExpectancy: lifeExpStr)
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
                .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
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
