// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ReteCasa",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ReteCasa",
            path: "Sources/ReteCasa"
        )
    ]
)
