import Foundation
import UsageBarCore

// ClaudeUsageBar --session-hook
// Claude Code 훅이 부르는 명령. 표준 입력의 훅 JSON 을 읽어 ~/.claude/session-board/<세션 번호>.json 을 쓰거나 지운다.
// 훅이 실패해도 Claude Code 작업을 막지 않도록, 무슨 일이 있어도 종료 코드 0 으로 끝낸다
enum SessionHook {
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/session-board")
    }

    static func run() -> Never {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let input = decodeHookInput(data) else { exit(0) }

        let target = folder.appendingPathComponent("\(input.sessionId).json")
        switch hookAction(input) {
        case .ignore:
            break
        case .remove:
            try? FileManager.default.removeItem(at: target)
        case let .set(state):
            // 도구 호출 전이면 하는 일(읽기, 고치기, 실행 등)도 남긴다
            let activity = state == .working && input.event == "PreToolUse" ? activityFor(tool: input.toolName) : nil
            write(SessionStatus(sessionId: input.sessionId, state: state, cwd: input.cwd,
                                transcriptPath: input.transcriptPath, updatedAt: Date(), activity: activity), to: target)
        }
        exit(0)
    }

    // 여러 세션이 동시에 써도 섞이지 않게, 임시 파일에 쓴 뒤 rename 으로 한 번에 바꿔치기한다.
    // 임시 파일은 .tmp 로 끝나서 메뉴 막대 앱이 읽지 않는다
    private static func write(_ status: SessionStatus, to target: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let temp = folder.appendingPathComponent("\(status.sessionId).json.\(getpid()).tmp")
        guard (try? encodeSessionStatus(status).write(to: temp)) != nil else { return }
        if rename(temp.path, target.path) != 0 {
            try? FileManager.default.removeItem(at: temp)
        }
    }
}
