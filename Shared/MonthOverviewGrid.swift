import SwiftUI

/// 12개월을 cols × rows 미니 달력으로 보여주는 개요. (위젯 비율에 맞춰 열/행 조정)
/// 각 칸은 `cell` 클로저로 감싸 탭/인텐트를 붙입니다.
struct MonthOverviewGrid<Cell: View>: View {
    let months: [MonthRef]   // 표시할 (연,월) 목록 (보통 12개)
    let today: Date
    let accent: Color
    var cols: Int = 3
    var rows: Int = 4
    var spacing: CGFloat = 6
    @ViewBuilder let cell: (Int, MiniMonthView) -> Cell   // (위치 1-based, mini)

    var body: some View {
        GeometryReader { geo in
            let cellW = (geo.size.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            let cellH = (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let dot = max(min(cellW / 7.4, cellH / 8.6), 1)

            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: spacing) {
                        ForEach(0..<cols, id: \.self) { c in
                            let idx = r * cols + c
                            if idx < months.count {
                                let mr = months[idx]
                                cell(idx + 1, MiniMonthView(month: mr.month, year: mr.year,
                                                            today: today, accent: accent, dotSize: dot))
                                    .frame(width: cellW, height: cellH, alignment: .top)
                            } else {
                                Color.clear.frame(width: cellW, height: cellH)
                            }
                        }
                    }
                }
            }
        }
    }
}
