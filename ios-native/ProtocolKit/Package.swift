// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DSHMobileProtocol",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "DSHMobileProtocol", targets: ["DSHMobileProtocol"])],
    targets: [
        .target(name: "DSHMobileProtocol"),
        .testTarget(name: "DSHMobileProtocolTests", dependencies: ["DSHMobileProtocol"]),
    ]
)
