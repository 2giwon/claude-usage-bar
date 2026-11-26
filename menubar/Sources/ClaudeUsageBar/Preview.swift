import AppKit
import SwiftUI
import UsageBarCore

// 확인용: 상태별 펼침 화면과 메뉴 막대 아이콘을 PNG 로 저장한다
@MainActor
enum Preview {
    static func renderAll(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = ISO8601DateFormatter().date(from: "2026-11-26T00:16:00Z")!

        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            for (name, store) in samples(now: now) {
                save(PopoverView(store: store), scheme: scheme, to: folder.appendingPathComponent("popover-\(name)-\(suffix).png"))
                save(MenuBarLabel(store: store).padding(6), scheme: scheme, to: folder.appendingPathComponent("menubar-\(name)-\(suffix).png"))
            }
        }
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
