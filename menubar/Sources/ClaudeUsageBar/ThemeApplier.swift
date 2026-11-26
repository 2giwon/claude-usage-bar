import Foundation
import UsageBarCore
import UserNotifications

// 테마 적용 (11-26). ~/.claude/claude-usage-bar-theme.json 이 있을 때만 켜진다.
// 60초마다 GitHub 저장소의 테마 요청을 읽고(gh 명령의 로그인을 빌려 쓴다, 토큰을 저장하지 않는다),
// 켜진 Claude 테마와 다르면 `claude plugin` 으로 바꾼 뒤 결과 파일을 쓴다. 결과 파일은 바뀔 때만 쓴다.
// 계산(할 일 결정, 안전 검사)은 UsageBarCore/Theme.swift, 여기는 명령 실행과 파일 주고받기만 한다.
final class ThemeApplier {
    static let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/claude-usage-bar-theme.json")

    private let config: ThemeConfig
    private let queue = DispatchQueue(label: "claude-usage-bar.theme")
    private var timer: DispatchSourceTimer?
    private var seeded = false
    private var lastWritten: ThemeStatus?
    private var lastResult: ThemeResult?
    private let gh: String
    private let claude: String
    private let isKorean = language(preferred: Locale.preferredLanguages) == .korean

    private init(config: ThemeConfig, gh: String, claude: String) {
        self.config = config
        self.gh = gh
        self.claude = claude
    }

    /// 설정 파일이 있고 gh, claude 명령을 찾으면 시작한다. 아니면 아무 일도 하지 않는다
    static func startIfConfigured() -> ThemeApplier? {
        guard let config = decodeThemeConfig(try? Data(contentsOf: configURL)) else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let gh = firstExecutable(["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]),
              let claude = firstExecutable(["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"])
        else {
            NSLog("[theme] gh 또는 claude 명령을 찾지 못해 테마 적용을 켜지 않았어요")
            return nil
        }
        let applier = ThemeApplier(config: config, gh: gh, claude: claude)
        applier.start()
        return applier
    }

    private static func firstExecutable(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func start() {
        requestNotificationPermission()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 3, repeating: 60)
        t.setEventHandler { [weak self] in self?.runOnce() }
        t.resume()
        timer = t
    }

    // MARK: - 한 번 확인

    private func runOnce() {
        // 처음 한 번은 저장소에 있는 결과 파일로 마지막 결과를 이어받는다(앱을 다시 켜도 같은 요청을 또 처리하지 않게)
        if !seeded {
            switch readRepoFile(config.statusPath) {
            case .found(let data):
                lastWritten = decodeThemeStatus(data)
                lastResult = lastWritten?.last
            case .missing:
                break
            case .failed:
                return // GitHub 에 닿지 않으면 다음 확인 때 다시
            }
            seeded = true
        }

        guard let plugins = pluginList() else { return }
        var state = themeState(plugins, marketplace: config.marketplace)

        if case .found(let data) = readRepoFile(config.requestPath),
           let request = decodeThemeRequest(data), !isHandled(request, last: lastResult) {
            let result = apply(request, state: state)
            lastResult = result
            if !(result.applied && !result.reason.isEmpty) { notify(result) }
            if let fresh = pluginList() { state = themeState(fresh, marketplace: config.marketplace) }
        }

        let status = ThemeStatus(current: state.current, installed: state.installed, last: lastResult)
        if shouldWriteStatus(status, previous: lastWritten), writeRepoFile(config.statusPath, encodeThemeStatus(status)) {
            lastWritten = status
        }
    }

    /// 요청을 적용하고 결과를 돌려준다
    private func apply(_ request: ThemeRequest, state: ThemeState) -> ThemeResult {
        var market = loadMarketplace()
        if !market.contains(where: { $0.name == request.theme }) {
            // 새로 생긴 테마일 수 있다. 목록을 받아 와서 한 번 더 본다
            _ = run(claude, ["plugin", "marketplace", "update", config.marketplace])
            market = loadMarketplace()
        }
        let action = decideThemeAction(request, state: state, market: market)
        // 결과에는 처리한 요청의 시각을 남긴다(isHandled 가 이 값으로 같은 요청인지 본다)
        let result = { (applied: Bool, reason: String) in
            ThemeResult(theme: request.theme, applied: applied, reason: reason, at: Date(), requestedAt: request.requestedAt)
        }
        let fail = { (reason: String) in result(false, reason) }

        switch action {
        case .nothing:
            // 이미 켜져 있다. 결과는 남겨야 웹이 "기다리는 중"에서 벗어난다. 알림은 띄우지 않는다(reason 이 있으면 안 띄움)
            return result(true, "이미 켜져 있어요")
        case .reject(let reason):
            return fail(reason)
        case .enable(let name, let disable):
            for other in disable { _ = plugin(["disable", other]) }
            guard plugin(["enable", name]) else {
                restore(disable)
                return fail("테마를 켜지 못했어요 (claude plugin enable 실패)")
            }
        case .install(let entry, let disable):
            if let problem = verifyAndInstall(entry, disable: disable) {
                restore(disable)
                return fail(problem)
            }
        }
        let after = pluginList().map { themeState($0, marketplace: config.marketplace) }
        guard after?.enabled == [request.theme] else {
            // 아무 테마도 안 켜진 채로 두지 않는다. 요청한 테마를 끄고 원래 테마를 다시 켠다
            if state.current != request.theme { _ = plugin(["disable", request.theme]) }
            restore(state.enabled)
            return fail("바꾼 뒤 켜진 테마가 요청과 달라서 원래 테마로 되돌렸어요")
        }
        return result(true, "")
    }

    /// zip 지문과 파일 검사를 통과해야 설치한다. 설치된 복사본도 검사한 파일과 같은지 다시 본다. 문제가 있으면 이유를 돌려준다
    private func verifyAndInstall(_ entry: MarketEntry, disable: [String]) -> String? {
        guard let zip = download(entry.url) else { return "테마 파일을 받지 못했어요 (또는 5MB 보다 커요)" }
        guard sha256Hex(zip) == entry.sha256 else { return "SHA-256 이 테마 목록의 값과 달라요" }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("claude-theme-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let zipURL = work.appendingPathComponent("theme.zip")
        let dir = work.appendingPathComponent("x")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try zip.write(to: zipURL)
        } catch {
            return "임시 폴더를 만들지 못했어요"
        }
        guard run("/usr/bin/ditto", ["-x", "-k", zipURL.path, dir.path]).code == 0 else { return "테마 파일을 풀지 못했어요" }
        guard let files = readThemeTree(dir) else { return "테마에 링크나 읽을 수 없는 파일이 있어요" }
        if let problem = inspectTheme(files).first { return "안전 검사에 걸렸어요: \(problem)" }

        for other in disable { _ = plugin(["disable", other]) }
        guard plugin(["install", entry.name]) else { return "테마를 설치하지 못했어요 (claude plugin install 실패)" }

        // 설치된 복사본이 검사한 파일과 다르면 지운다(받은 사이 바뀌었을 수 있다)
        let id = "\(entry.name)@\(config.marketplace)"
        let installPath = pluginListRaw()?.first { ($0["id"] as? String) == id }?["installPath"] as? String
        let installed = installPath.flatMap { readThemeTree(URL(fileURLWithPath: $0)) }
        guard installed == files else {
            _ = plugin(["uninstall", entry.name])
            return "설치된 파일이 검사한 파일과 달라서 지웠어요"
        }
        return nil
    }

    /// 실패했을 때 꺼 두었던 테마를 다시 켠다
    private func restore(_ disabled: [String]) {
        for name in disabled { _ = plugin(["enable", name]) }
    }

    // MARK: - claude 명령

    private func plugin(_ args: [String]) -> Bool {
        guard args.count == 2, isThemeName(args[1]) else { return false }
        let id = "\(args[1])@\(config.marketplace)"
        return run(claude, ["plugin", args[0], id, "--scope", "user"]).code == 0
    }

    private func pluginListRaw() -> [[String: Any]]? {
        let r = run(claude, ["plugin", "list", "--json"])
        guard r.code == 0 else { return nil }
        return (try? JSONSerialization.jsonObject(with: r.out)) as? [[String: Any]]
    }

    private func pluginList() -> [InstalledPlugin]? {
        let r = run(claude, ["plugin", "list", "--json"])
        return r.code == 0 ? decodePluginList(r.out) : nil
    }

    private func loadMarketplace() -> [MarketEntry] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/plugins/marketplaces/\(config.marketplace)/.claude-plugin/marketplace.json")
        return (try? Data(contentsOf: url)).flatMap(decodeMarketplace) ?? []
    }

    // MARK: - GitHub (gh 명령)

    private enum RepoRead {
        case found(Data)
        case missing
        case failed
    }

    private func readRepoFile(_ path: String) -> RepoRead {
        let r = run(gh, ["api", "repos/\(config.repo)/contents/\(path)", "-H", "Accept: application/vnd.github.raw"])
        if r.code == 0 { return .found(r.out) }
        // gh 는 "gh: Not Found (HTTP 404)" 처럼 알린다. 숫자 404 만 보고 판단하지 않는다(리뷰 11-26)
        return String(decoding: r.err, as: UTF8.self).contains("(HTTP 404)") ? .missing : .failed
    }

    private func writeRepoFile(_ path: String, _ data: Data) -> Bool {
        let shaRun = run(gh, ["api", "repos/\(config.repo)/contents/\(path)", "--jq", ".sha"])
        let sha = shaRun.code == 0 ? String(decoding: shaRun.out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : nil
        // 본문은 명령 인자가 아니라 표준 입력으로 넘긴다(긴 내용이 인자 길이 한도를 넘지 않게, 리뷰 11-26)
        var body: [String: Any] = ["message": "테마 결과: \(lastResult?.theme ?? "상태")", "content": data.base64EncodedString()]
        if let sha, !sha.isEmpty { body["sha"] = sha }
        guard let json = try? JSONSerialization.data(withJSONObject: body) else { return false }
        let r = run(gh, ["api", "-X", "PUT", "repos/\(config.repo)/contents/\(path)", "--input", "-"], input: json)
        if r.code != 0 { NSLog("[theme] 결과 파일을 쓰지 못했어요: %@", String(decoding: r.err, as: UTF8.self)) }
        return r.code == 0
    }

    // MARK: - 도우미

    /// 테마 zip 은 가장 큰 것도 0.3MB 쯤이다(11-26). 그보다 훨씬 큰 파일은 받지 않는다
    private static let maxZipBytes = 5_000_000

    private func download(_ url: URL) -> Data? {
        let done = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: url) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count <= Self.maxZipBytes { result = data }
            done.signal()
        }.resume()
        return done.wait(timeout: .now() + 60) == .success ? result : nil
    }

    /// 명령을 실행한다. 두 출력 파이프를 동시에 비우고(한쪽이 차서 멈추지 않게), 2분이 지나면 끝낸다(리뷰 11-26)
    private func run(_ exe: String, _ args: [String], input: Data? = nil) -> (code: Int32, out: Data, err: Data) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(env["PATH"] ?? "")"
        p.environment = env
        let out = Pipe(), err = Pipe(), inPipe = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = input == nil ? FileHandle.nullDevice : inPipe
        do { try p.run() } catch { return (-1, Data(), Data()) }

        let group = DispatchGroup()
        var outData = Data(), errData = Data()
        for (pipe, isOut) in [(out, true), (err, false)] {
            group.enter()
            DispatchQueue.global().async {
                let d = pipe.fileHandleForReading.readDataToEndOfFile()
                if isOut { outData = d } else { errData = d }
                group.leave()
            }
        }
        if let input {
            inPipe.fileHandleForWriting.write(input)
            try? inPipe.fileHandleForWriting.close()
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: killer)
        p.waitUntilExit()
        killer.cancel()
        group.wait()
        return (p.terminationStatus, outData, errData)
    }

    // MARK: - 맥 알림

    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    private func requestNotificationPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ result: ThemeResult) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        if result.applied {
            content.title = isKorean ? "Claude 테마를 \(result.theme) 로 바꿨어요" : "Claude theme changed to \(result.theme)"
            content.body = isKorean ? "새 세션을 열거나 /reload-plugins 를 하면 보여요" : "Open a new session or run /reload-plugins to see it"
        } else {
            content.title = isKorean ? "Claude 테마를 바꾸지 못했어요" : "Could not change the Claude theme"
            content.body = result.reason
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
