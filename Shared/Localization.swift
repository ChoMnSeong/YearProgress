import Foundation

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
