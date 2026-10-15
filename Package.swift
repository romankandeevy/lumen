// swift-tools-version:6.1
import PackageDescription

// Lumen — модули из §10.1 техплана. Сейчас только те, в которых уже есть код.
let package = Package(
    name: "Lumen",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lumen", targets: ["Lumen"]),
        .executable(name: "lumen-mcp", targets: ["lumen-mcp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(name: "LumenCore"),
        .target(name: "LumenStorage", dependencies: ["LumenCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "LumenProviders", dependencies: ["LumenCore"]),
        .target(name: "LumenUI", dependencies: ["LumenCore", "LumenStorage", "LumenProviders"]),
        .executableTarget(name: "Lumen", dependencies: ["LumenUI"]),
        // stdio MCP-сервер: память для claude (лежит рядом с Lumen в бандле)
        .executableTarget(name: "lumen-mcp", dependencies: ["LumenCore", "LumenStorage"]),
        .testTarget(name: "LumenTests", dependencies: ["LumenCore", "LumenStorage", "LumenProviders", "LumenUI", "lumen-mcp"],
                    resources: [.copy("Fixtures")]),
    ]
)
