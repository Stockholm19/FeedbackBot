// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FeedbackBot",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.92.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.9.0")
    ],
    targets: [
        // Вся логика как библиотека
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver")
            ],
            path: "Sources/App"
        ),
        // Точка входа — отдельный исполняемый таргет в папке Run (НЕ внутри Sources)
        .executableTarget(
            name: "Run",
            dependencies: ["App"],
            path: "Run"
        )
    ]
)
