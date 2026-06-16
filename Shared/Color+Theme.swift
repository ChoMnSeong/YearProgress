import SwiftUI
import AppKit

// MARK: - Color 유틸 (hex 변환·다크모드 강조·휘도)

extension Color {
    /// "#RRGGBB" → Color
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self = Color(.sRGB,
                     red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }

    /// 색을 더 어둡게 (라이트 모드 '오늘' 강조용)
    func darker(by amount: Double = 0.24) -> Color {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return self }
        return Color(.sRGB,
                     red: Double(c.redComponent) * (1 - amount),
                     green: Double(c.greenComponent) * (1 - amount),
                     blue: Double(c.blueComponent) * (1 - amount),
                     opacity: Double(c.alphaComponent))
    }

    /// 색을 더 밝게 (다크 모드 '오늘' 강조용 — 어둡게 하면 검은 배경에 묻힘)
    func lighter(by amount: Double = 0.35) -> Color {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return self }
        func up(_ v: CGFloat) -> Double { Double(v) + (1 - Double(v)) * amount }
        return Color(.sRGB,
                     red: up(c.redComponent),
                     green: up(c.greenComponent),
                     blue: up(c.blueComponent),
                     opacity: Double(c.alphaComponent))
    }

    /// 현재 모드에 맞는 '오늘' 강조색: 다크는 밝게, 라이트는 어둡게.
    func emphasized(for scheme: ColorScheme) -> Color {
        scheme == .dark ? lighter() : darker()
    }

    /// 대비 판단용 휘도(0~1).
    var luminance: Double {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return 0 }
        return 0.299 * Double(c.redComponent) + 0.587 * Double(c.greenComponent) + 0.114 * Double(c.blueComponent)
    }

    /// Color → "#RRGGBB" (extended sRGB 가 0~1 범위를 벗어날 수 있어 클램프)
    func toHexString() -> String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        func clamp(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X",
                      clamp(c.redComponent), clamp(c.greenComponent), clamp(c.blueComponent))
    }
}

// MARK: - 테마 색상 · 표시 모드

/// 사용자가 고를 수 있는 강조 색상. 앱·위젯이 공유 저장소로 선택값을 공유합니다.
enum ThemeColor: String, CaseIterable, Identifiable {
    case blue, teal, green, orange, pink, red, purple, indigo

    var id: String { rawValue }

    var hex: String {
        switch self {
        case .blue:   return "#3399F2"
        case .teal:   return "#2EB3B3"
        case .green:  return "#47B86B"
        case .orange: return "#F5992E"
        case .pink:   return "#F2669E"
        case .red:    return "#E65757"
        case .purple: return "#9966EB"
        case .indigo: return "#5766DB"
        }
    }

    var color: Color { Color(hex: hex) ?? .blue }

    var label: String {
        switch self {
        case .blue:   return "파랑"
        case .teal:   return "청록"
        case .green:  return "초록"
        case .orange: return "주황"
        case .pink:   return "분홍"
        case .red:    return "빨강"
        case .purple: return "보라"
        case .indigo: return "남색"
        }
    }

    static let storageKey = "themeColor"
    static let defaultHex = ThemeColor.blue.hex
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case dots, graph
    var id: String { rawValue }
    var label: String { self == .dots ? L.t("점", "Dots") : L.t("그래프", "Graph") }
}

enum DotGrouping: String, CaseIterable, Identifiable {
    case continuous, monthly
    var id: String { rawValue }
    var label: String { self == .continuous ? L.t("365 한눈에", "365 at once") : L.t("월별", "By month") }
}
