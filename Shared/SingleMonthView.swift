import SwiftUI

/// 한 달만 크게 보여주는 확대 달력(날짜 숫자 표시). 공간을 채우도록 스케일됩니다.
/// (부모가 높이를 정해줘야 함)
struct SingleMonthView: View {
    let month: Int
    let year: Int
    let today: Date
    let accent: Color
    var spacing: CGFloat = 4
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lengths = YearMath.monthLengths(year: year)
        let days = lengths[month - 1]
        let cols = 7
        let offset = YearMath.weekdayOffset(year: year, month: month)   // 1일의 요일 칸
        let rows = Int(ceil(Double(offset + days) / Double(cols)))
        let tc = Calendar.current.dateComponents([.year, .month, .day], from: today)
        // 채워진 칸 글자색: 강조색이 밝으면 검정, 어두우면 흰색 (흰색 고정이면 밝은 색에서 안 보임)
        let filledText: Color = accent.luminance > 0.62 ? Color.black.opacity(0.82) : .white

        GeometryReader { geo in
            // 셀이 영역(가로·세로)을 꽉 채우도록 직사각형으로 배치.
            let cellW = (geo.size.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            let cellH = (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)

            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: spacing) {
                        ForEach(0..<cols, id: \.self) { c in
                            let d = r * cols + c - offset + 1   // 요일 정렬
                            if d >= 1 && d <= days {
                                dayCell(day: d, tc: tc, w: cellW, h: cellH, filledText: filledText)
                            } else {
                                Color.clear.frame(width: cellW, height: cellH)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(day: Int, tc: DateComponents, w: CGFloat, h: CGFloat, filledText: Color) -> some View {
        let isToday = (year == tc.year && month == tc.month && day == tc.day)
        let filled = (year != tc.year!) ? (year < tc.year!)
            : (month != tc.month!) ? (month < tc.month!)
            : (day <= tc.day!)
        let s = min(w, h)
        ZStack {
            RoundedRectangle(cornerRadius: s * 0.28, style: .continuous)
                .fill(filled ? accent : accent.opacity(scheme == .dark ? 0.26 : 0.15))
                // 오늘 강조: 다크는 밝게, 라이트는 어둡게 (어둡게 고정이면 검은 배경에 묻힘)
                .brightness(isToday ? (scheme == .dark ? 0.18 : -0.24) : 0)
            Text("\(day)")
                .font(.system(size: s * 0.46, weight: isToday ? .bold : .medium, design: .rounded))
                .minimumScaleFactor(0.5)
                .foregroundStyle(filled ? filledText : accent.opacity(0.85))
        }
        .frame(width: w, height: h)
    }
}
