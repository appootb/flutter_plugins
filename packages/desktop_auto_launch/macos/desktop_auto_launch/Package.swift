// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "desktop_auto_launch",
    platforms: [
        .macOS("10.15"),
    ],
    products: [
        .library(name: "desktop-auto-launch", targets: ["desktop_auto_launch"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "desktop_auto_launch",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ]
        ),
    ]
)
