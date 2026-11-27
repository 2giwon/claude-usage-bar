import SwiftUI
import UsageBarCore

// 펼침 화면의 "세션" 카드: 데스크탑 앱 세션이 지금 무엇을 하는지. 줄을 누르면 그 세션을 연다
struct SessionCard: View {
    @ObservedObject var sessions: SessionStore

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Words.strings.boardTitle).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if sessions.waitingCount > 0 {
                        Text("\(Words.strings.boardWaiting) \(sessions.waitingCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.warning)
                    }
                }
                content
                if sessions.uploadFailed {
                    note("icloud.slash", Words.strings.boardUploadFailed)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch sessions.load {
        case .loading, .hidden:
            // 처음 읽기 전: 회색 줄 3개로 자리를 잡아 둔다(값이 와도 화면이 밀리지 않게)
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6).fill(Palette.track).frame(height: 30)
                }
            }
        case .failed:
            note("exclamationmark.triangle", Words.strings.boardFailed)
        case let .loaded(rows) where rows.isEmpty:
            note("moon.zzz", Words.strings.boardEmpty)
        case let .loaded(rows) where rows.count <= 6:
            list(rows)
        case let .loaded(rows):
            // 7줄부터는 펼침 화면이 너무 길어지지 않게 스크롤한다
            ScrollView { list(rows) }.frame(height: 280)
        }
    }

    private func list(_ rows: [BoardRow]) -> some View {
        VStack(spacing: 2) {
            ForEach(rows, id: \.localId) { row in
                SessionRow(row: row, now: sessions.now, isOpenFailed: sessions.openFailedId == row.localId) {
                    sessions.open(row)
                }
            }
        }
    }

    private func note(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}

struct SessionRow: View {
    var row: BoardRow
    var now: Date
    var isOpenFailed: Bool
    var action: () -> Void
    @StateObject private var state = PressState()

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8).padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if let line = secondLine {
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundStyle(isOpenFailed ? Palette.warning : .secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(kindText).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
                    Text(Words.since(row.since, now: now))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(state.isHovering ? 0.07 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(row.link == nil)
        .onHover { state.isHovering = $0 && row.link != nil }
        .help(row.link == nil ? Words.strings.boardTitleMissing : Words.strings.boardOpenHelp)
    }

    private var secondLine: String? {
        if isOpenFailed { return Words.strings.boardOpenFailed }
        if row.isTitleMissing { return Words.strings.boardTitleMissing }
        return Words.strings.boardActivity(row.activity) ?? row.detail
    }

    private var color: Color {
        switch row.kind {
        case .waiting: return Palette.warning
        case .working: return Palette.normal
        case .review: return Palette.weekly
        case .done: return Palette.idle
        }
    }

    private var kindText: String {
        switch row.kind {
        case .waiting: return Words.strings.boardWaiting
        case .working: return Words.strings.boardWorking
        case .review: return Words.strings.boardReview
        case .done: return Words.strings.boardDone
        }
    }
}
