import SwiftUI

/// 진행률을 원형 그래프로 표시 (가운데 퍼센트, 오른쪽에 % 기호).
struct RingGraphView: View {
    let fraction: Double
    let accent: Color
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [accent.opacity(0.55), accent]), center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(format: "%.2f", fraction * 100))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .padding(lineWidth + 6)
        }
    }
}
