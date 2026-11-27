import Foundation

// 세션 현황판: Claude 데스크탑 앱(Code 탭)에서 돌고 있는 세션이 지금 무엇을 하는지 보여 준다.
//
// 1. Claude Code 훅이 `ClaudeUsageBar --session-hook` 을 부르면, 훅 입력(JSON)을 읽어
//    ~/.claude/session-board/<CLI 세션 번호>.json 에 상태(일하는 중, 답 기다림, 쉬는 중)를 쓴다.
// 2. 메뉴 막대 앱이 상태 파일과 데스크탑 앱의 세션 파일
//    (~/Library/Application Support/Claude/claude-code-sessions/<계정>/<조직>/local_*.json)을 이어서 목록을 만든다.
// 3. 목록 줄을 누르면 claude://code/continue?session=local_<번호> 로 그 세션을 연다.
//
// 데스크탑 앱의 세션 파일과 링크 형식은 공식 문서에 없는 앱 내부 형식이다(2026-11-27, 앱 7.37095.0 에서 확인).
// 앱이 업데이트되면 바뀔 수 있어서, 못 읽는 칸이 있어도 목록이 사라지지 않게 만든다.

public enum SessionState: String, Equatable {
    case working  // 일하는 중
    case waiting  // 답 기다림 (질문 카드, 권한 요청)
    case idle     // 쉬는 중 (응답이 끝남)
}

// ===== 1. 훅 입력 =====

public struct HookInput: Equatable {
    public var sessionId: String
    public var event: String
    public var cwd: String?
    public var transcriptPath: String?
    public var notificationType: String?
    public var toolName: String?

    public init(sessionId: String, event: String, cwd: String?, transcriptPath: String?,
                notificationType: String?, toolName: String?) {
        self.sessionId = sessionId
        self.event = event
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.notificationType = notificationType
        self.toolName = toolName
    }
}

private struct RawHookInput: Decodable {
    var session_id: String?
    var hook_event_name: String?
    var cwd: String?
    var transcript_path: String?
    var notification_type: String?
    var tool_name: String?
}

// 세션 번호는 상태 파일 이름이 되므로 영문, 숫자, -, _ 만 받는다("../" 같은 값으로 다른 곳에 쓰지 않게)
private func isSafeFileName(_ text: String) -> Bool {
    !text.isEmpty && text.count <= 128
        && text.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" || $0 == "_" }
}

// 훅이 표준 입력으로 주는 JSON 을 읽는다. 깨졌거나 세션 번호가 없거나 파일 이름으로 못 쓰면 nil
public func decodeHookInput(_ data: Data) -> HookInput? {
    guard let raw = try? JSONDecoder().decode(RawHookInput.self, from: data),
          let sessionId = raw.session_id, isSafeFileName(sessionId),
          let event = raw.hook_event_name
    else {
        return nil
    }
    return HookInput(sessionId: sessionId, event: event, cwd: raw.cwd, transcriptPath: raw.transcript_path,
                     notificationType: raw.notification_type, toolName: raw.tool_name)
}

public enum HookAction: Equatable {
    case set(SessionState)
    case remove
    case ignore
}

// 어떤 훅이 오면 상태를 어떻게 바꾸는지
//   UserPromptSubmit -> 일하는 중
//   PreToolUse(AskUserQuestion) -> 답 기다림, PreToolUse(다른 도구) -> 일하는 중
//   PostToolUse(AskUserQuestion) -> 일하는 중
//   Notification(권한 요청, 입력 요청) -> 답 기다림
//   Stop -> 쉬는 중, SessionEnd -> 상태 파일 지우기
// SessionStart 는 쓰지 않는다. 대화 압축(compact) 때도 와서, 일하는 도중에 쉬는 중으로 바뀌어 보이기 때문이다
public func hookAction(_ input: HookInput) -> HookAction {
    switch input.event {
    case "UserPromptSubmit":
        return .set(.working)
    case "PreToolUse":
        // 다른 도구 호출 전은 일하는 중(하는 일은 activityFor 로 따로 기록). 권한을 허락한 뒤 다음 도구 때 확실히 돌아온다
        return input.toolName == "AskUserQuestion" ? .set(.waiting) : .set(.working)
    case "PostToolUse":
        return input.toolName == "AskUserQuestion" ? .set(.working) : .ignore
    case "Notification":
        return ["permission_prompt", "elicitation_dialog"].contains(input.notificationType ?? "")
            ? .set(.waiting) : .ignore
    case "Stop":
        return .set(.idle)
    case "SessionEnd":
        return .remove
    default:
        return .ignore
    }
}

// ===== 상태 파일 =====

public struct SessionStatus: Equatable {
    public var sessionId: String
    public var state: SessionState
    public var cwd: String?
    public var transcriptPath: String?
    public var updatedAt: Date
    public var activity: String?  // 일하는 중일 때 하는 일(reading, editing, running 등). activityFor(tool:) 참고

    public init(sessionId: String, state: SessionState, cwd: String?, transcriptPath: String?, updatedAt: Date,
                activity: String? = nil) {
        self.sessionId = sessionId
        self.state = state
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.updatedAt = updatedAt
        self.activity = activity
    }
}

private struct RawSessionStatus: Codable {
    var version: Int
    var sessionId: String
    var state: String
    var cwd: String?
    var transcriptPath: String?
    var updatedAt: String
    var activity: String?
}

public func encodeSessionStatus(_ status: SessionStatus) -> Data {
    let raw = RawSessionStatus(version: 1, sessionId: status.sessionId, state: status.state.rawValue,
                               cwd: status.cwd, transcriptPath: status.transcriptPath,
                               updatedAt: formatDate(status.updatedAt), activity: status.activity)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(raw)) ?? Data()
}

public func decodeSessionStatus(_ data: Data) -> SessionStatus? {
    guard let raw = try? JSONDecoder().decode(RawSessionStatus.self, from: data),
          let state = SessionState(rawValue: raw.state),
          let updatedAt = parseDate(raw.updatedAt)
    else {
        return nil
    }
    return SessionStatus(sessionId: raw.sessionId, state: state, cwd: raw.cwd,
                         transcriptPath: raw.transcriptPath, updatedAt: updatedAt, activity: raw.activity)
}

public enum StatusFolder: Equatable {
    case missing                   // 상태 폴더가 없음: 훅을 설치하지 않은 것으로 보고 세션 카드를 숨긴다
    case unreadable                // 폴더는 있는데 목록을 못 읽음(권한 등): 실패로 알린다
    case statuses([SessionStatus])
}

// 상태 폴더의 *.json 을 모두 읽는다. 깨진 파일과 쓰는 도중의 임시 파일(.tmp)은 건너뛴다
public func readStatusFolder(_ root: URL) -> StatusFolder {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return .missing
    }
    guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
        return .unreadable
    }
    let statuses = files
        .filter { $0.pathExtension == "json" }
        .compactMap { (try? Data(contentsOf: $0)).flatMap(decodeSessionStatus) }
        .sorted { $0.sessionId < $1.sessionId }
    return .statuses(statuses)
}

// ===== 2. 데스크탑 앱 세션 파일 =====

public struct AppSession: Equatable {
    public var localId: String
    public var cliIds: [String]
    public var title: String?
    public var cwd: String?
    public var isArchived: Bool
    public var summaryCategory: String?
    public var summaryDetail: String?
    public var isSummaryCurrent: Bool

    public init(localId: String, cliIds: [String], title: String?, cwd: String?, isArchived: Bool,
                summaryCategory: String?, summaryDetail: String?, isSummaryCurrent: Bool) {
        self.localId = localId
        self.cliIds = cliIds
        self.title = title
        self.cwd = cwd
        self.isArchived = isArchived
        self.summaryCategory = summaryCategory
        self.summaryDetail = summaryDetail
        self.isSummaryCurrent = isSummaryCurrent
    }
}

// 세션 파일에는 칸이 아주 많다. 쓰는 칸만 고르고 나머지는 무시한다(모르는 칸이 늘어도 읽힌다)
private struct RawAppSession: Decodable {
    var sessionId: String?
    var cliSessionId: String?
    var lastAssistantCliSessionId: String?
    var cwd: String?
    var title: String?
    var isArchived: Bool?
    var lastAssistantUuid: String?
    var postTurnSummaryFor: String?
    var postTurnSummary: RawSummary?
}

private struct RawSummary: Decodable {
    var status_category: String?
    var status_detail: String?
}

// 데스크탑 앱이 링크에서 받는 세션 번호 모양 (앱 코드의 검사와 같다)
private func isLocalSessionId(_ text: String) -> Bool {
    guard text.hasPrefix("local_") else { return false }
    let rest = text.dropFirst("local_".count)
    return (1...64).contains(rest.count)
        && rest.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" }
}

public func decodeAppSession(_ data: Data) -> AppSession? {
    guard let raw = try? JSONDecoder().decode(RawAppSession.self, from: data),
          let localId = raw.sessionId, isLocalSessionId(localId)
    else {
        return nil
    }
    let cliIds = [raw.cliSessionId, raw.lastAssistantCliSessionId].compactMap { $0 }
    // 요약은 턴이 끝난 뒤 앱이 붙인다. 요약 대상이 마지막 응답이 아니면 지난 턴 요약이다
    let isCurrent = raw.postTurnSummaryFor != nil && raw.postTurnSummaryFor == raw.lastAssistantUuid
    return AppSession(
        localId: localId,
        cliIds: Array(Set(cliIds)).sorted(),
        title: raw.title,
        cwd: raw.cwd,
        isArchived: raw.isArchived ?? false,
        summaryCategory: raw.postTurnSummary?.status_category,
        summaryDetail: raw.postTurnSummary?.status_detail,
        isSummaryCurrent: isCurrent
    )
}

// ===== 목록 =====

public enum BoardKind: Equatable {
    case waiting  // 답 기다림
    case working  // 일하는 중
    case review   // 확인 필요
    case done     // 끝남
}

public struct BoardRow: Equatable {
    public var localId: String
    public var title: String
    public var isTitleMissing: Bool  // 제목을 못 읽어 폴더 이름으로 대신 보임(앱 형식이 바뀌었을 수 있음)
    public var kind: BoardKind
    public var detail: String?
    public var since: Date           // 지금 상태가 시작된 시각
    public var link: URL?
    public var activity: String?     // 일하는 중일 때 하는 일

    public init(localId: String, title: String, isTitleMissing: Bool, kind: BoardKind,
                detail: String?, since: Date, link: URL?, activity: String? = nil) {
        self.localId = localId
        self.title = title
        self.isTitleMissing = isTitleMissing
        self.kind = kind
        self.detail = detail
        self.since = since
        self.link = link
        self.activity = activity
    }
}

// 도구 이름 -> 하는 일. 작업노트와 메뉴 막대가 같은 값을 쓴다(Worker 도 이 값만 받는다)
//   reading 읽는 중, editing 고치는 중, running 명령 실행 중, researching 찾아보는 중,
//   delegating 서브 에이전트에 맡기는 중, planning 계획 세우는 중, tool 그 밖 도구
public func activityFor(tool: String?) -> String? {
    guard let tool, !tool.isEmpty else { return nil }
    switch tool {
    case "Read", "Grep", "Glob", "LS": return "reading"
    case "Edit", "Write", "MultiEdit", "NotebookEdit": return "editing"
    case "Bash", "BashOutput", "KillShell": return "running"
    case "WebFetch", "WebSearch": return "researching"
    case "Agent", "Task": return "delegating"
    case "TodoWrite", "ExitPlanMode", "EnterPlanMode": return "planning"
    default:
        return tool.hasSuffix("update_plan") ? "planning" : "tool"
    }
}

// 30분 동안 상태 파일도 대화 기록도 바뀌지 않은 "일하는 중"은 버려진 턴으로 본다(앱이 비정상으로 꺼진 경우 등).
// Clauddy(renatoaug/claude-usage-monitor) 의 ADR-006 과 같은 기준
public let abandonedWorkSeconds: TimeInterval = 30 * 60

public let boardIdleLimit: TimeInterval = 24 * 60 * 60

private func folderName(_ path: String?) -> String {
    guard let path, !path.isEmpty else { return "?" }
    return URL(fileURLWithPath: path).lastPathComponent
}

// 상태 파일과 앱 세션 파일을 이어서 목록을 만든다.
//   sessions 가 nil 이면 앱 세션 폴더를 못 읽은 것이다. 그때는 상태 파일만으로 폴더 이름을 보여 주고 링크는 붙이지 않는다
//   transcriptModified: CLI 세션 번호 -> 대화 기록 파일 수정 시각
public func buildBoard(statuses: [SessionStatus], sessions: [AppSession]?,
                       transcriptModified: [String: Date], now: Date) -> [BoardRow] {
    var byCli: [String: AppSession] = [:]
    for session in sessions ?? [] {
        for cli in session.cliIds { byCli[cli] = session }
    }

    var rows: [BoardRow] = []
    var seen = Set<String>()
    // 한 앱 세션에 CLI 번호가 여럿이면 가장 최근 상태만 쓴다
    for status in statuses.sorted(by: { $0.updatedAt > $1.updatedAt }) {
        var state = status.state
        var since = status.updatedAt
        // 권한을 허락한 뒤 다시 일하는 순간에는 오는 훅이 없다. 답 기다림 뒤에 대화 기록이 바뀌었으면 일하는 중으로 본다
        if state == .waiting, let modified = transcriptModified[status.sessionId], modified > status.updatedAt {
            state = .working
            since = modified
        }
        var abandonedAt: Date?
        if state == .working {
            let lastSign = max(since, transcriptModified[status.sessionId] ?? .distantPast)
            if now.timeIntervalSince(lastSign) > abandonedWorkSeconds {
                state = .idle
                abandonedAt = lastSign
                since = lastSign
            }
        }
        let session: AppSession?
        if sessions == nil {
            session = nil
        } else {
            guard let match = byCli[status.sessionId], !match.isArchived else { continue }
            session = match
        }
        // 세션마다 가장 최근 상태 하나만 본다. 24시간 거르기보다 먼저 해야 한다.
        // 거르기를 먼저 하면 최신 상태가 걸러진 뒤 같은 세션의 더 오래된 상태가 대신 살아난다
        let key = session?.localId ?? "cli_\(status.sessionId)"
        if seen.contains(key) { continue }
        seen.insert(key)
        if state == .idle, now.timeIntervalSince(since) > boardIdleLimit { continue }

        let kind: BoardKind
        var detail: String?
        switch state {
        case .working: kind = .working
        case .waiting: kind = .waiting
        case .idle where abandonedAt != nil:
            // 버려진 턴: 앱 요약은 지난 턴 것일 수 있어서 보지 않는다
            kind = .done
        case .idle:
            if let session, session.isSummaryCurrent {
                detail = session.summaryDetail
                switch session.summaryCategory {
                case "blocked": kind = .waiting
                case "review_ready": kind = .review
                default: kind = .done
                }
            } else {
                kind = .done
            }
        }

        let title = session?.title.flatMap { $0.isEmpty ? nil : $0 }
        rows.append(BoardRow(
            localId: key,
            title: title ?? folderName(session?.cwd ?? status.cwd),
            isTitleMissing: title == nil,
            kind: kind,
            detail: detail,
            since: since,
            link: session.flatMap { sessionLink($0.localId) },
            activity: kind == .working ? status.activity : nil
        ))
    }

    let order: [BoardKind: Int] = [.waiting: 0, .working: 1, .review: 2, .done: 3]
    return rows.sorted {
        order[$0.kind]! != order[$1.kind]! ? order[$0.kind]! < order[$1.kind]! : $0.since > $1.since
    }
}

// ===== 3. 세션 여는 링크 =====

public func sessionLink(_ localId: String) -> URL? {
    guard isLocalSessionId(localId) else { return nil }
    return URL(string: "claude://code/continue?session=\(localId)")
}

// ===== 오래 기다림 알림 =====

public let waitAlertSeconds: TimeInterval = 10 * 60

public struct WaitAlert: Equatable {
    public var key: String  // 같은 기다림을 가리키는 값(세션 번호 + 기다림 시작 시각). 다시 기다리면 달라진다
    public var row: BoardRow
}

// 답 기다림이 10분 넘었고, 아직 알리지 않은 기다림
public func alertsDue(_ rows: [BoardRow], notified: Set<String>, now: Date) -> [WaitAlert] {
    rows.compactMap { row in
        guard row.kind == .waiting, now.timeIntervalSince(row.since) >= waitAlertSeconds else { return nil }
        let key = "\(row.localId)@\(Int(row.since.timeIntervalSince1970))"
        return notified.contains(key) ? nil : WaitAlert(key: key, row: row)
    }
}

func formatDate(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
