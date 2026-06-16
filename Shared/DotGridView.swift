import SwiftUI

/// 올해를 하루 = 점 하나로 표현하는 그리드.
/// 365개 점을 SwiftUI 도형 대신 `Canvas` 로 한 번에 그려 위젯 렌더를 가볍게 합니다.
struct DotGridView: View {
    let dayOfYear: Int
    let totalDays: Int
    let accent: Color
    var columns: Int = 19   // 0 = 자동(영역을 꽉 채우도록 열 수 계산)
    var spacing: CGFloat = 2
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let past = accent
        let today = accent.emphasized(for: scheme)
        // 다크 모드에선 어두운 배경 위라 미래 점을 조금 더 또렷하게.
        let future = accent.opacity(scheme == .dark ? 0.30 : 0.16)

        Canvas(opaque: false) { ctx, size in
            let cols = columns > 0 ? columns
                : Self.bestColumns(count: totalDays, size: size, spacing: spacing)
            let rows = max(Int(ceil(Double(totalDays) / Double(cols))), 1)
            let dotW = (size.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            let dotH = (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let dot = max(min(dotW, dotH), 1)
            let radius = dot * 0.28
            let corner = CGSize(width: radius, height: radius)

            // 그리드를 가운데 정렬해 남는 여백을 양쪽으로 분산
            let gridW = CGFloat(cols) * dot + CGFloat(cols - 1) * spacing
            let gridH = CGFloat(rows) * dot + CGFloat(rows - 1) * spacing
            let ox = max((size.width - gridW) / 2, 0)
            let oy = max((size.height - gridH) / 2, 0)

            // 점 365개를 색깔별 Path 3개로 모아 fill 3번에 끝냅니다(개별 fill 365번 대비 큰 절감).
            var pastPath = Path(), todayPath = Path(), futurePath = Path()
            for i in 0..<totalDays {
                let row = i / cols
                let col = i % cols
                let x = ox + CGFloat(col) * (dot + spacing)
                let y = oy + CGFloat(row) * (dot + spacing)
                let rect = CGRect(x: x, y: y, width: dot, height: dot)
                let day = i + 1
                if day == dayOfYear { todayPath.addRoundedRect(in: rect, cornerSize: corner) }
                else if day < dayOfYear { pastPath.addRoundedRect(in: rect, cornerSize: corner) }
                else { futurePath.addRoundedRect(in: rect, cornerSize: corner) }
            }
            ctx.fill(pastPath, with: .color(past))
            ctx.fill(futurePath, with: .color(future))
            ctx.fill(todayPath, with: .color(today))
        }
    }

    /// 영역을 가장 꽉 채우는(=점이 가장 커지는) 열 수를 찾습니다.
    static func bestColumns(count: Int, size: CGSize, spacing: CGFloat) -> Int {
        guard count > 0, size.width > 0, size.height > 0 else { return max(count, 1) }
        var best = 1
        var bestDot: CGFloat = 0
        for c in 1...count {
            let rows = Int(ceil(Double(count) / Double(c)))
            let dw = (size.width - spacing * CGFloat(c - 1)) / CGFloat(c)
            let dh = (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let dot = min(dw, dh)
            if dot > bestDot { bestDot = dot; best = c }
        }
        return best
    }
}
