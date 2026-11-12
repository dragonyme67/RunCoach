// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RunCoachCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RunCoachCore", targets: ["RunCoachCore"])
    ],
    targets: [
        .target(name: "RunCoachCore"),
        .testTarget(name: "RunCoachCoreTests", dependencies: ["RunCoachCore"])
    ]
)
