// UsageBarCore 계산 함수 검사. Xcode 없이 명령줄 도구만으로는 Swift Testing 이 빌드되지 않아서
// 테스트 대신 이 실행 파일을 쓴다. 하나라도 틀리면 종료 코드 1 로 끝난다.
//   swift run UsageBarChecks
import Foundation
import UsageBarCore

var failures = 0

// swift run UsageBarChecks --inspect <폴더>...  실제 테마 폴더(zip 을 푼 것)를 안전 검사에 돌려 본다(오탐 확인용)
if let i = CommandLine.arguments.firstIndex(of: "--inspect") {
    var bad = 0
    for dir in CommandLine.arguments[(i + 1)...] {
        // 앱과 같은 폴더 읽기 함수를 쓴다(앱만 다른 방식으로 읽다가 생긴 11-26 사고를 이 도구로 못 잡았다)
        let root = URL(fileURLWithPath: dir)
        let problems = readThemeTree(root).map(inspectTheme) ?? ["폴더를 읽지 못했어요(링크나 읽을 수 없는 파일)"]
        print(problems.isEmpty ? "(ok) \(root.lastPathComponent)" : "(problem) \(root.lastPathComponent): \(problems)")
        if !problems.isEmpty { bad += 1 }
    }
    exit(bad == 0 ? 0 : 1)
}

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

// ─── 테마 적용 (11-26) ───────────────────────────────────────────────────────

// M1. 설정 파일
let config = decodeThemeConfig(Data("""
{ "repo": "someone/private-docs", "requestPath": "claude-theme/request.json", "statusPath": "claude-theme/status.json" }
""".utf8))
check("M1. 설정 파일을 읽는다", config?.repo == "someone/private-docs" && config?.statusPath == "claude-theme/status.json")
check("M1. 설정 파일이 없거나 깨지면 nil (적용 기능 꺼짐)", decodeThemeConfig(nil) == nil && decodeThemeConfig(Data("{".utf8)) == nil)
check("M1. 저장소 이름이 owner/name 모양이 아니면 nil",
      decodeThemeConfig(Data(#"{"repo":"a/b/c","requestPath":"r.json","statusPath":"s.json"}"#.utf8)) == nil)
check("M1. 경로에 .. 이 있으면 nil",
      decodeThemeConfig(Data(#"{"repo":"a/b","requestPath":"../r.json","statusPath":"s.json"}"#.utf8)) == nil)

// 요청과 플러그인 목록
let request = decodeThemeRequest(Data(#"{"version":1,"theme":"harvest-home","requestedAt":"2026-11-26T10:00:00.000Z"}"#.utf8))
check("요청 파일을 읽는다(밀리초 시각 포함)", request?.theme == "harvest-home" && request?.requestedAt == date("2026-11-26T10:00:00Z"))
check("요청 이름이 이상하면 nil", decodeThemeRequest(Data(#"{"theme":"../x","requestedAt":"2026-11-26T10:00:00Z"}"#.utf8)) == nil)

let pluginList = decodePluginList(Data("""
[{"id":"claude-hud@claude-hud","enabled":false},
 {"id":"pixel-cafe@claudefolio-themes","enabled":true},
 {"id":"sky-clock@claudefolio-themes","enabled":false}]
""".utf8)) ?? []
let state = themeState(pluginList, marketplace: "claudefolio-themes")
check("플러그인 목록에서 켜진 테마와 설치된 테마를 뽑는다",
      state.current == "pixel-cafe" && state.installed == ["pixel-cafe", "sky-clock"] && state.enabled == ["pixel-cafe"])

let market = decodeMarketplace(Data("""
{"plugins":[
 {"name":"pixel-cafe","source":{"source":"archive","url":"https://github.com/claudefoliothemes/claude-code-themes/releases/download/v0.1.0/pixel-cafe-0.1.0.zip","sha256":"\(String(repeating: "a", count: 64))"}},
 {"name":"sky-clock","source":{"source":"archive","url":"https://github.com/claudefoliothemes/claude-code-themes/releases/download/v0.1.0/sky-clock-0.1.0.zip","sha256":"\(String(repeating: "b", count: 64))"}},
 {"name":"harvest-home","source":{"source":"archive","url":"https://github.com/claudefoliothemes/claude-code-themes/releases/download/v0.1.0/harvest-home-0.1.0.zip","sha256":"\(String(repeating: "c", count: 64))"}},
 {"name":"evil","source":{"source":"archive","url":"https://example.com/evil.zip","sha256":"\(String(repeating: "d", count: 64))"}}
]}
""".utf8)) ?? []
check("마켓플레이스에서 GitHub 테마 저장소 zip 만 받는다(다른 주소는 뺀다)",
      market.map(\.name) == ["pixel-cafe", "sky-clock", "harvest-home"])

// M2, M3, M4. 할 일 결정
func req(_ name: String) -> ThemeRequest { ThemeRequest(theme: name, requestedAt: date("2026-11-26T10:00:00Z")) }
check("M2. 요청이 지금 테마와 같으면 아무것도 안 한다",
      decideThemeAction(req("pixel-cafe"), state: state, market: market) == .nothing)
check("M3. 설치된 테마면 다른 테마를 끄고 켠다",
      decideThemeAction(req("sky-clock"), state: state, market: market) == .enable(name: "sky-clock", disable: ["pixel-cafe"]))
if case let .install(entry, disable) = decideThemeAction(req("harvest-home"), state: state, market: market) {
    check("M3. 처음 테마면 설치한다", entry.name == "harvest-home" && disable == ["pixel-cafe"])
} else {
    check("M3. 처음 테마면 설치한다", false)
}
if case .reject = decideThemeAction(req("not-in-market"), state: state, market: market) {
    check("M4. 마켓플레이스에 없는 이름은 거절", true)
} else {
    check("M4. 마켓플레이스에 없는 이름은 거절", false)
}

// 이미 처리한 요청인지. 맥 시계와 폰 시계가 달라도 되게, 결과에 남긴 요청 시각과 같은지로 본다(리뷰 11-26)
let lastDone = ThemeResult(theme: "harvest-home", applied: false, reason: "x",
                           at: date("2026-11-26T09:58:00Z"), requestedAt: date("2026-11-26T10:00:00Z"))
check("결과의 요청 시각이 같으면 이미 처리한 요청(맥 시계가 늦어도)", isHandled(req("harvest-home"), last: lastDone))
check("요청 시각이 다르면 새 요청",
      !isHandled(ThemeRequest(theme: "harvest-home", requestedAt: date("2026-11-26T10:05:00Z")), last: lastDone))
check("다른 테마의 결과면 아직 처리 안 함", !isHandled(req("sky-clock"), last: lastDone))

// M5. 지문
check("M5. SHA-256 을 16진수로 계산한다",
      sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

// M6. 테마 파일 안전 검사
let goodTheme: [String: Data] = [
    ".claude-plugin/plugin.json": Data(#"{"name":"pixel-cafe","version":"0.1.0","description":"d","author":{"name":"ClaudeFolio","url":"https://claudefolio.com"},"homepage":"https://claudefolio.com/themes","license":"MIT","keywords":["theme"]}"#.utf8),
    ".claude-plugin/icon.png": Data([0x89, 0x50]),
    "hooks/hooks.json": Data(#"{ "modules": ["./register.tsx"] }"#.utf8),
    "hooks/register.tsx": Data("""
    import type { EngineInterface, Register } from 'claude-code'
    import { SCENE } from './scene.js'
    async function applyLook($: EngineInterface) { await $.theme.set({}) }
    """.utf8),
    "hooks/scene.js": Data(#"export const SCENE = "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>""#.utf8),
    "hooks/scene.d.ts": Data("export declare const SCENE: string".utf8),
]
check("M6. pixel-cafe 와 같은 구조는 통과", inspectTheme(goodTheme).isEmpty)

func withFile(_ path: String, _ text: String) -> [String: Data] {
    var t = goodTheme
    t[path] = Data(text.utf8)
    return t
}
let riskyCases: [(String, [String: Data])] = [
    ("fetch", withFile("hooks/register.tsx", "await fetch('https://x')")),
    ("child_process", withFile("hooks/register.tsx", "import { exec } from 'node:child_process'")),
    ("eval", withFile("hooks/scene.js", "eval('1')")),
    ("동적 import", withFile("hooks/register.tsx", "await import('./x.js')")),
    ("require", withFile("hooks/register.tsx", "const fs = require('fs')")),
    ("WebSocket", withFile("hooks/register.tsx", "new WebSocket('wss://x')")),
    ("외부 모듈", withFile("hooks/register.tsx", "import fs from 'fs'")),
    ("다른 주소", withFile("hooks/scene.js", "const u = 'https://evil.example/collect'")),
    ("모르는 파일(명령)", withFile("commands/run.md", "run")),
    ("MCP 서버 설정", withFile(".mcp.json", "{}")),
    ("plugin.json 의 mcpServers", withFile(".claude-plugin/plugin.json", #"{"name":"x","mcpServers":{}}"#)),
    ("hooks.json 의 명령 훅", withFile("hooks/hooks.json", #"{"hooks":{"SessionStart":[]}}"#)),
    // 리뷰(11-26)가 찾은 우회
    ("한 줄에 상대 import + 바깥 import", withFile("hooks/register.tsx", "import a from './a.js'; import fs from 'node:fs';")),
    ("여러 줄 import", withFile("hooks/register.tsx", "import {\n  readFile\n} from 'fs'")),
    ("부수 효과 import", withFile("hooks/register.tsx", "import 'node:fs'")),
    ("글자 이어 붙인 속성 접근", withFile("hooks/register.tsx", "globalThis['fe' + 'tch'](u)")),
    ("변수에 담은 fetch", withFile("hooks/register.tsx", "const f = fetch; f(u)")),
    ("(0,eval)", withFile("hooks/register.tsx", "(0, eval)(s)")),
    ("Function(s)", withFile("hooks/register.tsx", "Function(s)()")),
    ("주석 끼운 동적 import", withFile("hooks/register.tsx", "import/**/('./x.js')")),
    ("유니코드 이스케이프", withFile("hooks/register.tsx", "\\u0066etch(u)")),
    ("템플릿 안 코드", withFile("hooks/register.tsx", "const s = `a${fetch(u)}b`")),
    ("Image 로 주소 보내기", withFile("hooks/register.tsx", "new Image().src = u")),
    ("setTimeout", withFile("hooks/register.tsx", "setTimeout(s, 1)")),
    ("끝나지 않은 문자열", withFile("hooks/register.tsx", "const s = 'abc")),
    ("make-colors.js 를 바꾼 것", withFile("hooks/make-colors.js", "export const makeColors = () => fetch(u)")),
]
for (name, files) in riskyCases {
    check("M6. 위험: \(name) 은 걸린다", !inspectTheme(files).isEmpty)
}
check("M6. 문자열과 주석 안의 낱말(window, fetch)은 걸리지 않는다",
      inspectTheme(withFile("hooks/register.tsx", """
      // fetch is not used here
      const alt = 'Rain on the window, fetch(nothing)'
      const t = `light through the window`
      """)).isEmpty)
check("M6. 정규식 안의 \\ 와 따옴표는 걸리지 않는다(window-clock 테마)",
      inspectTheme(withFile("hooks/register.tsx", #"const SOUTHERN = /^(Australia)\/|it's/i; const half = a / b / c"#)).isEmpty)
check("M6. 나눗셈 뒤 코드는 그대로 검사한다",
      !inspectTheme(withFile("hooks/register.tsx", "const x = a / b; fetch(u) / 2")).isEmpty)
let longLine = withFile("hooks/register.tsx", "import fs from 'fs'" + String(repeating: " ", count: 5000))
check("M6. 문제 설명은 200자를 넘지 않는다", inspectTheme(longLine).allSatisfy { $0.count <= 200 })

// 폴더 읽기: 맥 임시 폴더(/var 와 /private/var 두 이름)에서도 상대 경로가 맞아야 한다(11-26 실제 사고)
let treeRoot = FileManager.default.temporaryDirectory.appendingPathComponent("usagebar-check-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: treeRoot.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: treeRoot.appendingPathComponent(".in_use"), withIntermediateDirectories: true)
try? Data("{}".utf8).write(to: treeRoot.appendingPathComponent(".claude-plugin/plugin.json"))
try? Data("1".utf8).write(to: treeRoot.appendingPathComponent(".in_use/123"))
let tree = readThemeTree(treeRoot)
check("폴더 읽기: 임시 폴더에서도 상대 경로가 .claude-plugin/plugin.json", tree.map { Array($0.keys) } == [".claude-plugin/plugin.json"])
try? FileManager.default.createSymbolicLink(at: treeRoot.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
check("폴더 읽기: 링크가 있으면 nil", readThemeTree(treeRoot) == nil)
try? FileManager.default.removeItem(at: treeRoot)

// M7. 결과 파일은 바뀔 때만 쓴다
let s1 = ThemeStatus(current: "pixel-cafe", installed: ["pixel-cafe"], last: nil)
let s2 = ThemeStatus(current: "sky-clock", installed: ["pixel-cafe", "sky-clock"], last: lastDone)
check("M7. 같으면 쓰지 않는다", !shouldWriteStatus(s1, previous: s1))
check("M7. 다르면 쓴다, 처음이면 쓴다", shouldWriteStatus(s2, previous: s1) && shouldWriteStatus(s1, previous: nil))
let encoded = encodeThemeStatus(s2)
let back = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any]
let last = back?["last"] as? [String: Any]
check("M7. 결과 파일 모양: current, installed, last(theme, result, reason, at)",
      back?["version"] as? Int == 1 && back?["current"] as? String == "sky-clock"
          && last?["result"] as? String == "failed" && last?["at"] as? String == "2026-11-26T09:58:00.000Z"
          && last?["requestedAt"] as? String == "2026-11-26T10:00:00.000Z")
check("M7. 웹이 쓰는 결과 파일을 다시 읽는다", decodeThemeStatus(encoded) == s2)

print(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
