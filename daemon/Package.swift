// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Hilo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "hilod", targets: ["hilod"]),
        .executable(name: "hilo", targets: ["hilo"]),
    ],
    targets: [
        .target(name: "HiloContract"),
        .target(name: "HiloCore", dependencies: ["HiloContract"]),
        .target(name: "HiloStore", dependencies: ["HiloContract"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "HiloRuntime", dependencies: ["HiloCore", "HiloContract", "HiloStore"]),
        .executableTarget(
            name: "hilod", dependencies: ["HiloRuntime", "HiloCore", "HiloContract"], exclude: ["Info.plist"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                                           "-Xlinker", "Sources/hilod/Info.plist"])]
        ),
        .executableTarget(name: "hilo", dependencies: ["HiloRuntime"]),
        .testTarget(name: "HiloContractTests", dependencies: ["HiloContract"]),
        .testTarget(name: "HiloCoreTests", dependencies: ["HiloCore"]),
        .testTarget(name: "HiloStoreTests", dependencies: ["HiloStore", "HiloContract"]),
        .testTarget(name: "HiloRuntimeTests", dependencies: ["HiloRuntime", "HiloCore", "HiloContract"]),
    ]
)
