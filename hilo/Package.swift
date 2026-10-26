// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HiloApp",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HiloApp", targets: ["HiloApp"])],
    dependencies: [.package(path: "../daemon")],
    targets: [
        .executableTarget(name: "HiloApp", dependencies: [
            .product(name: "HiloStore", package: "daemon"),
            .product(name: "HiloRuntime", package: "daemon"),
        ], path: "Sources/HiloApp"),
    ]
)
