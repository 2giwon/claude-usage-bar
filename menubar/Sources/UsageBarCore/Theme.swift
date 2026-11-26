import CryptoKit
import Foundation

// 테마 적용의 화면 없는 계산 함수 (11-26).
// 작업노트 웹이 GitHub 저장소에 쓴 테마 요청을 맥에서 읽어, 켜진 Claude 테마(ClaudeFolio 마켓플레이스 플러그인)를
// 바꿀지 정하고, 처음 설치하는 테마의 파일이 안전한지 검사한다. 실제 명령 실행은 앱 쪽 ThemeApplier 가 한다.

// MARK: - 설정 파일

/// ~/.claude/claude-usage-bar-theme.json. 이 파일이 있을 때만 적용 기능이 켜진다(공개 앱에 개인 저장소 이름을 넣지 않으려고)
public struct ThemeConfig: Equatable {
    public var repo: String        // owner/name
    public var requestPath: String
    public var statusPath: String
    public var marketplace: String  // 테마 마켓플레이스 이름

    public init(repo: String, requestPath: String, statusPath: String, marketplace: String = "claudefolio-themes") {
        self.repo = repo
        self.requestPath = requestPath
        self.statusPath = statusPath
        self.marketplace = marketplace
    }
}

private struct RawConfig: Decodable {
    var repo: String
    var requestPath: String
    var statusPath: String
}

private func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

private func isSafeRepoPath(_ path: String) -> Bool {
    matches(path, #"^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$"#) && !path.split(separator: "/").contains("..")
}

public func decodeThemeConfig(_ data: Data?) -> ThemeConfig? {
    guard let data, let raw = try? JSONDecoder().decode(RawConfig.self, from: data) else { return nil }
    guard matches(raw.repo, #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#),
          isSafeRepoPath(raw.requestPath), isSafeRepoPath(raw.statusPath) else { return nil }
    return ThemeConfig(repo: raw.repo, requestPath: raw.requestPath, statusPath: raw.statusPath)
}

// MARK: - 이름, 요청, 플러그인 목록, 마켓플레이스

/// 테마 이름 규칙. 경로 문자나 대문자가 들어간 이름은 명령에 넘기지 않는다
public func isThemeName(_ name: String) -> Bool {
    name.count <= 64 && matches(name, #"^[a-z0-9]+(-[a-z0-9]+)*$"#)
}

public struct ThemeRequest: Equatable {
    public var theme: String
    public var requestedAt: Date
    public init(theme: String, requestedAt: Date) {
        self.theme = theme
        self.requestedAt = requestedAt
    }
}

private struct RawRequest: Decodable {
    var theme: String
    var requestedAt: String
}

public func decodeThemeRequest(_ data: Data) -> ThemeRequest? {
    guard let raw = try? JSONDecoder().decode(RawRequest.self, from: data),
          isThemeName(raw.theme), let at = parseDate(raw.requestedAt) else { return nil }
    return ThemeRequest(theme: raw.theme, requestedAt: at)
}

public struct InstalledPlugin: Equatable {
    public var id: String
    public var enabled: Bool
}

private struct RawPlugin: Decodable {
    var id: String
    var enabled: Bool?
}

/// `claude plugin list --json` 출력
public func decodePluginList(_ data: Data) -> [InstalledPlugin]? {
    guard let raw = try? JSONDecoder().decode([RawPlugin].self, from: data) else { return nil }
    return raw.map { InstalledPlugin(id: $0.id, enabled: $0.enabled ?? false) }
}

public struct ThemeState: Equatable {
    public var installed: [String]  // 설치된 테마 이름(목록 순서)
    public var enabled: [String]    // 켜진 테마 이름. 정상이면 하나
    public var current: String? { enabled.first }
}

public func themeState(_ plugins: [InstalledPlugin], marketplace: String) -> ThemeState {
    let suffix = "@\(marketplace)"
    let themes = plugins.filter { $0.id.hasSuffix(suffix) }
    let name = { (p: InstalledPlugin) in String(p.id.dropLast(suffix.count)) }
    return ThemeState(
        installed: themes.map(name).filter(isThemeName),
        enabled: themes.filter(\.enabled).map(name).filter(isThemeName)
    )
}

public struct MarketEntry: Equatable {
    public var name: String
    public var url: URL
    public var sha256: String
}

private struct RawMarket: Decodable {
    struct Plugin: Decodable {
        struct Source: Decodable {
            var url: String?
            var sha256: String?
        }
        var name: String
        var source: Source?
    }
    var plugins: [Plugin]
}

/// 테마 zip 은 테마 저장소의 GitHub Releases 에서만 받는다
private let allowedZipPrefix = "https://github.com/claudefoliothemes/claude-code-themes/releases/download/"

public func decodeMarketplace(_ data: Data) -> [MarketEntry]? {
    guard let raw = try? JSONDecoder().decode(RawMarket.self, from: data) else { return nil }
    return raw.plugins.compactMap { p in
        guard isThemeName(p.name), let urlText = p.source?.url, urlText.hasPrefix(allowedZipPrefix),
              !urlText.contains(".."), let url = URL(string: urlText),
              let sha = p.source?.sha256?.lowercased(), matches(sha, "^[0-9a-f]{64}$") else { return nil }
        return MarketEntry(name: p.name, url: url, sha256: sha)
    }
}

// MARK: - 할 일 결정

public enum ThemeAction: Equatable {
    case nothing
    case enable(name: String, disable: [String])
    case install(MarketEntry, disable: [String])
    case reject(String)
}

public func decideThemeAction(_ request: ThemeRequest, state: ThemeState, market: [MarketEntry]) -> ThemeAction {
    let others = state.enabled.filter { $0 != request.theme }
    if state.enabled == [request.theme] { return .nothing }
    guard let entry = market.first(where: { $0.name == request.theme }) else {
        return .reject("테마 목록에 없는 이름이에요 (\(request.theme))")
    }
    if state.installed.contains(request.theme) { return .enable(name: request.theme, disable: others) }
    return .install(entry, disable: others)
}

/// 마지막 결과(성공이든 실패든)가 바로 이 요청의 결과면 이미 처리한 요청이다. 실패한 요청을 매분 다시 시도하지 않는다.
/// 맥 시계와 폰 시계가 다를 수 있어서 시각의 앞뒤가 아니라 결과에 남긴 요청 시각이 같은지로 본다(리뷰 11-26)
public func isHandled(_ request: ThemeRequest, last: ThemeResult?) -> Bool {
    guard let last else { return false }
    return last.theme == request.theme && last.requestedAt == request.requestedAt
}

// MARK: - 지문과 파일 검사

public func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// 테마에 있어도 되는 파일
private func isAllowedThemePath(_ path: String) -> Bool {
    if path == ".claude-plugin/plugin.json" || path == ".claude-plugin/icon.png" { return true }
    return matches(path, #"^hooks/[A-Za-z0-9_.-]+\.(tsx|ts|js|json)$"#)
}

private let allowedPluginKeys: Set<String> = ["name", "version", "description", "author", "homepage", "license", "keywords", "repository"]

/// 테마 제작 도구가 만든 색 계산 파일. 45개 테마 모두 글자 하나 다르지 않게 같아서(11-26 확인) 지문이 같을 때만 코드 검사를 건너뛴다
private let knownHelperFiles: [String: String] = [
    "hooks/make-colors.js": "06c282db180ad32dd820a169050b9e11b1254745e76734bae3f5835611139a1e",
    "hooks/make-colors.d.ts": "d6bc9dbc1e1ab404079c4bc65307df2ae042c4e76822e86a5f4e5979f876777e",
]

/// 코드(문자열과 주석을 걷어 낸 부분)에 나오면 안 되는 이름. 테마는 $.theme, $.ui 만 쓰면 되므로
/// 전역 객체, 코드 실행, 네트워크, 저장소, 타이머로 갈 수 있는 이름을 전부 막는다(리뷰 11-26: 막는 목록 대신 좁게)
private let bannedNames = [
    "globalThis", "window", "self", "document", "Function", "constructor", "prototype", "__proto__", "eval",
    "Reflect", "Proxy", "Image", "Worker", "SharedWorker", "importScripts", "Bun", "Deno", "process", "module",
    "require", "exports", "fetch", "XMLHttpRequest", "WebSocket", "EventSource", "navigator", "location",
    "localStorage", "sessionStorage", "indexedDB", "caches", "postMessage", "setTimeout", "setInterval",
    "child_process",
]

/// JS 글을 훑어 주석을 걷어 낸 글(kept)과, 거기서 문자열 내용까지 비운 코드(code)를 만든다.
/// 템플릿의 ${ } 안은 코드로 남긴다. 문자열이나 주석이 끝나지 않으면 nil(잘못 읽어 코드를 놓치지 않게 실패로 본다)
private func splitCode(_ text: String) -> (kept: String, code: String)? {
    enum Mode { case code, line, block, single, double, template, regex }
    var kept = "", code = ""
    var mode = Mode.code
    var braces: [Int] = []  // 템플릿 ${ 마다 그 안의 { 깊이
    var inClass = false     // 정규식의 [ ] 안
    var prev: Character = ";" // 코드에서 마지막으로 본 공백 아닌 글자. 정규식과 나눗셈을 가른다
    let regexStart = Set("(,=:[!&|?{};+-*%<>~^")
    let chars = Array(text)
    var i = 0
    while i < chars.count {
        let c = chars[i], n = i + 1 < chars.count ? chars[i + 1] : "\0"
        switch mode {
        case .code:
            if c == "/" && n == "/" { mode = .line; i += 2; code += " "; kept += " "; continue }
            if c == "/" && n == "*" { mode = .block; i += 2; code += " "; kept += " "; continue }
            // 연산자 뒤의 / 는 정규식 시작. 이름이나 ) ] 뒤는 나눗셈으로 본다(잘못 봐도 더 엄격해질 뿐이다)
            if c == "/" && regexStart.contains(prev) {
                mode = .regex; inClass = false; kept.append(c); code += "/r"; i += 1; continue
            }
            if !c.isWhitespace { prev = c }
            if c == "'" { mode = .single } else if c == "\"" { mode = .double } else if c == "`" { mode = .template }
            else if c == "{" && !braces.isEmpty { braces[braces.count - 1] += 1 }
            else if c == "}" && !braces.isEmpty {
                if braces[braces.count - 1] == 0 { braces.removeLast(); mode = .template; kept.append(c); code.append("`"); i += 1; continue }
                braces[braces.count - 1] -= 1
            }
            kept.append(c); code.append(c)
        case .line:
            if c == "\n" { mode = .code; kept.append(c); code.append(c) }
        case .block:
            if c == "*" && n == "/" { mode = .code; i += 2; continue }
            if c == "\n" { kept.append(c); code.append(c) }
        case .single, .double:
            kept.append(c)
            if c == "\\" { if i + 1 < chars.count { kept.append(n) }; i += 2; continue }
            if c == "\n" { return nil }
            if (mode == .single && c == "'") || (mode == .double && c == "\"") { mode = .code; code.append(c) }
        case .regex:
            kept.append(c)
            if c == "\\" { if i + 1 < chars.count { kept.append(n) }; i += 2; continue }
            if c == "\n" { return nil }
            if c == "[" { inClass = true } else if c == "]" { inClass = false }
            else if c == "/" && !inClass { mode = .code; prev = "/"; code.append("/") }
        case .template:
            kept.append(c)
            if c == "\\" { if i + 1 < chars.count { kept.append(n) }; i += 2; continue }
            if c == "`" { mode = .code; code.append("``") }
            else if c == "$" && n == "{" { kept.append(n); code.append("`${"); braces.append(0); mode = .code; i += 2; continue }
        }
        i += 1
    }
    guard mode == .code || mode == .line, braces.isEmpty else { return nil }
    return (kept, code)
}

private func short(_ text: String) -> String {
    text.count <= 200 ? text : String(text.prefix(197)) + "..."
}

/// 한 코드 파일의 문제
private func inspectCode(_ path: String, _ text: String) -> [String] {
    guard let (kept, code) = splitCode(text) else { return ["\(path) 의 문자열이나 주석이 끝나지 않아요"] }
    var problems: [String] = []
    for name in bannedNames where matches(code, #"(?<![\w$])"# + NSRegularExpression.escapedPattern(for: name) + #"(?![\w$])"#) {
        problems.append("\(path) 에 \(name) 이(가) 있어요")
    }
    if matches(code, #"(?<![\w$.])import\s*\("#) { problems.append("\(path) 에 동적 import 가 있어요") }
    if code.contains("\\") { problems.append("\(path) 의 코드에 이스케이프(\\)가 있어요") }
    if matches(code, #"[\w$\)\]]\s*\[\s*["'`]"#) { problems.append("\(path) 에 글자로 속성을 꺼내는 코드가 있어요") }

    // 다른 모듈은 같은 폴더 파일만. 타입만 가져오는 import type ... from 'claude-code' 는 실행되지 않아 허락한다
    let withoutTypes = (try? NSRegularExpression(pattern: #"\bimport\s+type\s+[^;'"`]*?\bfrom\s*(['"])claude-code\1"#))
        .map { $0.stringByReplacingMatches(in: kept, range: NSRange(location: 0, length: (kept as NSString).length), withTemplate: "") } ?? kept
    for spec in withoutTypes.regexGroups(#"\b(?:from|import)\s*['"]([^'"]*)['"]"#) where !matches(spec, #"^\./[A-Za-z0-9_.-]+$"#) {
        problems.append("\(path) 가 바깥 모듈을 불러와요: \(spec)")
    }
    // 주소는 SVG 이름공간 하나만 허락한다
    for url in kept.regexMatches(#"(https?|wss?)://[^\s"'\\)`]+"#) where url != "http://www.w3.org/2000/svg" {
        problems.append("\(path) 에 주소가 있어요: \(url)")
    }
    return problems
}

/// 검사 결과 문제 목록. 비어 있으면 통과. 문제 설명은 200자 이하로 자른다(결과 파일이 커지지 않게)
public func inspectTheme(_ files: [String: Data]) -> [String] {
    inspectThemeFull(files).map(short)
}

private func inspectThemeFull(_ files: [String: Data]) -> [String] {
    var problems: [String] = []
    for path in files.keys.sorted() where !isAllowedThemePath(path) {
        problems.append("테마에 있으면 안 되는 파일: \(path)")
    }

    if let data = files[".claude-plugin/plugin.json"],
       let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
        for key in obj.keys.sorted() where !allowedPluginKeys.contains(key) {
            problems.append("plugin.json 에 모르는 항목: \(key)")
        }
    } else {
        problems.append("plugin.json 을 읽지 못했어요")
    }

    // hooks.json 은 mod 모듈 목록만 있어야 한다(명령을 실행하는 훅이 있으면 안 된다)
    if let data = files["hooks/hooks.json"] {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let modules = obj?["modules"] as? [String]
        if obj == nil || obj!.keys.sorted() != ["modules"] || modules == nil
            || !modules!.allSatisfy({ matches($0, #"^\./[A-Za-z0-9_.-]+\.(tsx|ts|js)$"#) }) {
            problems.append("hooks.json 에 모듈 목록 말고 다른 것이 있어요")
        }
    }

    for path in files.keys.sorted() where matches(path, #"\.(tsx|ts|js)$"#) {
        let data = files[path]!
        if let known = knownHelperFiles[path], sha256Hex(data) == known { continue }
        guard let text = String(data: data, encoding: .utf8) else {
            problems.append("\(path) 를 글로 읽지 못했어요")
            continue
        }
        problems += inspectCode(path, text)
    }
    return problems
}

private extension String {
    /// 첫 번째 괄호 묶음들
    func regexGroups(_ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = self as NSString
        return re.matches(in: self, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    func regexMatches(_ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = self as NSString
        return re.matches(in: self, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }
}

/// 폴더 안 파일들(상대 경로 → 내용). Claude Code 가 쓰는 .in_use 표시 폴더는 뺀다.
/// 링크나 읽을 수 없는 파일이 하나라도 있으면 nil(검사하지 못한 것을 지나치지 않게).
/// 맥 임시 폴더는 /var 와 /private/var 두 이름으로 불려서, 글자 수로 자르지 않고 경로 조각 단위로 상대 경로를 만든다(11-26 실제 사고)
public func readThemeTree(_ root: URL) -> [String: Data]? {
    let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
    let rootParts = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return nil }
    var files: [String: Data] = [:]
    while let url = walker.nextObject() as? URL {
        guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        if v.isSymbolicLink == true { return nil }
        let parts = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard parts.count > rootParts.count, Array(parts.prefix(rootParts.count)) == rootParts else { return nil }
        let rel = parts.dropFirst(rootParts.count)
        if rel.first == ".in_use" { continue }
        if v.isDirectory == true { continue }
        guard v.isRegularFile == true, let data = try? Data(contentsOf: url) else { return nil }
        files[rel.joined(separator: "/")] = data
    }
    return files
}

// MARK: - 결과 파일

public struct ThemeResult: Equatable {
    public var theme: String
    public var applied: Bool
    public var reason: String
    public var at: Date
    /// 처리한 요청의 시각(요청 파일 값 그대로). 맥과 폰 시계가 달라도 같은 요청인지 알 수 있다
    public var requestedAt: Date?
    public init(theme: String, applied: Bool, reason: String, at: Date, requestedAt: Date? = nil) {
        self.theme = theme
        self.applied = applied
        self.reason = reason
        self.at = at
        self.requestedAt = requestedAt
    }
}

public struct ThemeStatus: Equatable {
    public var current: String?
    public var installed: [String]
    public var last: ThemeResult?
    public init(current: String?, installed: [String], last: ThemeResult?) {
        self.current = current
        self.installed = installed
        self.last = last
    }
}

private func isoText(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: date)
}

public func encodeThemeStatus(_ status: ThemeStatus) -> Data {
    var obj: [String: Any] = [
        "version": 1,
        "current": status.current ?? NSNull(),
        "installed": status.installed,
        "last": NSNull(),
    ]
    if let l = status.last {
        var last: [String: Any] = ["theme": l.theme, "result": l.applied ? "applied" : "failed", "reason": l.reason, "at": isoText(l.at)]
        if let r = l.requestedAt { last["requestedAt"] = isoText(r) }
        obj["last"] = last
    }
    let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    return data + Data("\n".utf8)
}

public func decodeThemeStatus(_ data: Data) -> ThemeStatus? {
    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let installed = obj["installed"] as? [String] else { return nil }
    var last: ThemeResult?
    if let l = obj["last"] as? [String: Any], let theme = l["theme"] as? String, isThemeName(theme),
       let result = l["result"] as? String, let atText = l["at"] as? String, let at = parseDate(atText) {
        last = ThemeResult(theme: theme, applied: result == "applied", reason: l["reason"] as? String ?? "", at: at,
                           requestedAt: (l["requestedAt"] as? String).flatMap(parseDate))
    }
    return ThemeStatus(current: (obj["current"] as? String).flatMap { isThemeName($0) ? $0 : nil },
                       installed: installed.filter(isThemeName), last: last)
}

public func shouldWriteStatus(_ status: ThemeStatus, previous: ThemeStatus?) -> Bool {
    status != previous
}
