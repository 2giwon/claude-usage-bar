// swift-tools-version: 5.10
import PackageDescription

// Claude Usage Bar: Claude 사용량을 보여 주는 맥 메뉴 막대 앱.
// UsageBarCore: 화면 없는 계산 함수, UsageBarChecks: 계산 함수 검사(Xcode 없이 쓰는 테스트 대용),
// ClaudeUsageBar: 메뉴 막대 앱 화면
let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "UsageBarCore"),
        .executableTarget(name: "UsageBarChecks", dependencies: ["UsageBarCore"]),
        .executableTarget(name: "ClaudeUsageBar", dependencies: ["UsageBarCore"]),
    ]
)
