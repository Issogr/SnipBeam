// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SnipBeam",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SnipBeam", targets: ["SnipBeam"])],
    targets: [.executableTarget(name: "SnipBeam")]
)
