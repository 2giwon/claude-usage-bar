import Foundation
import UsageBarCore

// ~/.claude/claude-usage-bar.json 을 2초마다 확인해서 바뀌었으면 다시 읽는다.
// 파일 감시(DispatchSource)는 파일을 통째로 바꿔 쓰면 끊겨서, 수정 시각을 보는 방식으로 한다
final class UsageStore: ObservableObject {
    enum Load: Equatable {
        case missing          // 파일이 아직 없음
        case failed           // 파일이 깨짐 (한 번도 제대로 읽은 적이 없을 때만)
        case loaded(Snapshot)
    }

    @Published private(set) var load: Load
    @Published private(set) var now: Date

    let fileURL: URL
    private var lastModified: Date?
    private var timer: Timer?

    init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/claude-usage-bar.json"),
        load: Load = .missing,
        now: Date = Date()
    ) {
        self.fileURL = fileURL
        self.load = load
        self.now = now
    }

    func start() {
        reload(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.reload(force: false)
        }
    }

    func reload(force: Bool) {
        now = Date()
        let modified = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
        guard let modified else {
            if case .loaded = load { return }
            load = .missing
            return
        }
        if !force, modified == lastModified { return }
        lastModified = modified

        if let data = try? Data(contentsOf: fileURL), let snapshot = decodeSnapshot(data) {
            load = .loaded(snapshot)
        } else if case .loaded = load {
            // 쓰는 도중에 읽었을 수 있다. 마지막 정상 값을 두고 다음 확인 때 다시 읽는다
            lastModified = nil
        } else {
            load = .failed
        }
    }
}
