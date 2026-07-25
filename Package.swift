// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "iGestures",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .library(name: "iGestures", targets: ["iGestures"]),
    .executable(
      name: "iGesturesCoreChecks",
      targets: ["iGesturesCoreChecks"]
    ),
  ],
  targets: [
    .target(
      name: "iGestures",
      path: "iGestures",
      exclude: [
        "App",
        "Resources",
        "Supporting",
        "UI",
      ],
      sources: [
        "Core",
        "Services",
      ]
    ),
    .executableTarget(
      name: "iGesturesCoreChecks",
      dependencies: ["iGestures"],
      path: "iGesturesCoreChecks"
    ),
  ]
)
