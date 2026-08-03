// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "TacosMind",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AppCore", targets: ["AppCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/luizmb/FP.git", from: "2.2.0"),
        .package(url: "https://github.com/luizmb/Hourglass.git", from: "1.0.1"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.1"),
        .package(url: "https://github.com/SwiftRex/SwiftRex.git", branch: "main", traits: ["ReactiveConcurrency"]),
        .package(url: "https://github.com/luizmb/ReactiveConcurrency.git", from: "1.1.0"),
        .package(url: "https://github.com/luizmb/NetworkTools.git", from: "0.7.0"),
    ],
    targets: [
        .target(
            name: "GeneratorCore",
            dependencies: [
                .product(name: "CoreFP", package: "FP"),
                .product(name: "CoreFPOperators", package: "FP"),
                .product(name: "DataStructure", package: "FP"),
                .product(name: "DataStructureOperators", package: "FP"),
                .product(name: "Hourglass", package: "Hourglass"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            resources: [.copy("Resources/Fonts")]
        ),
        .executableTarget(
            name: "Meow",
            dependencies: [
                "GeneratorCore",
                .product(name: "CoreFP", package: "FP"),
            ]
        ),
        .testTarget(
            name: "GeneratorCoreTests",
            dependencies: [
                "GeneratorCore",
                .product(name: "CoreFP", package: "FP"),
                .product(name: "CoreFPOperators", package: "FP"),
                .product(name: "DataStructure", package: "FP"),
                .product(name: "DataStructureOperators", package: "FP"),
            ]
        ),

        // MARK: - ArticleEditor: shared domain types

        .target(
            name: "AppDomain",
            dependencies: [
                "GeneratorCore",
                .product(name: "CoreFP", package: "FP"),
                .product(name: "CoreFPOperators", package: "FP"),
                .product(name: "FPMacros", package: "FP"),
            ],
            path: "Sources/ArticleEditor/AppDomain",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - ArticleEditor: file-watching

        .target(
            name: "FileWatching",
            dependencies: [
                .product(name: "ReactiveConcurrency", package: "ReactiveConcurrency"),
            ],
            path: "Sources/ArticleEditor/FileWatching",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - ArticleEditor: features

        .target(
            name: "ArticleListFeature",
            dependencies: [
                "AppDomain",
                "GeneratorCore",
                .product(name: "SwiftRex", package: "SwiftRex"),
                .product(name: "SwiftRex.SwiftUI", package: "SwiftRex"),
                .product(name: "SwiftRex.Architecture", package: "SwiftRex"),
                .product(name: "SwiftRex.Operators", package: "SwiftRex"),
                .product(name: "SwiftRex.ReactiveConcurrency", package: "SwiftRex"),
                .product(name: "ReactiveConcurrency", package: "ReactiveConcurrency"),
                .product(name: "CoreFP", package: "FP"),
                .product(name: "CoreFPOperators", package: "FP"),
            ],
            path: "Sources/ArticleEditor/ArticleListFeature",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        .target(
            name: "ArticleEditorFeature",
            dependencies: [
                "AppDomain",
                "FileWatching",
                "GeneratorCore",
                .product(name: "SwiftRex", package: "SwiftRex"),
                .product(name: "SwiftRex.SwiftUI", package: "SwiftRex"),
                .product(name: "SwiftRex.Architecture", package: "SwiftRex"),
                .product(name: "SwiftRex.Operators", package: "SwiftRex"),
                .product(name: "SwiftRex.ReactiveConcurrency", package: "SwiftRex"),
                .product(name: "ReactiveConcurrency", package: "ReactiveConcurrency"),
                .product(name: "CoreFP", package: "FP"),
                .product(name: "CoreFPOperators", package: "FP"),
            ],
            path: "Sources/ArticleEditor/ArticleEditorFeature",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        .target(
            name: "AIChatFeature",
            dependencies: [
                "AppDomain",
                .product(name: "SwiftRex", package: "SwiftRex"),
                .product(name: "SwiftRex.SwiftUI", package: "SwiftRex"),
                .product(name: "SwiftRex.Architecture", package: "SwiftRex"),
                .product(name: "SwiftRex.Operators", package: "SwiftRex"),
                .product(name: "SwiftRex.ReactiveConcurrency", package: "SwiftRex"),
                .product(name: "ReactiveConcurrency", package: "ReactiveConcurrency"),
                .product(name: "CoreFP", package: "FP"),
                .product(name: "CoreFPOperators", package: "FP"),
            ],
            path: "Sources/ArticleEditor/AIChatFeature",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        .target(
            name: "GitHubSyncFeature",
            dependencies: [
                "AppDomain",
                .product(name: "SwiftRex", package: "SwiftRex"),
                .product(name: "SwiftRex.SwiftUI", package: "SwiftRex"),
                .product(name: "SwiftRex.Architecture", package: "SwiftRex"),
                .product(name: "SwiftRex.Operators", package: "SwiftRex"),
                .product(name: "SwiftRex.ReactiveConcurrency", package: "SwiftRex"),
                .product(name: "ReactiveConcurrency", package: "ReactiveConcurrency"),
                .product(name: "CoreFP", package: "FP"),
                .product(name: "CoreFPOperators", package: "FP"),
            ],
            path: "Sources/ArticleEditor/GitHubSyncFeature",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - ArticleEditor: app wiring

        .target(
            name: "AppCore",
            dependencies: [
                "AppDomain",
                "FileWatching",
                "ArticleListFeature",
                "ArticleEditorFeature",
                "AIChatFeature",
                "GitHubSyncFeature",
                "GeneratorCore",
                .product(name: "SwiftRex", package: "SwiftRex"),
                .product(name: "SwiftRex.SwiftUI", package: "SwiftRex"),
                .product(name: "SwiftRex.Architecture", package: "SwiftRex"),
                .product(name: "SwiftRex.Operators", package: "SwiftRex"),
                .product(name: "SwiftRex.ReactiveConcurrency", package: "SwiftRex"),
                .product(name: "ReactiveConcurrency", package: "ReactiveConcurrency"),
                .product(name: "CoreFP", package: "FP"),
                .product(name: "CoreFPOperators", package: "FP"),
                .product(name: "FPMacros", package: "FP"),
                .product(name: "Core", package: "NetworkTools"),
                .product(name: "NetworkClient", package: "NetworkTools"),
                .product(name: "NetworkServer", package: "NetworkTools"),
            ],
            path: "Sources/ArticleEditor/AppCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - ArticleEditor: tests

        .testTarget(
            name: "FileWatchingTests",
            dependencies: [
                "FileWatching",
                .product(name: "ReactiveConcurrency", package: "ReactiveConcurrency"),
            ],
            path: "Tests/FileWatchingTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        .testTarget(
            name: "AppCoreTests",
            dependencies: [
                "AppCore",
                "AppDomain",
                "ArticleEditorFeature",
                "ArticleListFeature",
                "AIChatFeature",
                "GitHubSyncFeature",
                "GeneratorCore",
                .product(name: "SwiftRex", package: "SwiftRex"),
                .product(name: "SwiftRex.SwiftUI", package: "SwiftRex"),
                .product(name: "SwiftRex.Testing", package: "SwiftRex"),
                .product(name: "ReactiveConcurrency", package: "ReactiveConcurrency"),
            ],
            path: "Tests/AppCoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        .testTarget(
            name: "ArticleListFeatureTests",
            dependencies: [
                "ArticleListFeature",
                "AppDomain",
                .product(name: "SwiftRex", package: "SwiftRex"),
                .product(name: "SwiftRex.Testing", package: "SwiftRex"),
                .product(name: "ReactiveConcurrency", package: "ReactiveConcurrency"),
            ],
            path: "Tests/ArticleListFeatureTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        .testTarget(
            name: "ArticleEditorFeatureTests",
            dependencies: [
                "ArticleEditorFeature",
                "AppDomain",
                "FileWatching",
                "GeneratorCore",
                .product(name: "SwiftRex", package: "SwiftRex"),
                .product(name: "SwiftRex.Testing", package: "SwiftRex"),
                .product(name: "ReactiveConcurrency", package: "ReactiveConcurrency"),
            ],
            path: "Tests/ArticleEditorFeatureTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        .testTarget(
            name: "AIChatFeatureTests",
            dependencies: [
                "AIChatFeature",
                "AppDomain",
                .product(name: "SwiftRex", package: "SwiftRex"),
                .product(name: "SwiftRex.Testing", package: "SwiftRex"),
                .product(name: "ReactiveConcurrency", package: "ReactiveConcurrency"),
            ],
            path: "Tests/AIChatFeatureTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        .testTarget(
            name: "GitHubSyncFeatureTests",
            dependencies: [
                "GitHubSyncFeature",
                "AppDomain",
                .product(name: "SwiftRex", package: "SwiftRex"),
                .product(name: "SwiftRex.Testing", package: "SwiftRex"),
                .product(name: "ReactiveConcurrency", package: "ReactiveConcurrency"),
            ],
            path: "Tests/GitHubSyncFeatureTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
