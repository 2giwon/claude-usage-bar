import Foundation

// 화면 문구 표. 맥의 선호 언어 1순위가 한국어면 한국어, 그 밖에는 영어로 보여 준다
public enum Language: Equatable {
    case korean
    case english
}

public func language(preferred: [String]) -> Language {
    guard let first = preferred.first?.lowercased() else { return .english }
    return first == "ko" || first.hasPrefix("ko-") || first.hasPrefix("ko_") ? .korean : .english
}

public struct Strings {
    public let language: Language

    public init(_ language: Language) {
        self.language = language
    }

    private func pick(_ korean: String, _ english: String) -> String {
        language == .korean ? korean : english
    }

    public var title: String { pick("Claude 사용량", "Claude Usage") }
    public var waiting: String { pick("기다리는 중", "Waiting") }
    public var emptyNotice: String {
        pick("Claude Code에서 응답을 한 번 받으면 표시돼요", "Shows after your next Claude Code response")
    }
    public var failedNotice: String { pick("사용량 파일을 읽지 못했어요", "Couldn't read the usage file") }
    public var noPlanNotice: String { pick("구독 요금제 사용량이 없어요", "No subscription plan usage") }
    public var footer: String { pick("Claude Code 응답 기준", "Via Claude Code") }
    public var refresh: String { pick("새로 읽기", "Refresh") }
    public var refreshed: String { pick("다시 읽었어요", "Refreshed") }
    public var refreshHelp: String { pick("사용량 파일 다시 읽기", "Read the usage file again") }
    public var quit: String { pick("종료", "Quit") }
    public var quitHelp: String { pick("Claude Usage Bar 종료", "Quit Claude Usage Bar") }
    public var fiveHourTitle: String { pick("5시간 사용량", "5-hour usage") }
    public var weeklyTitle: String { pick("주간 사용량", "Weekly usage") }
    public var contextTitle: String { pick("지금 세션 컨텍스트", "Session context") }
    public var resetDone: String { pick("초기화됨, 다음 응답 때 갱신", "Reset, updates on next response") }
    public var showAfterResponse: String { pick("다음 응답 때 표시", "After next reply") }

    // 고정 문구 전체. 번역을 빠뜨리지 않았는지 검사할 때 쓴다
    public var all: [String] {
        [title, waiting, emptyNotice, failedNotice, noPlanNotice, footer, refresh, refreshed,
         refreshHelp, quit, quitHelp, fiveHourTitle, weeklyTitle, contextTitle, resetDone,
         showAfterResponse]
    }

    // "3시간 39분 남음" / "3h 39m left"
    public func remaining(minutes: Int) -> String {
        let total = max(0, minutes)
        let days = total / (24 * 60)
        let hours = (total % (24 * 60)) / 60
        let mins = total % 60
        if days > 0 { return pick("\(days)일 \(hours)시간 남음", "\(days)d \(hours)h left") }
        if hours > 0 { return pick("\(hours)시간 \(mins)분 남음", "\(hours)h \(mins)m left") }
        return pick("\(mins)분 남음", "\(mins)m left")
    }

    // "방금 갱신", "2분 전 갱신", "35분 전 값이에요" / "Just updated", "Updated 2m ago", "From 35m ago"
    public func updated(minutesAgo: Int, isStale: Bool) -> String {
        let minutes = max(0, minutesAgo)
        if minutes < 1, !isStale { return pick("방금 갱신", "Just updated") }
        let ago = minutes < 60
            ? pick("\(minutes)분 전", "\(minutes)m ago")
            : pick("\(minutes / 60)시간 전", "\(minutes / 60)h ago")
        return isStale
            ? pick("\(ago) 값이에요", "From \(ago)")
            : pick("\(ago) 갱신", "Updated \(ago)")
    }

    // "13:20 초기화" / "Resets 1:20 PM". time 은 이미 언어에 맞게 만든 시각 글자
    public func resets(_ time: String) -> String {
        pick("\(time) 초기화", "Resets \(time)")
    }

    // 주간 기준선 안내
    public func pace(isFast: Bool, baseline: String) -> String {
        isFast
            ? pick("이 속도면 초기화 전에 다 써요 (기준선 \(baseline))",
                   "Over pace, may run out (pace \(baseline))")
            : pick("지금 속도면 여유 있어요 (기준선 \(baseline))",
                   "On pace, room to spare (pace \(baseline))")
    }

    // "claude-usage-bar 세션" / "claude-usage-bar"
    public func session(_ name: String) -> String {
        pick("\(name) 세션", name)
    }

    // "1M 중 198K" / "198K of 1M"
    public func tokens(used: String, of window: String) -> String {
        pick("\(window) 중 \(used)", "\(used) of \(window)")
    }

    // ===== 세션 현황판 =====

    public var boardTitle: String { pick("세션", "Sessions") }
    public var boardWaiting: String { pick("답 기다림", "Needs you") }
    public var boardWorking: String { pick("일하는 중", "Working") }
    public var boardReview: String { pick("확인 필요", "Review") }
    public var boardDone: String { pick("끝남", "Done") }
    public var boardEmpty: String { pick("지금 열린 세션이 없어요", "No open sessions") }
    public var boardFailed: String { pick("세션 상태를 읽지 못했어요", "Couldn't read session status") }
    public var boardTitleMissing: String {
        pick("앱 형식이 바뀌어 제목을 못 읽었어요", "Couldn't read the title, the app's format may have changed")
    }
    public var boardOpenFailed: String { pick("세션을 열지 못했어요", "Couldn't open the session") }
    public var boardOpenHelp: String { pick("눌러서 이 세션 열기", "Open this session") }
    public var boardAlertTitle: String { pick("답을 기다리는 세션이 있어요", "A session is waiting for you") }
    public var boardUploadFailed: String { pick("작업노트로 보내지 못했어요", "Couldn't send the list") }

    // 하는 일 한 줄: activityFor(tool:) 의 값
    public func boardActivity(_ activity: String?) -> String? {
        switch activity {
        case "reading": return pick("파일 읽는 중", "Reading files")
        case "editing": return pick("파일 고치는 중", "Editing files")
        case "running": return pick("명령 실행 중", "Running a command")
        case "researching": return pick("찾아보는 중", "Looking things up")
        case "delegating": return pick("서브 에이전트에 맡기는 중", "Delegating to an agent")
        case "planning": return pick("계획 세우는 중", "Planning")
        case "tool": return pick("도구 쓰는 중", "Using a tool")
        default: return nil
        }
    }

    public var boardAll: [String] {
        ["reading", "editing", "running", "researching", "delegating", "planning", "tool"].compactMap(boardActivity)
        + [boardTitle, boardWaiting, boardWorking, boardReview, boardDone, boardEmpty, boardFailed,
         boardTitleMissing, boardOpenFailed, boardOpenHelp, boardAlertTitle, boardUploadFailed,
         boardAlertBody("x"), boardSince(minutes: 0), boardSince(minutes: 5), boardSince(minutes: 90)]
    }

    // "주식 종목 분석 세션이 10분 넘게 답을 기다리고 있어요"
    public func boardAlertBody(_ title: String) -> String {
        pick("\(title) 세션이 10분 넘게 답을 기다리고 있어요", "\(title) has been waiting for over 10 minutes")
    }

    // "방금", "5분 전", "1시간 전" / "now", "5m ago", "1h ago"
    public func boardSince(minutes: Int) -> String {
        let value = max(0, minutes)
        if value < 1 { return pick("방금", "now") }
        if value < 60 { return pick("\(value)분 전", "\(value)m ago") }
        return pick("\(value / 60)시간 전", "\(value / 60)h ago")
    }
}
