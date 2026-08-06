// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CatWalk",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "CatWalk",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/CatWalk",
            // Lets the built binary find Sparkle.framework inside the .app bundle.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
