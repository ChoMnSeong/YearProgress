import SwiftUI

struct ContentView: View {
    @AppStorage(ThemeColor.storageKey)
    private var themeHex = ThemeColor.defaultHex
    @AppStorage(AppSettings.periodKey)
    private var periodRaw = Period.year.rawValue
    @AppStorage(AppSettings.birthDateKey)
    private var birthDateStr = ""
    @AppStorage(AppSettings.lifeExpectancyKey)
    private var lifeExpStr = "80"

    private var accent: Color { Color(hex: themeHex) ?? .blue }
    private var period: Period { Period(rawValue: periodRaw) ?? .year }
    private var birthDate: Date? { birthDateStr.isEmpty ? nil : AppSettings.birthFormatter.date(from: birthDateStr) }
    private var lifeExpectancy: Int { Int(lifeExpStr) ?? 80 }

    var body: some View {
        // 1초마다 화면을 갱신하여 시계와 진행률이 살아있도록 합니다.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            YearProgressScreen(date: context.date,
                               progress: PeriodProgress.current(period: period, date: context.date,
                                                                birthDate: birthDate, lifeExpectancy: lifeExpectancy),
                               accent: accent)
        }
    }
}

private struct YearProgressScreen: View {
    let date: Date
    let progress: PeriodProgress
    let accent: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), accent.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 4) {
                    Text(progress.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(MenuBarFormat.dateTime(date: date))
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .monospacedDigit()
                }

                ProgressRing(fraction: progress.fraction, accent: accent)
                    .frame(width: 240, height: 240)

                Text(progress.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                MonthBar(fraction: progress.fraction, accent: accent)
                    .frame(height: 14)
                    .padding(.horizontal, 32)
            }
            .padding()
        }
    }
}

/// 가운데에 퍼센트를 표시하는 원형 진행률 링
private struct ProgressRing: View {
    let fraction: Double
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.15), lineWidth: 22)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [accent.opacity(0.6), accent]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 22, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: fraction)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(format: "%.2f", fraction * 100))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                Text("%")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
        }
    }
}

/// 진행률만큼 채워지는 가로 막대
private struct MonthBar: View {
    let fraction: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(accent.opacity(0.15))
                Capsule()
                    .fill(accent)
                    .frame(width: geo.size.width * fraction)
                    .animation(.easeInOut, value: fraction)
            }
        }
    }
}

#Preview {
    ContentView()
}
