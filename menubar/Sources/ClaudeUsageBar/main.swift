import AppKit
import SwiftUI
import UsageBarCore

// Claude Usage Bar 메뉴 막대 앱.
//   ClaudeUsageBar --render <폴더>  화면을 상태별 그림으로 저장하고 끝난다(확인용)
//   ClaudeUsageBar --icon <폴더>    앱 아이콘을 여러 크기의 PNG 로 저장하고 끝난다(아이콘 파일 만들기용)
//   ClaudeUsageBar --session-hook   Claude Code 훅이 부르는 명령. 세션 상태 파일을 쓰고 끝난다
struct ClaudeUsageBarApp: App {
    @StateObject private var store: UsageStore = {
        let store = UsageStore()
        store.start()
        return store
    }()

    @StateObject private var sessions: SessionStore = {
        let sessions = SessionStore()
        sessions.start()
        return sessions
    }()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store, sessions: sessions)
        } label: {
            MenuBarLabel(store: store, sessions: sessions)
        }
        .menuBarExtraStyle(.window)
    }
}

let arguments = CommandLine.arguments
// 훅은 Claude Code 작업마다 불리므로, 화면 부품을 띄우기 전에 가장 먼저 처리하고 끝낸다
if arguments.contains("--session-hook") {
    SessionHook.run()
}
if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
    MainActor.assumeIsolated {
        Preview.renderAll(to: URL(fileURLWithPath: arguments[index + 1]))
    }
    exit(0)
}
if let index = arguments.firstIndex(of: "--icon"), index + 1 < arguments.count {
    MainActor.assumeIsolated {
        AppIcon.renderIconset(to: URL(fileURLWithPath: arguments[index + 1]))
    }
    exit(0)
}
// 테마 적용은 ~/.claude/claude-usage-bar-theme.json 이 있을 때만 켜진다(없으면 nil, 아무 일도 안 함)
let themeApplier = ThemeApplier.startIfConfigured()
ClaudeUsageBarApp.main()
