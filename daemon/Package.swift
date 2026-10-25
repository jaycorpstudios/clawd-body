// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Hilo",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HiloContract"),
        .target(name: "HiloCore", dependencies: ["HiloContract"]),
        .testTarget(name: "HiloContractTests", dependencies: ["HiloContract"]),
        .testTarget(name: "HiloCoreTests", dependencies: ["HiloCore"]),
    ]
)
