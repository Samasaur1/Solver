// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "Solver",
    products: [
        .executable(name: "solver", targets: ["Solver"]),
        .library(name: "SolverKit", targets: ["SolverKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.0"),
        .package(url: "https://github.com/onevcat/Rainbow", from: "3.0.0"),
    ],
    targets: [
        .target(name: "Solver", dependencies: [
            "SolverKit",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            "Rainbow"
        ]),
        .target(name: "SolverKit", dependencies: []),
    ]
)
