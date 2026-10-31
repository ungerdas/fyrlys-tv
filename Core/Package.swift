// swift-tools-version:5.9
// Kjernen i Fyrlys for Apple TV: Xtream Codes, programinfo, favoritter og tekstene. Bare Foundation, så den kan
// testes uten Apple TV (også på Linux). Selve appen (SwiftUI) ligger i ../App og bygges med Xcode (../project.yml).
import PackageDescription

let package = Package(
    name: "FyrlysCore",
    platforms: [.tvOS(.v17), .macOS(.v14), .iOS(.v17)],
    products: [.library(name: "FyrlysCore", targets: ["FyrlysCore"])],
    targets: [
        .target(name: "FyrlysCore", path: "Sources/FyrlysCore"),
        .testTarget(name: "FyrlysCoreTests", dependencies: ["FyrlysCore"], path: "Tests/FyrlysCoreTests"),
    ]
)
