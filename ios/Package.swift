// swift-tools-version:5.9
//
// IDE indexing manifest for the locus iOS module.
//
// This top-level SwiftPM manifest exists so native helper tests and IDE
// indexers can resolve internal types (StorageManager, ConfigManager,
// GzipEncoder, ...) without a Flutter host project.
//
// Flutter's build integration uses the nested `ios/locus/Package.swift`. This
// top-level manifest remains intentionally separate because it provides a
// Flutter-free package for native helper tests and editor indexing.
//
// Files that import the `Flutter` framework are excluded because this helper
// package intentionally has no Flutter dependency. Production Flutter builds
// compile the complete source set through either `locus.podspec` or the nested
// `ios/locus/Package.swift`.

import Foundation
import PackageDescription

// CocoaPods and Flutter's nested Swift package expose this source tree as the
// lowercase `locus` module. Keep `Locus` as the default for compatibility with
// existing standalone users of this helper manifest, while allowing CI to
// compile the same tests against the production module identity as well.
let nativeModuleName = ProcessInfo.processInfo.environment["LOCUS_NATIVE_TEST_MODULE"] ?? "Locus"

let package = Package(
    name: "Locus",
    platforms: [.iOS(.v14), .macOS(.v10_15)],
    products: [
        .library(name: "Locus", targets: [nativeModuleName]),
    ],
    targets: [
        .target(
            name: "LocusSQLCipher",
            path: "locus/Sources/LocusSQLCipher",
            exclude: ["vendor", "LICENSE.md", "README.md"],
            publicHeadersPath: "include",
            cSettings: [.define("NDEBUG", to: "1")],
            linkerSettings: [.linkedFramework("Security"), .linkedFramework("Foundation")]
        ),
        .target(
            name: nativeModuleName,
            dependencies: ["LocusSQLCipher"],
            path: "locus/Sources/locus",
            exclude: [
                "LocusPlugin.h",
                "LocusPlugin.m",
                "SwiftLocusPlugin.swift",
                "SwiftLocusPlugin+Background.swift",
                "SwiftLocusPlugin+Delegates.swift",
                "SwiftLocusPlugin+Events.swift",
                "SwiftLocusPlugin+Logging.swift",
                "Core/LocationClient.swift",
                "Motion/MotionManager.swift",
                "Core/HeadlessHeadersDispatcher.swift",
                "Core/HeadlessValidationDispatcher.swift",
            ]
        ),
        .testTarget(
            name: "LocusTests",
            dependencies: [.target(name: nativeModuleName)],
            path: "Tests"
        ),
    ]
)
