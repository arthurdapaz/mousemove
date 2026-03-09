// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "mousemove",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "mousemove", targets: ["mousemove"])],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "mousemove",
            dependencies: []
        ),
        .testTarget(
            name: "mousemoveTests",
            dependencies: ["mousemove"]
        )
    ]
)
