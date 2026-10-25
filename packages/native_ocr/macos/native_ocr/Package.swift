// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "native_ocr",
    platforms: [
        .macOS("10.15"),
    ],
    products: [
        .library(name: "native-ocr", targets: ["native_ocr"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "native_ocr",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ]
        ),
    ]
)
