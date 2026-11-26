// UsageBarCore 계산 함수 검사. Xcode 없이 명령줄 도구만으로는 Swift Testing 이 빌드되지 않아서
// 테스트 대신 이 실행 파일을 쓴다. 하나라도 틀리면 종료 코드 1 로 끝난다.
//   swift run UsageBarChecks
import Foundation
import UsageBarCore

var failures = 0

func check(_ name: String, _ condition: Bool) {
    if condition {
        print("(pass) \(name)")
    } else {
        print("(fail) \(name)")
        failures += 1
    }
}

func date(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

let sample = """
{
  "version": 1,
  "updatedAt": "2026-11-26T00:14:00.000Z",
  "status": "ready",
  "limits": [
    { "kind": "five_hour", "percentUsed": 8, "resetsAt": "2026-11-26T04:20:00.000Z" },
    { "kind": "seven_day", "percentUsed": 41, "resetsAt": "2026-11-29T06:00:00.000Z" }
  ],
  "context": { "percent": 20, "tokens": 198228, "window": 1000000 },
  "session": "claude-usage-bar"
}
"""

// 3. 파일 읽기
let snapshot = decodeSnapshot(Data(sample.utf8))
check("3. JSON 을 읽어서 5시간 8% 로 해석한다",
      snapshot?.limits.first { $0.kind == "five_hour" }?.percentUsed == 8)
check("3. JSON 을 읽어서 주간 41% 로 해석한다",
      snapshot?.limits.first { $0.kind == "seven_day" }?.percentUsed == 41)
check("3. 초기화 시각과 갱신 시각을 날짜로 읽는다",
      snapshot?.limits.first?.resetsAt == date("2026-11-26T04:20:00Z")
          && snapshot?.updatedAt == date("2026-11-26T00:14:00Z"))
check("3. 컨텍스트와 세션 이름을 읽는다",
      snapshot?.context?.percent == 20 && snapshot?.session == "claude-usage-bar")
check("3. 깨진 JSON 은 실패(nil) 가 된다",
      decodeSnapshot(Data("{ not json".utf8)) == nil)

// 4. 주간 기준선: 초기화까지 3일 6시간 남았으면 7일 중 3일 18시간 지남 -> 90/168 = 53.6%
let weeklyReset = date("2026-11-29T06:00:00Z")
let now = weeklyReset.addingTimeInterval(-(3 * 24 + 6) * 3600)
let baseline = weeklyBaseline(resetsAt: weeklyReset, now: now)
check("4. 3일 18시간 지났으면 기준선은 54%", Int(baseline.rounded()) == 54)
check("4. 41% 를 썼으면 기준선보다 적어서 여유", pace(used: 41, baseline: baseline) == .comfortable)
check("4. 60% 를 썼으면 기준선보다 많아서 빠름", pace(used: 60, baseline: baseline) == .fast)

// 5. 초기화 지난 값, 오래된 값
let fiveHour = Limit(kind: "five_hour", percentUsed: 8, resetsAt: date("2026-11-26T04:20:00Z"))
let afterReset = windowView(fiveHour, now: date("2026-11-26T04:21:00Z"))
check("5. 초기화 시각이 지났으면 0% 로 보고 초기화됨으로 표시한다",
      afterReset.percent == 0 && afterReset.isReset)
let beforeReset = windowView(fiveHour, now: date("2026-11-26T04:19:00Z"))
check("5. 초기화 전이면 받은 값 그대로",
      beforeReset.percent == 8 && !beforeReset.isReset)
let updated = date("2026-11-26T00:14:00Z")
check("5. 31분 지난 값은 오래된 값", isStale(updatedAt: updated, now: updated.addingTimeInterval(31 * 60)))
check("5. 29분 지난 값은 아직 새 값", !isStale(updatedAt: updated, now: updated.addingTimeInterval(29 * 60)))

// 6. 경고 색
check("6. 80% 이상이면 경고", level(percent: 80) == .warning && level(percent: 95) == .warning)
check("6. 80% 미만이면 평소", level(percent: 79.9) == .normal && level(percent: 8) == .normal)

// 7. 언어 고르기: 맥 선호 언어 1순위를 본다
check("7. ko-KR 이면 한국어", language(preferred: ["ko-KR", "en-US"]) == .korean)
check("7. ko 만 있어도 한국어", language(preferred: ["ko"]) == .korean)
check("7. en-US 면 영어", language(preferred: ["en-US", "ko-KR"]) == .english)
check("7. ja-JP 면 영어", language(preferred: ["ja-JP"]) == .english)
check("7. 비어 있으면 영어", language(preferred: []) == .english)

let ko = Strings(.korean)
let en = Strings(.english)

// 8. 남은 시간
check("8. 한국어 3시간 39분 남음", ko.remaining(minutes: 3 * 60 + 39) == "3시간 39분 남음")
check("8. 영어 3h 39m left", en.remaining(minutes: 3 * 60 + 39) == "3h 39m left")
check("8. 한국어 3일 5시간 남음", ko.remaining(minutes: (3 * 24 + 5) * 60 + 10) == "3일 5시간 남음")
check("8. 영어 3d 5h left", en.remaining(minutes: (3 * 24 + 5) * 60 + 10) == "3d 5h left")
check("8. 1시간 안이면 분만", ko.remaining(minutes: 12) == "12분 남음" && en.remaining(minutes: 12) == "12m left")

// 9. 갱신 시각
check("9. 한국어 방금 갱신", ko.updated(minutesAgo: 0, isStale: false) == "방금 갱신")
check("9. 한국어 2분 전 갱신", ko.updated(minutesAgo: 2, isStale: false) == "2분 전 갱신")
check("9. 한국어 오래된 값", ko.updated(minutesAgo: 35, isStale: true) == "35분 전 값이에요")
check("9. 영어 Just updated", en.updated(minutesAgo: 0, isStale: false) == "Just updated")
check("9. 영어 Updated 2m ago", en.updated(minutesAgo: 2, isStale: false) == "Updated 2m ago")
check("9. 영어 오래된 값", en.updated(minutesAgo: 35, isStale: true) == "From 35m ago")
check("9. 한 시간 넘으면 시간 단위",
      ko.updated(minutesAgo: 130, isStale: true) == "2시간 전 값이에요"
          && en.updated(minutesAgo: 130, isStale: true) == "From 2h ago")

// 10. 번역 누락 없음
check("10. 한국어 문구가 모두 채워져 있다", ko.all.allSatisfy { !$0.isEmpty })
check("10. 영어 문구가 모두 채워져 있다", en.all.allSatisfy { !$0.isEmpty })
check("10. 영어 문구에 한국어가 섞이지 않는다",
      en.all.allSatisfy { $0.range(of: "\\p{Hangul}", options: .regularExpression) == nil })
check("10. 문장형 문구도 두 언어 다 채워져 있다",
      [ko, en].allSatisfy {
          !$0.resets("13:20").isEmpty && !$0.pace(isFast: true, baseline: "54%").isEmpty
              && !$0.pace(isFast: false, baseline: "54%").isEmpty && !$0.session("x").isEmpty
              && !$0.tokens(used: "198K", of: "1M").isEmpty
      })

print(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
