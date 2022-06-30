// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "mousemove",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "mousemove", targets: ["mousemove"])],
    dependencies: [],
    targets: [.executableTarget(name: "mousemove", dependencies: [])]
)

