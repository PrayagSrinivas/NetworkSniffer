// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
// swift-tools-version: 6.0

let package = Package(
  name: "NetworkSniffer",
  platforms: [
    .iOS(.v14) // iOS-only, enables OS.Logger without macOS constraints
  ],
  products: [
    .library(name: "NetworkSniffer", targets: ["NetworkSniffer"]),
  ],
  targets: [
    .target(name: "NetworkSniffer"),
    .testTarget(name: "NetworkSnifferTests", dependencies: ["NetworkSniffer"]),
  ]
)
