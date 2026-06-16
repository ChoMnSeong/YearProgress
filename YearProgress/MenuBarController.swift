import AppKit

/// 메뉴 막대 상태 항목(텍스트 + 링 아이콘)을 전담하는 컨트롤러.
/// AppDelegate 에서 분리해, 상태 항목 갱신·외관 복구·성능 관련 로직을 한곳에 모읍니다.
///
/// 제어센터 전체 리로드/검은 글자/CPU 폭주를 막는 핵심 원칙:
/// - 텍스트는 monospaced 라 초가 바뀌어도 폭이 동일 → 재배치 없음. 문자열이 바뀔 때만 세팅.
/// - 링은 정수 % 가 바뀔 때만 '캐시된' template 이미지로 교체.
/// - statusItem.length 는 절대 직접 세팅하지 않음(variableLength 자동).
/// - 깨어남/디스플레이 변화 알림에서만 강제 재그리기(코얼레싱). effectiveAppearance KVO 는 금지.
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onClick: () -> Void
    private let calendar = Calendar.current

    private var timer: Timer?
    private var lastTitle = ""
    private var lastRingKey = -1
    private var refreshPending = false
    // RunCat 방식: 링 이미지를 정수 %별로 캐싱해 재사용(매번 새로 그리지 않음).
    private var ringCache: [Int: NSImage] = [:]
    // 매초 UserDefaults 읽기 + 날짜 문자열 파싱을 피하기 위한 설정 캐시.
    private var settings = MenuBarSettings.load()

    /// 팝오버를 이 버튼에 붙이기 위해 외부(AppDelegate)에 노출.
    var button: NSStatusBarButton? { statusItem.button }

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init()
    }

    /// 상태 항목·관찰자·타이머를 구성하고 첫 갱신을 수행합니다.
    /// (공유 설정을 UserDefaults 로 들여온 뒤에 호출해야 캐시가 올바릅니다.)
    func start() {
        settings = MenuBarSettings.load()

        statusItem.button?.do {
            $0.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            $0.imagePosition = .imageTrailing
            $0.target = self
            $0.action = #selector(handleClick)
        }

        // 설정이 바뀌면 캐시를 갱신하고 즉시 다시 그립니다.
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)

        // 깨어남/디스플레이 재구성 시 강제 갱신 — 메뉴 막대 항목이 이전 외관
        // (예: 다크 막대에 검은 글자)으로 남는 문제를 막습니다.
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(forceRefresh), name: NSWorkspace.didWakeNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(forceRefresh), name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(forceRefresh),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

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

    @objc private func handleClick() { onClick() }

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

    /// 깨어남·디스플레이 재구성·외관 변화 후 항목을 강제로 다시 그립니다.
    /// 변경 가드(lastTitle/lastRingKey)가 "값이 같으면 그리지 않음"이라,
    /// 외관만 바뀐 경우 글자가 이전 색(검정)으로 남는 것을 여기서 풉니다.
    /// 알림이 짧은 시간에 몰려올 수 있어(깨어남 직후 폭주) 한 사이클로 합칩니다.
    /// 주의: button.appearance 는 절대 건드리지 않음 — 세팅하면 effectiveAppearance
    /// 재계산 → KVO 재발화 → 무한 갱신 루프(CPU 100%)가 됩니다.
    @objc func forceRefresh() {
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
struct MenuBarSettings: Equatable {
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
