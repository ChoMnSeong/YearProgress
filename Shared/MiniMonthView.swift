import SwiftUI

/// 한 달을 7열 작은 점 격자로 표현 (개요용 미니 / 확대용 모두 dotSize 로 크기 조절)
struct MiniMonthView: View {
    let month: Int
    let year: Int
    let today: Date
    let accent: Color
    var dotSize: CGFloat = 4
    var showsLabel: Bool = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lengths = YearMath.monthLengths(year: year)
        let days = lengths[month - 1]
        let tc = Calendar.current.dateComponents([.year, .month, .day], from: today)
        let cols = 7
        let offset = YearMath.weekdayOffset(year: year, month: month)   // 1일의 요일 칸
        let rows = Int(ceil(Double(offset + days) / Double(cols)))
        let gap = max(dotSize * 0.22, 1)
        let labelFontSize = max(dotSize * 1.4, 7)
        let labelH = showsLabel ? labelFontSize + gap : 0

        let past = accent
        let todayColor = accent.emphasized(for: scheme)
        let future = accent.opacity(scheme == .dark ? 0.32 : 0.18)
        let labelText = Text(YearMath.monthShort(month))
            .font(.system(size: labelFontSize, weight: .semibold))
            .foregroundStyle(.secondary)

        let width = CGFloat(cols) * (dotSize + gap) - gap
        let height = labelH + CGFloat(rows) * (dotSize + gap) - gap

        Canvas(opaque: false) { ctx, _ in
            if showsLabel {
                ctx.draw(ctx.resolve(labelText), at: CGPoint(x: 0, y: 0), anchor: .topLeading)
            }
            let r = dotSize * 0.3
            let corner = CGSize(width: r, height: r)
            // 색깔별 Path 로 모아 fill 3번에 그립니다.
            var pastPath = Path(), todayPath = Path(), futurePath = Path()
            for i in 0..<days {
                let gridIndex = offset + i   // 요일 위치만큼 밀어서 배치
                let row = gridIndex / cols
                let col = gridIndex % cols
                let x = CGFloat(col) * (dotSize + gap)
                let y = labelH + CGFloat(row) * (dotSize + gap)
                let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                let d = i + 1
                let isToday = (year == tc.year && month == tc.month && d == tc.day)
                let filled = (year != tc.year!) ? (year < tc.year!)
                    : (month != tc.month!) ? (month < tc.month!)
                    : (d <= tc.day!)
                if isToday { todayPath.addRoundedRect(in: rect, cornerSize: corner) }
                else if filled { pastPath.addRoundedRect(in: rect, cornerSize: corner) }
                else { futurePath.addRoundedRect(in: rect, cornerSize: corner) }
            }
            ctx.fill(pastPath, with: .color(past))
            ctx.fill(futurePath, with: .color(future))
            ctx.fill(todayPath, with: .color(todayColor))
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}
