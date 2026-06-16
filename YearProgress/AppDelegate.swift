import SwiftUI
import AppKit
import WidgetKit

/// 앱 생명주기 + 팝오버/창 소유. 메뉴 막대 항목 자체는 MenuBarController 가 전담합니다.
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var menuBar: MenuBarController!
    private let popover = NSPopover()
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 아이콘 숨김 + Command-Tab 전환기에서 제외 (메뉴 막대 전용)
        NSApp.setActivationPolicy(.accessory)

        // 저장된 설정을 공유 파일에서 불러와 앱 UI(표준 defaults)에 반영. (파일을 덮어쓰지 않음)
        // MenuBarController 의 설정 캐시가 이 값들을 읽으므로 컨트롤러 생성 전에 합니다.
        importSharedSettings()
        WidgetCenter.shared.reloadAllTimelines()

        // 팝오버 내용 뷰는 '열 때' 만들고 닫히면 버립니다(popoverDidClose).
        // 미리 만들어 두면 닫힌 뒤에도 SwiftUI TimelineView 가 매초 전체 UI 를
        // 재렌더해 CPU 를 계속 점유하는 문제가 있었습니다.
        popover.do {
            $0.behavior = .transient
            $0.contentSize = NSSize(width: 260, height: 660)
            $0.delegate = self
        }

        menuBar = MenuBarController { [weak self] in self?.togglePopover() }
        menuBar.start()
    }

    /// 공유 파일의 설정을 표준 UserDefaults 로 들여옵니다(@AppStorage 가 읽도록).
    private func importSharedSettings() {
        let s = SharedStore.read()
        let std = UserDefaults.standard
        let keys = [
            ThemeColor.storageKey, AppSettings.displayModeKey, AppSettings.dotGroupingKey,
            AppSettings.periodKey, AppSettings.birthDateKey, AppSettings.lifeExpectancyKey,
            AppSettings.eventTitleKey, AppSettings.eventDateKey
        ]
        for key in keys {
            if let v = s[key] { std.set(v, forKey: key) }
        }
    }

    private func togglePopover() {
        guard let button = menuBar.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.contentViewController = NSHostingController(
                rootView: PopoverContent(
                    onOpenWindow: { [weak self] in self?.showMainWindow() },
                    onQuit: { NSApp.terminate(nil) }
                )
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// 닫힌 팝오버의 SwiftUI 가 백그라운드에서 계속 틱하지 않도록 내용을 버립니다.
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    private func showMainWindow() {
        if mainWindow == nil {
            let hosting = NSHostingController(rootView: ContentView())
            let window = NSWindow(contentViewController: hosting).then {
                $0.title = L.t("올해 진행률", "Year Progress")
                $0.styleMask = [.titled, .closable, .miniaturizable]
                $0.isReleasedWhenClosed = false
                $0.setContentSize(NSSize(width: 360, height: 520))
                $0.center()
            }
            mainWindow = window
            // 창을 닫으면 해제 — 닫힌 창의 1초 TimelineView 가 계속 돌지 않도록.
            NotificationCenter.default.addObserver(self, selector: #selector(mainWindowClosed(_:)),
                                                   name: NSWindow.willCloseNotification, object: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func mainWindowClosed(_ note: Notification) {
        guard let w = note.object as? NSWindow, w === mainWindow else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: w)
        mainWindow = nil
    }
}
