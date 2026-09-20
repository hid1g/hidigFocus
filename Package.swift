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
        .systemLibrary(
            name: "CSQLite",
            path: "CSQLite",
            pkgConfig: "sqlite3"
        ),
        .executableTarget(
            name: "hidigFocus",
            dependencies: ["CSQLite"],
            path: "Sources",
            exclude: ["Resources/SafariExtension"],
            resources: [
                .process("Resources/hidigFocus-icon-master.png"),
                .copy("Resources/BrowserExtension")
            ]
        ),
        .testTarget(
            name: "hidigFocusTests",
            dependencies: ["hidigFocus", "CSQLite"],
            path: "Tests"
        )
    ]
)
