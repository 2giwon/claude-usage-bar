import AppKit
import SwiftUI
import UsageBarCore

// 확인용: 상태별 펼침 화면과 메뉴 막대 아이콘을 한국어(ko), 영어(en)로 PNG 저장한다
@MainActor
enum Preview {
    static func renderAll(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = ISO8601DateFormatter().date(from: "2026-11-26T00:16:00Z")!
        let original = Words.strings

        for (code, lang) in [("ko", Language.korean), ("en", Language.english)] {
            Words.strings = Strings(lang)
            for scheme in [ColorScheme.light, .dark] {
                let suffix = "\(code)-\(scheme == .dark ? "dark" : "light")"
                let hidden = SessionStore(load: .hidden, now: now)
                for (name, store) in samples(now: now) {
                    save(PopoverView(store: store, sessions: hidden), scheme: scheme, to: folder.appendingPathComponent("popover-\(name)-\(suffix).png"))
                    save(MenuBarLabel(store: store, sessions: hidden).padding(6), scheme: scheme, to: folder.appendingPathComponent("menubar-\(name)-\(suffix).png"))
                }
                let usage = samples(now: now)[0].1
                for (name, sessions) in sessionSamples(now: now) {
                    save(PopoverView(store: usage, sessions: sessions), scheme: scheme,
                         to: folder.appendingPathComponent("popover-sessions-\(name)-\(suffix).png"))
                    save(MenuBarLabel(store: usage, sessions: sessions).padding(6), scheme: scheme,
                         to: folder.appendingPathComponent("menubar-sessions-\(name)-\(suffix).png"))
                }
            }
        }
        Words.strings = original
        print("rendered to \(folder.path)")
    }

    static func samples(now: Date) -> [(String, UsageStore)] {
        func snapshot(five: Double, week: Double, updated: Date) -> Snapshot {
            Snapshot(
                version: 1,
                updatedAt: updated,
                status: "ready",
                limits: [
                    Limit(kind: "five_hour", percentUsed: five, resetsAt: now.addingTimeInterval(4 * 3600 + 33 * 60)),
                    Limit(kind: "seven_day", percentUsed: week, resetsAt: now.addingTimeInterval(3 * 86400 + 6 * 3600)),
                ],
                context: Context(percent: 20, tokens: 198_228, window: 1_000_000),
                session: "claude-usage-bar"
            )
        }
        let fresh = now.addingTimeInterval(-120)
        return [
            ("normal", UsageStore(load: .loaded(snapshot(five: 8, week: 41, updated: fresh)), now: now)),
            ("warning", UsageStore(load: .loaded(snapshot(five: 85, week: 72, updated: fresh)), now: now)),
            ("stale", UsageStore(load: .loaded(snapshot(five: 8, week: 41, updated: now.addingTimeInterval(-35 * 60))), now: now)),
            ("missing", UsageStore(load: .missing, now: now)),
            ("failed", UsageStore(load: .failed, now: now)),
        ]
    }

    static func sessionSamples(now: Date) -> [(String, SessionStore)] {
        func row(_ id: String, _ title: String, _ kind: BoardKind, _ detail: String?, minutes: Double,
                 missing: Bool = false) -> BoardRow {
            BoardRow(localId: "local_\(id)", title: title, isTitleMissing: missing, kind: kind, detail: detail,
                     since: now.addingTimeInterval(-minutes * 60), link: missing ? nil : sessionLink("local_\(id)"))
        }
        let rows = [
            row("a", "주식 종목 분석", .waiting, "매수 기준을 정해 주세요", minutes: 12),
            row("b", "랩매니저 프론트", .working, nil, minutes: 3),
            row("c", "작업노트 작업", .review, "버스 도착 예측값 차이 확인", minutes: 8),
            row("d", "Android위클리", .done, "#754 글 배포 완료", minutes: 95),
            row("e", "claude-usage-bar", .working, nil, minutes: 0, missing: true),
        ]
        return [
            ("list", SessionStore(load: .loaded(rows), now: now)),
            ("loading", SessionStore(load: .loading, now: now)),
            ("empty", SessionStore(load: .loaded([]), now: now)),
            ("failed", SessionStore(load: .failed, now: now)),
        ]
    }

    static func save<V: View>(_ view: V, scheme: ColorScheme, to url: URL) {
        let content = view
            .environment(\.colorScheme, scheme)
            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.97))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}
