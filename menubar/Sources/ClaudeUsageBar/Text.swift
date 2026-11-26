import Foundation

// 화면에 쓰는 한국어 문구
enum Words {
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "d일 (E) HH:mm"
        return formatter
    }()

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func resetClock(_ date: Date) -> String {
        "\(clock.string(from: date)) 초기화"
    }

    static func resetDay(_ date: Date) -> String {
        "\(dayClock.string(from: date)) 초기화"
    }

    // "4시간 33분 남음", "3일 6시간 남음", "12분 남음"
    static func remaining(until date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let days = minutes / (24 * 60)
        let hours = (minutes % (24 * 60)) / 60
        let mins = minutes % 60
        if days > 0 { return "\(days)일 \(hours)시간 남음" }
        if hours > 0 { return "\(hours)시간 \(mins)분 남음" }
        return "\(mins)분 남음"
    }

    // "방금 갱신", "2분 전 갱신", "3시간 전 갱신"
    static func updated(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "방금 갱신" }
        if minutes < 60 { return "\(minutes)분 전 갱신" }
        return "\(minutes / 60)시간 전 갱신"
    }

    // "1M 중 198K"
    static func tokens(_ used: Int, of window: Int) -> String {
        "\(short(window)) 중 \(short(used))"
    }

    private static func short(_ value: Int) -> String {
        if value >= 1_000_000, value % 1_000_000 == 0 { return "\(value / 1_000_000)M" }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return "\(value / 1_000)K" }
        return "\(value)"
    }
}
