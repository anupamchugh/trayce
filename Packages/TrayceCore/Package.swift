// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TrayceCore",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [.library(name: "TrayceCore", targets: ["TrayceCore"])],
    targets: [
        .target(name: "TrayceCore", resources: [.process("Resources")]),
        .testTarget(name: "TrayceCoreTests", dependencies: ["TrayceCore"]),
    ]
)
