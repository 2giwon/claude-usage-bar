import Foundation
import UsageBarCore

// 화면에 쓰는 문구. 맥의 선호 언어 1순위를 보고 한국어 또는 영어를 고른다.
// 문구 자체는 UsageBarCore 의 Strings 에 있고, 여기서는 시각과 숫자를 언어에 맞게 글자로 바꾼다
enum Words {
    // 확인용 그림(--render)에서 두 언어를 번갈아 그리려고 바꿀 수 있게 둔다
    static var strings = Strings(language(preferred: Locale.preferredLanguages))

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    // 5시간 창: "13:20 초기화" / "Resets 1:20 PM"
    static func resetClock(_ date: Date) -> String {
        strings.resets(formatter(korean: "HH:mm", english: "h:mm a").string(from: date))
    }

    // 주간 창: "29일 (일) 15:00 초기화" / "Resets Sun 29, 3:00 PM"
    static func resetDay(_ date: Date) -> String {
        strings.resets(formatter(korean: "d일 (E) HH:mm", english: "EEE d, h:mm a").string(from: date))
    }

    static func remaining(until date: Date, now: Date) -> String {
        strings.remaining(minutes: Int(date.timeIntervalSince(now) / 60))
    }

    static func updated(_ date: Date, now: Date, isStale: Bool) -> String {
        strings.updated(minutesAgo: Int(now.timeIntervalSince(date) / 60), isStale: isStale)
    }

    // "1M 중 198K" / "198K of 1M"
    static func tokens(_ used: Int, of window: Int) -> String {
        strings.tokens(used: short(used), of: short(window))
    }

    private static func formatter(korean: String, english: String) -> DateFormatter {
        let formatter = DateFormatter()
        if strings.language == .korean {
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = korean
        } else {
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = english
        }
        return formatter
    }

    private static func short(_ value: Int) -> String {
        if value >= 1_000_000, value % 1_000_000 == 0 { return "\(value / 1_000_000)M" }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return "\(value / 1_000)K" }
        return "\(value)"
    }
}
