import SwiftUI

@main
struct YearProgressApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 메뉴 막대 전용 앱이라 자동으로 열리는 창이 없는 Settings 씬만 둡니다.
        Settings { EmptyView() }
    }
}
