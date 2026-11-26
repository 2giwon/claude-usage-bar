import AppKit
import SwiftUI

// 앱 아이콘 (시안 B: 5시간 링과 주간 막대, 기준선).
// 1024 크기 캔버스에 그린다. 맥 아이콘 규칙대로 둘레에 100 만큼 여백을 두고 둥근 사각형을 그린다
struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(Color(red: 0.11, green: 0.12, blue: 0.15))
                .frame(width: 824, height: 824)

            // 5시간 링: 65% 채움
            ZStack {
                Circle().stroke(Color(red: 0.23, green: 0.24, blue: 0.28), lineWidth: 80)
                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(Palette.normal, style: StrokeStyle(lineWidth: 80, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 448, height: 448)
            .offset(y: -48)

            // 주간 막대와 기준선
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 0.23, green: 0.24, blue: 0.28))
                    .frame(width: 544, height: 64)
                Capsule().fill(Palette.weekly)
                    .frame(width: 240, height: 64)
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.91, green: 0.91, blue: 0.92))
                    .frame(width: 24, height: 128)
                    .offset(x: 288)
            }
            .frame(width: 544, height: 128)
            .offset(y: 296)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
enum AppIcon {
    // iconutil 이 요구하는 이름과 크기
    static let sizes: [(name: String, pixels: CGFloat)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    static func renderIconset(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for size in sizes {
            let renderer = ImageRenderer(content: AppIconView())
            renderer.scale = size.pixels / 1024
            guard let cgImage = renderer.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: folder.appendingPathComponent("\(size.name).png"))
        }
        print("icon rendered to \(folder.path)")
    }
}
