import AppKit
import SwiftUI
import UsageBarCore

// Claude Usage Bar 메뉴 막대 앱.
//   ClaudeUsageBar --render <폴더>  화면을 상태별 그림으로 저장하고 끝난다(확인용)
//   ClaudeUsageBar --icon <폴더>    앱 아이콘을 여러 크기의 PNG 로 저장하고 끝난다(아이콘 파일 만들기용)
struct ClaudeUsageBarApp: App {
    @StateObject private var store: UsageStore = {
        let store = UsageStore()
        store.start()
        return store
    }()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

let arguments = CommandLine.arguments
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
