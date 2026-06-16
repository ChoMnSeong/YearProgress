import SwiftUI
import AppKit

/// 커스텀 색상 버튼 (무지개 원 → 시스템 색상 패널)
struct CustomColorButton: View {
    @Binding var color: Color

    var body: some View {
        Button {
            ColorPanelController.shared.show(initial: color) { color = $0 }
        } label: {
            Circle()
                .fill(AngularGradient(
                    gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]),
                    center: .center
                ))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(L.t("색상 직접 선택", "Pick a custom color"))
    }
}

/// 연속 호출을 마지막 한 번으로 모으는 디바운서.
final class Debouncer {
    static let shared = Debouncer()
    private var work: DispatchWorkItem?

    func call(after: TimeInterval = 0.3, _ block: @escaping () -> Void) {
        work?.cancel()
        let w = DispatchWorkItem(block: block)
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: w)
    }
}

/// 시스템 색상 패널(NSColorPanel)을 띄우고 선택을 콜백으로 전달.
final class ColorPanelController: NSObject {
    static let shared = ColorPanelController()
    private var onChange: ((Color) -> Void)?

    func show(initial: Color, onChange: @escaping (Color) -> Void) {
        self.onChange = onChange
        NSColorPanel.shared.do {
            $0.showsAlpha = false
            $0.color = NSColor(initial)
            $0.setTarget(self)
            $0.setAction(#selector(colorChanged(_:)))
            $0.isFloatingPanel = true
        }
        NSApp.activate(ignoringOtherApps: true)
        NSColorPanel.shared.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(Color(nsColor: sender.color))
    }
}
