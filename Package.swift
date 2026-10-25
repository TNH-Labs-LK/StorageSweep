// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StorageSweep",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "StorageSweep",
            path: "Sources/StorageSweep"
        )
    ]
)
