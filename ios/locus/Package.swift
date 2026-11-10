// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "locus",
    platforms: [
        .iOS("14.0"),
    ],
    products: [
        .library(name: "locus", targets: ["locus"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "LocusSQLCipher",
            exclude: ["vendor", "LICENSE.md", "README.md"],
            publicHeadersPath: "include",
            cSettings: [.define("NDEBUG", to: "1")],
            linkerSettings: [.linkedFramework("Security"), .linkedFramework("Foundation")]
        ),
        .target(
            name: "locus",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "LocusSQLCipher",
            ],
            exclude: [
                "LocusPlugin.h",
                "LocusPlugin.m",
            ],
            swiftSettings: [
                .define("LOCUS_SWIFT_PACKAGE"),
            ]
        ),
    ]
)
