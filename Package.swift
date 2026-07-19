// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FluentKit",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "FluentKit", targets: ["FluentKit"]),
        .executable(name: "FluentGallery", targets: ["FluentGallery"]),
        .executable(name: "FluentKitValidation", targets: ["FluentKitValidation"])
    ],
    targets: [
        .target(name: "FluentKit"),
        .executableTarget(name: "FluentGallery", dependencies: ["FluentKit"]),
        .executableTarget(name: "FluentKitValidation", dependencies: ["FluentKit"])
    ]
)
