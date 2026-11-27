import Foundation

// 세션 목록을 다른 화면(작업노트 등)으로 올리기.
// ~/.claude/claude-usage-bar-board.json 설정 파일({ "url": "https://.../board", "key": "쓰기 열쇠" })이 있을 때만 켜진다.
// 올리는 곳은 POST <url> 에 Authorization: Bearer <key> 로 { rows: [...] } 를 받는 서버다
// (작업노트는 2giwon.github.io 저장소 worker/board.mjs). 작업 폴더 경로 같은 다른 값은 올리지 않는다

public let uploadRepeatSeconds: TimeInterval = 60  // 목록이 같아도 이만큼 지나면 다시 올린다(받는 쪽이 "맥 연결됨"을 알게)
public let uploadRetrySeconds: TimeInterval = 10   // 실패하면 이만큼 뒤에 다시

private struct UploadRow: Encodable {
    var id: String
    var title: String
    var kind: String
    var detail: String?
    var activity: String?
    var since: String
    var titleMissing: Bool
}

private struct UploadBody: Encodable {
    var rows: [UploadRow]
}

private func kindName(_ kind: BoardKind) -> String {
    switch kind {
    case .waiting: return "waiting"
    case .working: return "working"
    case .review: return "review"
    case .done: return "done"
    }
}

// 같은 목록이면 같은 글자가 나오게(바뀔 때만 올리려고) 칸 순서를 고정한다
public func encodeBoardUpload(_ rows: [BoardRow]) -> Data {
    let body = UploadBody(rows: rows.map {
        UploadRow(id: $0.localId, title: $0.title, kind: kindName($0.kind), detail: $0.detail,
                  activity: $0.activity, since: formatDate($0.since), titleMissing: $0.isTitleMissing)
    })
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(body)) ?? Data()
}

public struct UploadAttempt: Equatable {
    public var payload: Data
    public var at: Date
    public var ok: Bool

    public init(payload: Data, at: Date, ok: Bool) {
        self.payload = payload
        self.at = at
        self.ok = ok
    }
}

// 처음이면 올린다. 실패했으면 10초 뒤에 다시. 목록이 바뀌면 바로, 같으면 60초마다
public func shouldUpload(_ payload: Data, last: UploadAttempt?, now: Date) -> Bool {
    guard let last else { return true }
    let elapsed = now.timeIntervalSince(last.at)
    if !last.ok { return elapsed >= uploadRetrySeconds }
    if payload != last.payload { return true }
    return elapsed >= uploadRepeatSeconds
}

public struct BoardConfig: Equatable {
    public var url: URL
    public var key: String
}

private struct RawBoardConfig: Decodable {
    var url: String?
    var key: String?
}

// 열쇠가 그대로 지나가므로 https 주소만 받는다
public func decodeBoardConfig(_ data: Data) -> BoardConfig? {
    guard let raw = try? JSONDecoder().decode(RawBoardConfig.self, from: data),
          let text = raw.url, let url = URL(string: text), url.scheme == "https", url.host != nil,
          let key = raw.key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty
    else {
        return nil
    }
    return BoardConfig(url: url, key: key)
}
