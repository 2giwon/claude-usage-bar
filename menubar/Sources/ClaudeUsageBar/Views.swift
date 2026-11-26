import SwiftUI
import UsageBarCore

// 색: 평소 초록, 경고 주황, 주간 파랑, 컨텍스트 보라, 값 없음 회색
enum Palette {
    static let normal = Color(red: 0.11, green: 0.62, blue: 0.46)
    static let warning = Color(red: 0.94, green: 0.62, blue: 0.15)
    static let weekly = Color(red: 0.22, green: 0.54, blue: 0.87)
    static let context = Color(red: 0.50, green: 0.47, blue: 0.87)
    static let track = Color.primary.opacity(0.08)
    static let idle = Color.secondary.opacity(0.5)

    static func color(for percent: Double) -> Color {
        level(percent: percent) == .warning ? warning : normal
    }
}

// 원형 게이지. percent 가 nil 이면 점선 회색 링(값 없음)
struct Ring: View {
    var percent: Double?
    var lineWidth: CGFloat
    var color: Color
    var track: Color = Palette.track

    var body: some View {
        ZStack {
            if let percent {
                Circle().stroke(track, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, percent / 100)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle().stroke(Palette.idle, style: StrokeStyle(lineWidth: lineWidth, dash: [3, 3]))
            }
        }
        .padding(lineWidth / 2)
    }
}

// 가로 막대. marker 가 있으면 그 위치에 기준선을 세운다
struct Bar: View {
    var percent: Double?
    var color: Color
    var marker: Double? = nil
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                if let percent, percent > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(height, proxy.size.width * min(1, percent / 100)))
                }
                if let marker {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary)
                        .frame(width: 2, height: height + 8)
                        .offset(x: proxy.size.width * min(1, marker / 100) - 1)
                }
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
        }
        .frame(height: height + 8)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

// 메뉴 막대에 들어가는 링 아이콘과 숫자
struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarIcon.image(percent: menuPercent, isDim: isDim))
            Text(menuText)
                .monospacedDigit()
        }
    }

    private var fiveHour: WindowView? {
        guard case let .loaded(snapshot) = store.load,
              let limit = snapshot.limits.first(where: { $0.kind == "five_hour" })
        else { return nil }
        return windowView(limit, now: store.now)
    }

    private var isDim: Bool {
        guard case let .loaded(snapshot) = store.load else { return true }
        return isStale(updatedAt: snapshot.updatedAt, now: store.now)
    }

    private var menuPercent: Double? { fiveHour?.percent }

    private var menuText: String {
        switch store.load {
        case .failed: return "!"
        case .missing: return "—"
        case .loaded: return fiveHour.map { Words.percent($0.percent) } ?? "—"
        }
    }
}

enum MenuBarIcon {
    // 메뉴 막대용 18pt 링을 그림으로 만든다. 메뉴 막대는 SwiftUI 도형을 직접 그리지 못해서 그림으로 바꾼다
    @MainActor
    static func image(percent: Double?, isDim: Bool) -> NSImage {
        let color = percent.map { Palette.color(for: $0) } ?? Palette.idle
        // 메뉴 막대는 밝을 수도 어두울 수도 있어서, 어느 쪽에서도 보이는 중간 회색을 바탕으로 쓴다
        let ring = Ring(percent: percent, lineWidth: 3, color: color, track: Color.gray.opacity(0.45))
            .frame(width: 16, height: 16)
            .opacity(isDim ? 0.45 : 1)
            .padding(1)
        let renderer = ImageRenderer(content: ring)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = false
        return image
    }
}

// 메뉴 막대 아이콘을 누르면 펼쳐지는 화면
struct PopoverView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            switch store.load {
            case .missing:
                FiveHourCard(view: nil, now: store.now, isDim: true)
                notice(icon: "hourglass", text: Words.strings.emptyNotice)
            case .failed:
                notice(icon: "exclamationmark.triangle", text: Words.strings.failedNotice)
            case let .loaded(snapshot):
                loaded(snapshot)
            }
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    @ViewBuilder
    private func loaded(_ snapshot: Snapshot) -> some View {
        let isDim = isStale(updatedAt: snapshot.updatedAt, now: store.now)
        let five = snapshot.limits.first { $0.kind == "five_hour" }
        let week = snapshot.limits.first { $0.kind == "seven_day" }

        if five == nil, week == nil {
            notice(icon: "person.crop.circle.badge.questionmark", text: Words.strings.noPlanNotice)
        } else {
            if let five {
                FiveHourCard(view: windowView(five, now: store.now), now: store.now, isDim: isDim)
            }
            if let week {
                WeeklyCard(view: windowView(week, now: store.now), now: store.now, isDim: isDim)
            }
        }
        if let context = snapshot.context, let percent = context.percent {
            ContextCard(percent: percent, context: context, session: snapshot.session)
        }
    }

    private var header: some View {
        HStack {
            Text(Words.strings.title).font(.system(size: 15, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(liveColor).frame(width: 7, height: 7)
                Text(updatedText).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var liveColor: Color {
        guard case let .loaded(snapshot) = store.load,
              !isStale(updatedAt: snapshot.updatedAt, now: store.now)
        else { return Palette.idle }
        return Palette.normal
    }

    private var updatedText: String {
        guard case let .loaded(snapshot) = store.load else { return Words.strings.waiting }
        return Words.updated(
            snapshot.updatedAt,
            now: store.now,
            isStale: isStale(updatedAt: snapshot.updatedAt, now: store.now)
        )
    }

    private func notice(icon: String, text: String) -> some View {
        Card {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(.secondary)
                Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(Words.strings.footer).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            RefreshButton { store.reload(force: true) }
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(Words.strings.quit, systemImage: "power")
            }
            .buttonStyle(FooterButtonStyle())
            .help(Words.strings.quitHelp)
        }
        .padding(.top, 4)
        .overlay(alignment: .top) { Divider().offset(y: -6) }
    }
}

// 새로 읽기 버튼. 값이 그대로여도 눌린 걸 알 수 있게 아이콘이 한 바퀴 돌고 잠깐 "다시 읽었어요"로 바뀐다
// 버튼 상태는 @StateObject 로 들고 있다. 명령줄 도구(Xcode 없음)에는 @State 매크로 부품이 없어서 빌드되지 않는다
final class PressState: ObservableObject {
    @Published var turns = 0.0
    @Published var isDone = false
    @Published var isHovering = false
}

struct RefreshButton: View {
    var action: () -> Void
    @StateObject private var state = PressState()

    var body: some View {
        Button {
            action()
            withAnimation(.easeInOut(duration: 0.5)) { state.turns += 1 }
            state.isDone = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [state] in state.isDone = false }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: state.isDone ? "checkmark" : "arrow.clockwise")
                    .rotationEffect(.degrees(state.turns * 360))
                Text(state.isDone ? Words.strings.refreshed : Words.strings.refresh)
            }
        }
        .buttonStyle(FooterButtonStyle())
        .help(Words.strings.refreshHelp)
    }
}

// 아래쪽 작은 버튼: 평소에도 옅은 배경으로 버튼인 게 보이고,
// 마우스를 올리면 진해지고, 누르면 더 진해지면서 살짝 작아진다
struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FooterButtonBody(configuration: configuration)
    }
}

private struct FooterButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @StateObject private var state = PressState()

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(state.isHovering || configuration.isPressed ? Color.primary : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.18 : state.isHovering ? 0.11 : 0.05))
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: state.isHovering)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { state.isHovering = $0 }
    }
}

struct FiveHourCard: View {
    var view: WindowView?
    var now: Date
    var isDim: Bool

    var body: some View {
        Card {
            HStack(spacing: 16) {
                ZStack {
                    Ring(percent: view?.percent, lineWidth: 10, color: color)
                    Text(view.map { Words.percent($0.percent) } ?? "—")
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()
                }
                .frame(width: 96, height: 96)
                .opacity(isDim ? 0.55 : 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text(Words.strings.fiveHourTitle).font(.system(size: 14, weight: .semibold))
                    if let view, view.isReset {
                        caption("arrow.counterclockwise", Words.strings.resetDone)
                    } else if let reset = view?.resetsAt {
                        caption("clock", Words.resetClock(reset))
                        Bar(percent: elapsedPercent(until: reset), color: Color.secondary.opacity(0.6), height: 6)
                        Text(Words.remaining(until: reset, now: now))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    } else if view == nil {
                        caption("hourglass", Words.strings.showAfterResponse)
                    }
                }
            }
        }
    }

    private var color: Color {
        view.map { Palette.color(for: $0.percent) } ?? Palette.idle
    }

    // 5시간 중 지난 비율
    private func elapsedPercent(until reset: Date) -> Double {
        let window: TimeInterval = 5 * 60 * 60
        return min(100, max(0, (window - reset.timeIntervalSince(now)) / window * 100))
    }
}

struct WeeklyCard: View {
    var view: WindowView
    var now: Date
    var isDim: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Words.strings.weeklyTitle).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(Words.percent(view.percent))
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                }
                Bar(percent: view.percent, color: barColor, marker: baseline)
                    .opacity(isDim ? 0.55 : 1)
                if view.isReset {
                    caption("arrow.counterclockwise", Words.strings.resetDone)
                } else if let reset = view.resetsAt {
                    HStack {
                        Text(Words.resetDay(reset))
                        Spacer()
                        Text(Words.remaining(until: reset, now: now))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                if let baseline {
                    paceBadge(baseline: baseline)
                }
            }
        }
    }

    private var barColor: Color {
        level(percent: view.percent) == .warning ? Palette.warning : Palette.weekly
    }

    private var baseline: Double? {
        guard !view.isReset, let reset = view.resetsAt else { return nil }
        return weeklyBaseline(resetsAt: reset, now: now)
    }

    private func paceBadge(baseline: Double) -> some View {
        let isFast = pace(used: view.percent, baseline: baseline) == .fast
        let text = Words.strings.pace(isFast: isFast, baseline: Words.percent(baseline))
        let color = isFast ? Palette.warning : Palette.normal
        return HStack(spacing: 4) {
            Image(systemName: isFast ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
            Text(text)
        }
        .font(.system(size: 12))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.14)))
    }
}

struct ContextCard: View {
    var percent: Double
    var context: Context
    var session: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Words.strings.contextTitle).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(Words.percent(percent))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                }
                Bar(percent: percent, color: Palette.context)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String {
        let tokens = context.tokens.map { Words.tokens($0, of: context.window) }
        return [session.map { Words.strings.session($0) }, tokens].compactMap { $0 }.joined(separator: ", ")
    }
}

private func caption(_ icon: String, _ text: String) -> some View {
    HStack(spacing: 4) {
        Image(systemName: icon)
        Text(text)
    }
    .font(.system(size: 12))
    .foregroundStyle(.secondary)
}
