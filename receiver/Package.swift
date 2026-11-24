// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "truckpad-receiver",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "truckpad-receiver", path: "Sources/truckpad-receiver")
    ]
)
