// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchCRTV",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "NotchCore",
            path: "Sources/NotchCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "NotchCRTV",
            dependencies: ["NotchCore"],
            path: "Sources/NotchCRTV",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Testes de lógica sem XCTest: swift run SelfTest
        .executableTarget(
            name: "SelfTest",
            dependencies: ["NotchCore"],
            path: "Sources/SelfTest",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
