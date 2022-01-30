// swift-tools-version:5.4
import PackageDescription

let package = Package(
    name: "HCSR04",
    
    products: [
        .library(
            name: "HCSR04",
            targets: ["HCSR04"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/uraimo/SwiftyGPIO.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "HCSR04",
            dependencies: [
                .product(name: "SwiftyGPIO", package: "SwiftyGPIO"),
            ],
            path: "Sources",
            resources: [
                .process("../README.md")
            ]
        ),
    ]
)
