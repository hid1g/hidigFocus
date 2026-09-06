// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "hidigFocus",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "hidigFocus", targets: ["hidigFocus"])
    ],
    targets: [
        .executableTarget(
            name: "hidigFocus",
            path: "Sources",
            exclude: ["Resources/SafariExtension"],
            resources: [
                .process("Resources/hidigFocus-icon-master.png"),
                .copy("Resources/BrowserExtension")
            ]
        ),
        .testTarget(
            name: "hidigFocusTests",
            dependencies: ["hidigFocus"],
            path: "Tests"
        )
    ]
)
