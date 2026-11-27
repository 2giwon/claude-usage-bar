import AppKit
import Foundation
import UserNotifications
import UsageBarCore

// 세션 현황판 데이터. 2초마다 상태 폴더(~/.claude/session-board)와 데스크탑 앱 세션 폴더를 읽어 목록을 만든다
final class SessionStore: NSObject, ObservableObject {
    enum Load: Equatable {
        case loading               // 처음 읽기 전
        case hidden                // 상태 폴더가 없음: 훅을 설치하지 않았으니 세션 카드를 숨긴다
        case failed                // 상태 폴더를 못 읽음
        case loaded([BoardRow])
    }

    @Published private(set) var load: Load
    @Published private(set) var now: Date
    // 세션 열기에 실패한 줄. 잠깐 "세션을 열지 못했어요" 를 보여 준다
    @Published private(set) var openFailedId: String?

    private let statusFolder: URL
    private let appRoot: URL
    private var timer: Timer?
    // 앱 세션 파일은 150KB 안팎이라 2초마다 전부 읽지 않는다. 수정 시각이 바뀐 파일만 다시 읽는다
    private var appCache: [URL: (modified: Date, session: AppSession?)] = [:]
    private var notified = Set<String>()
    private var askedPermission = false

    init(
        statusFolder: URL = SessionHook.folder,
        appRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions"),
        load: Load = .loading,
        now: Date = Date()
    ) {
        self.statusFolder = statusFolder
        self.appRoot = appRoot
        self.load = load
        self.now = now
    }

    var waitingCount: Int {
        guard case let .loaded(rows) = load else { return 0 }
        return rows.filter { $0.kind == .waiting }.count
    }

    func start() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.reload()
        }
        if canNotify { UNUserNotificationCenter.current().delegate = self }
    }

    func reload() {
        now = Date()
        switch readStatusFolder(statusFolder) {
        case .missing:
            load = .hidden
        case .unreadable:
            load = .failed
        case let .statuses(statuses):
            let rows = buildBoard(statuses: statuses, sessions: readAppSessions(),
                                  transcriptModified: transcriptTimes(statuses), now: now)
            if load != .loaded(rows) { load = .loaded(rows) }
            notifyIfNeeded(rows)
            uploadIfNeeded(rows)
        }
    }

    // ===== 다른 화면(작업노트)으로 올리기 =====
    // ~/.claude/claude-usage-bar-board.json 이 있을 때만 켜진다. 없으면 아무 일도 하지 않는다

    // 설정 파일이 있는데 마지막 올리기가 실패했으면 true. 세션 카드 아래에 한 줄로 알린다
    @Published private(set) var uploadFailed = false
    private var lastUpload: UploadAttempt?
    private var uploading = false
    private let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/claude-usage-bar-board.json")

    private func uploadIfNeeded(_ rows: [BoardRow]) {
        guard !uploading,
              let data = try? Data(contentsOf: configURL),
              let config = decodeBoardConfig(data)
        else {
            if uploadFailed, (try? Data(contentsOf: configURL)) == nil { uploadFailed = false }
            return
        }
        let payload = encodeBoardUpload(rows)
        guard shouldUpload(payload, last: lastUpload, now: now) else { return }

        var request = URLRequest(url: config.url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.key)", forHTTPHeaderField: "Authorization")
        request.httpBody = payload
        uploading = true
        let startedAt = now
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            // 받는 쪽이 201, 204 처럼 다른 성공 번호를 줄 수도 있어서 200번대는 모두 성공으로 본다(codex P2)
            let ok = error == nil && (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0)
            DispatchQueue.main.async {
                guard let self else { return }
                self.uploading = false
                self.lastUpload = UploadAttempt(payload: payload, at: startedAt, ok: ok)
                if self.uploadFailed != !ok { self.uploadFailed = !ok }
            }
        }.resume()
    }

    func open(_ row: BoardRow) {
        guard let link = row.link, NSWorkspace.shared.open(link) else {
            openFailedId = row.localId
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                if self?.openFailedId == row.localId { self?.openFailedId = nil }
            }
            return
        }
    }

    // <계정>/<조직>/local_*.json 을 읽는다.
    // 폴더가 없거나, 파일은 있는데 하나도 못 읽으면 nil(앱 형식이 바뀐 것으로 본다)
    private func readAppSessions() -> [AppSession]? {
        let manager = FileManager.default
        guard let accounts = try? manager.contentsOfDirectory(at: appRoot, includingPropertiesForKeys: nil) else {
            return nil
        }
        var files: [URL] = []
        // 안쪽 폴더 하나라도 못 읽으면 일부 세션이 "짝 없음"으로 사라지므로, 앱 형식이 바뀐 것과 같이 nil 로 본다
        for account in accounts where isDirectory(account) {
            guard let orgs = try? manager.contentsOfDirectory(at: account, includingPropertiesForKeys: nil) else {
                return nil
            }
            for org in orgs where isDirectory(org) {
                guard let items = try? manager.contentsOfDirectory(at: org, includingPropertiesForKeys: nil) else {
                    return nil
                }
                files += items.filter { $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json" }
            }
        }

        var sessions: [AppSession] = []
        var next: [URL: (modified: Date, session: AppSession?)] = [:]
        for file in files {
            let modified = (try? manager.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date ?? .distantPast
            if let cached = appCache[file], cached.modified == modified, cached.session != nil {
                next[file] = cached
                sessions.append(cached.session!)
                continue
            }
            if let session = (try? Data(contentsOf: file)).flatMap(decodeAppSession) {
                next[file] = (modified, session)
                sessions.append(session)
            } else if let previous = appCache[file]?.session {
                // 앱이 파일을 쓰는 도중에 읽었을 수 있다. 마지막으로 읽은 값을 쓰고, 수정 시각은 비워 다음에 다시 읽는다(codex P2)
                next[file] = (.distantPast, previous)
                sessions.append(previous)
            } else {
                next[file] = (.distantPast, nil)
            }
        }
        appCache = next
        if !files.isEmpty, sessions.isEmpty { return nil }
        return sessions
    }

    // 폴더 안에 일반 파일(.DS_Store, mod-commands.json 등)도 있어서, 폴더만 골라 들어간다
    private func isDirectory(_ url: URL) -> Bool {
        var flag: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }

    // 답 기다림, 일하는 중인 세션만 대화 기록 파일 수정 시각을 본다
    // (권한을 허락한 뒤 다시 일하는지, 30분 넘게 멈춘 버려진 턴인지 알려고)
    private func transcriptTimes(_ statuses: [SessionStatus]) -> [String: Date] {
        var times: [String: Date] = [:]
        for status in statuses where status.state != .idle {
            guard let path = status.transcriptPath,
                  let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            else { continue }
            times[status.sessionId] = modified
        }
        return times
    }

    // ===== 10분 알림 =====

    // swift run 처럼 앱 묶음(.app) 없이 돌리면 알림 센터가 멈추므로 앱 묶음일 때만 쓴다
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    private func notifyIfNeeded(_ rows: [BoardRow]) {
        let due = alertsDue(rows, notified: notified, now: now)
        guard !due.isEmpty, canNotify else { return }
        for alert in due { notified.insert(alert.key) }

        let center = UNUserNotificationCenter.current()
        let send = {
            for alert in due {
                let content = UNMutableNotificationContent()
                content.title = Words.strings.boardAlertTitle
                content.body = Words.strings.boardAlertBody(alert.row.title)
                if let link = alert.row.link { content.userInfo = ["link": link.absoluteString] }
                center.add(UNNotificationRequest(identifier: alert.key, content: content, trigger: nil))
            }
        }
        if askedPermission {
            send()
        } else {
            askedPermission = true
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if granted { send() }
            }
        }
    }
}

extension SessionStore: UNUserNotificationCenterDelegate {
    // 알림을 누르면 그 세션을 연다
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let text = response.notification.request.content.userInfo["link"] as? String,
           let link = URL(string: text) {
            DispatchQueue.main.async { NSWorkspace.shared.open(link) }
        }
        completionHandler()
    }

    // 메뉴 막대 앱이 앞에 있어도 알림을 보여 준다
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
