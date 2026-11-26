import Foundation

// mod가 쓰는 ~/.claude/claude-usage-bar.json 의 내용
public struct Snapshot: Equatable {
    public var version: Int
    public var updatedAt: Date
    public var status: String
    public var limits: [Limit]
    public var context: Context?
    public var session: String?

    public init(
        version: Int, updatedAt: Date, status: String, limits: [Limit],
        context: Context?, session: String?
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.status = status
        self.limits = limits
        self.context = context
        self.session = session
    }
}

public struct Limit: Equatable {
    public var kind: String
    public var percentUsed: Double
    public var resetsAt: Date?

    public init(kind: String, percentUsed: Double, resetsAt: Date? = nil) {
        self.kind = kind
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
    }
}

public struct Context: Equatable {
    public var percent: Double?
    public var tokens: Int?
    public var window: Int

    public init(percent: Double?, tokens: Int?, window: Int) {
        self.percent = percent
        self.tokens = tokens
        self.window = window
    }
}

public let warnPercent = 80.0
public let staleSeconds: TimeInterval = 30 * 60
public let weekSeconds: TimeInterval = 7 * 24 * 60 * 60

// 파일 내용(JSON)을 읽는다. 깨졌으면 nil
public func decodeSnapshot(_ data: Data) -> Snapshot? {
    guard let raw = try? JSONDecoder().decode(RawSnapshot.self, from: data),
          let updatedAt = parseDate(raw.updatedAt)
    else {
        return nil
    }
    return Snapshot(
        version: raw.version,
        updatedAt: updatedAt,
        status: raw.status,
        limits: raw.limits.map {
            Limit(kind: $0.kind, percentUsed: $0.percentUsed, resetsAt: $0.resetsAt.flatMap(parseDate))
        },
        context: raw.context.map { Context(percent: $0.percent, tokens: $0.tokens, window: $0.window) },
        session: raw.session
    )
}

private struct RawSnapshot: Decodable {
    var version: Int
    var updatedAt: String
    var status: String
    var limits: [RawLimit]
    var context: RawContext?
    var session: String?
}

private struct RawLimit: Decodable {
    var kind: String
    var percentUsed: Double
    var resetsAt: String?
}

private struct RawContext: Decodable {
    var percent: Double?
    var tokens: Int?
    var window: Int
}

// "2026-11-26T04:20:00.000Z" 처럼 소수점 초가 있어도, 없어도 읽는다
func parseDate(_ text: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}

// 한 사용량 창을 지금 시각 기준으로 본 값. 초기화 시각이 지났으면 0%로 보고 isReset 을 켠다
public struct WindowView: Equatable {
    public var percent: Double
    public var resetsAt: Date?
    public var isReset: Bool
}

public func windowView(_ limit: Limit, now: Date) -> WindowView {
    if let resetsAt = limit.resetsAt, resetsAt <= now {
        return WindowView(percent: 0, resetsAt: resetsAt, isReset: true)
    }
    return WindowView(percent: limit.percentUsed, resetsAt: limit.resetsAt, isReset: false)
}

// 주간 기준선: 일주일 중 지난 시간만큼 고르게 썼다면 지금 몇 %여야 하는지
public func weeklyBaseline(resetsAt: Date, now: Date) -> Double {
    let remaining = resetsAt.timeIntervalSince(now)
    let elapsed = weekSeconds - remaining
    return min(100, max(0, elapsed / weekSeconds * 100))
}

public enum Pace: Equatable {
    case comfortable  // 기준선보다 적게 씀
    case fast         // 기준선보다 많이 씀
}

public func pace(used: Double, baseline: Double) -> Pace {
    used > baseline ? .fast : .comfortable
}

// 30분 넘게 갱신이 없으면 오래된 값
public func isStale(updatedAt: Date, now: Date) -> Bool {
    now.timeIntervalSince(updatedAt) > staleSeconds
}

public enum Level: Equatable {
    case normal
    case warning
}

public func level(percent: Double) -> Level {
    percent >= warnPercent ? .warning : .normal
}
