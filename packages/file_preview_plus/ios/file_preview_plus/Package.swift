// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "file_preview_plus",
    platforms: [
        .iOS("13.0"),
    ],
    products: [
        .library(name: "file-preview-plus", targets: ["file_preview_plus"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "file_preview_plus",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ]
        ),
    ]
)
