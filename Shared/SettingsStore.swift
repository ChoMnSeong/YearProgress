import SwiftUI

/// 앱(비샌드박스)과 위젯(샌드박스)이 설정을 공유하는 저장소.
/// 무료 계정에선 App Group 을 못 쓰므로, **위젯 컨테이너 안의 JSON 파일**로 공유합니다.
/// - 위젯: 자기 컨테이너(NSHomeDirectory) 에서 직접 읽고 씀
/// - 앱(비샌드박스): 위젯 컨테이너 경로를 직접 구성해 같은 파일을 읽고 씀
enum SharedStore {
    static let widgetBundleID = "com.ensnif.YearProgress.YearProgressWidget"

    /// 앱의 디스크 쓰기를 메인 스레드 밖에서, 그러나 **제출 순서대로(FIFO)** 처리하는 직렬 큐.
    private static let ioQueue = DispatchQueue(label: "com.ensnif.YearProgress.store", qos: .utility)

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

    /// 앱 전용: read-modify-write 를 직렬 큐(오프메인)에서 수행하고,
    /// 끝나면 메인에서 `completion` 을 호출합니다. (UI 탭이 디스크에 막히지 않게)
    /// 직렬 큐라 여러 번 호출돼도 제출 순서대로 처리됩니다.
    static func merge(_ updates: [String: String], completion: @escaping () -> Void = {}) {
        ioQueue.async {
            var d = read()
            for (k, v) in updates { d[k] = v }
            write(d)
            DispatchQueue.main.async(execute: completion)
        }
    }
}

// MARK: - 설정 키 · 포매터 · 스냅샷

enum AppSettings {
    static let displayModeKey = "displayMode"
    static let dotGroupingKey = "dotGrouping"
    static let selectedMonthKey = "selectedMonth"   // 0 = 개요, 1...12 = 확대된 달
    static let periodKey = "period"
    static let birthDateKey = "birthDate"           // "yyyy-MM-dd"
    static let lifeExpectancyKey = "lifeExpectancy" // 정수 문자열
    static let eventTitleKey = "eventTitle"
    static let eventDateKey = "eventDate"           // "yyyy-MM-dd"

    static let birthFormatter = DateFormatter().then {
        $0.locale = Locale(identifier: "en_US_POSIX")
        $0.dateFormat = "yyyy-MM-dd"
    }

    /// 이벤트 상세("D-N · 토 6월 6일")용 — 매초 호출되는 경로라 캐싱 필수.
    static let eventDetailFormatter = DateFormatter().then {
        $0.locale = L.locale
        $0.setLocalizedDateFormatFromTemplate("EEE MMM d")
    }

    /// 모든 설정을 공유 파일에서 **한 번만** 읽어 담는 스냅샷.
    struct Snapshot {
        let accent: Color
        let mode: DisplayMode
        let grouping: DotGrouping
        let selectedMonth: Int
        let period: Period
        let birthDate: Date?
        let lifeExpectancy: Int
        let eventTitle: String?
        let eventDate: Date?
    }

    static func snapshot() -> Snapshot {
        let d = SharedStore.read()
        let birth = (d[birthDateKey]).flatMap { $0.isEmpty ? nil : birthFormatter.date(from: $0) }
        let evDate = (d[eventDateKey]).flatMap { $0.isEmpty ? nil : birthFormatter.date(from: $0) }
        let evTitle = (d[eventTitleKey]).flatMap { $0.isEmpty ? nil : $0 }
        return Snapshot(
            accent: Color(hex: d[ThemeColor.storageKey] ?? "") ?? ThemeColor.blue.color,
            mode: DisplayMode(rawValue: d[displayModeKey] ?? "") ?? .dots,
            grouping: DotGrouping(rawValue: d[dotGroupingKey] ?? "") ?? .continuous,
            selectedMonth: Int(d[selectedMonthKey] ?? "") ?? 0,
            period: Period(rawValue: d[periodKey] ?? "") ?? .year,
            birthDate: birth,
            lifeExpectancy: Int(d[lifeExpectancyKey] ?? "") ?? 80,
            eventTitle: evTitle,
            eventDate: evDate
        )
    }

    /// 앱이 현재 설정을 위젯과 공유하기 위해 한 번에 기록 (selectedMonth 는 개요로 초기화).
    /// 디스크 쓰기는 오프메인(직렬 큐)에서 일어나고, 끝나면 `completion` 이 메인에서 호출됩니다.
    static func push(theme: String, displayMode: String, dotGrouping: String,
                     period: String, birthDate: String, lifeExpectancy: String,
                     eventTitle: String, eventDate: String,
                     completion: @escaping () -> Void = {}) {
        SharedStore.merge([
            ThemeColor.storageKey: theme,
            displayModeKey: displayMode,
            dotGroupingKey: dotGrouping,
            periodKey: period,
            birthDateKey: birthDate,
            lifeExpectancyKey: lifeExpectancy,
            eventTitleKey: eventTitle,
            eventDateKey: eventDate,
            selectedMonthKey: "0"
        ], completion: completion)
    }
}
