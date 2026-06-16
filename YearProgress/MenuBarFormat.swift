import Foundation

/// 메뉴 막대·앱 창에서 쓰는 날짜/진행률 문자열 포맷.
enum MenuBarFormat {
    // 앱 창·메뉴 막대 공용: 초까지 (24시간제). 메뉴 막대 폭은 고정돼 있어 매초 갱신해도 재배치 안 됨.
    private static let dateTimeFormatter = DateFormatter().then {
        $0.locale = L.locale
        $0.setLocalizedDateFormatFromTemplate("EEE MMM d HH:mm:ss")
    }

    private static let dateOnlyFormatter = DateFormatter().then {
        $0.locale = L.locale
        $0.setLocalizedDateFormatFromTemplate("EEE MMM d")
    }

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
