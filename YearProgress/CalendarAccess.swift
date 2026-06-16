import SwiftUI
import EventKit

/// UI 가 쓰는 이벤트 정보만 담은 가벼운 Sendable 값.
/// (EKEvent 는 Sendable 이 아니고 UI 엔 id·제목·날짜만 필요해 분리)
struct EventOption: Identifiable, Hashable {
    let id: String
    let title: String
    let date: Date
}

/// 애플 캘린더(EventKit) 접근 + 다가오는 이벤트 로딩. 전부 async/await.
@MainActor
final class CalendarAccess: ObservableObject {
    @Published var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var events: [EventOption] = []
    private let store = EKEventStore()

    var authorized: Bool { status == .fullAccess }

    /// 권한 요청(없으면 시스템 다이얼로그) 후 이벤트를 불러옵니다.
    func requestAndLoad() {
        Task { await requestAccessAndReload() }
    }

    func requestAccessAndReload() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            status = EKEventStore.authorizationStatus(for: .event)
            if granted { await loadUpcoming() }
        } catch {
            status = EKEventStore.authorizationStatus(for: .event)
        }
    }

    /// 다가오는 2년치 이벤트를 백그라운드에서 조회·중복 제거해 가져옵니다.
    func loadUpcoming() async {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let store = self.store
        // 무거운 store 조회는 메인 밖에서. 결과(Sendable EventOption)만 메인으로 돌아옵니다.
        let loaded = await Task.detached(priority: .userInitiated) { () -> [EventOption] in
            let now = Date()
            let cal = Calendar.current
            let end = cal.date(byAdding: .year, value: 2, to: now) ?? now
            let pred = store.predicateForEvents(withStart: now, end: end, calendars: nil)
            var seen = Set<String>()
            return store.events(matching: pred)
                .sorted { $0.startDate < $1.startDate }
                // 여러 계정에 같은 공휴일이 중복되므로 제목+날짜 기준으로 하나만 남깁니다.
                .compactMap { ev -> EventOption? in
                    let title = (ev.title ?? "").trimmingCharacters(in: .whitespaces)
                    let day = Int(cal.startOfDay(for: ev.startDate).timeIntervalSince1970)
                    let key = "\(title)|\(day)"
                    guard seen.insert(key).inserted else { return nil }
                    return EventOption(id: ev.eventIdentifier ?? key,
                                       title: ev.title ?? L.t("이벤트", "Event"),
                                       date: ev.startDate)
                }
                .prefix(60)
                .map { $0 }
        }.value
        events = loaded
    }
}
