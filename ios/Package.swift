// swift-tools-version:5.9
//
// IDE indexing manifest for the locus iOS module.
//
// The actual iOS build for the plugin is driven by `locus.podspec` via
// CocoaPods. This SwiftPM manifest exists purely so SourceKit-LSP and other
// IDE indexers can resolve internal types (StorageManager, ConfigManager,
// GzipEncoder, ...) when individual files are opened standalone outside an
// Xcode workspace.
//
// Flutter's SwiftPM auto-detection looks at `ios/<plugin_name>/Package.swift`
// (nested), so this top-level manifest is invisible to `flutter build ios` —
// CocoaPods stays the canonical build path.
//
// Files that import the `Flutter` framework are excluded because Flutter is
// provided as a binary dependency through CocoaPods, not SwiftPM. Excluding
// them keeps this SwiftPM target compilable for indexing without affecting
// the CocoaPods build coverage.

import PackageDescription

let package = Package(
    name: "Locus",
    platforms: [.iOS(.v14), .macOS(.v10_14)],
    products: [
        .library(name: "Locus", targets: ["Locus"]),
    ],
    targets: [
        .target(
            name: "Locus",
            path: "Classes",
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
            dependencies: ["Locus"],
            path: "Tests"
        ),
    ]
)
