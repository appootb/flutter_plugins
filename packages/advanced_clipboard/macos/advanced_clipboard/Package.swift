// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "advanced_clipboard",
    platforms: [
        .macOS("10.15"),
    ],
    products: [
        .library(name: "advanced-clipboard", targets: ["advanced_clipboard"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "advanced_clipboard",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ]
        ),
    ]
)
