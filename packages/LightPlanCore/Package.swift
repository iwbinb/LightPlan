// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LightPlanCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "LightPlanCore", targets: ["LightPlanCore"]),
               .executable(name: "lightplan-cli", targets: ["LightPlanCLI"])],
    targets: [.target(name: "LightPlanCore"),
              .executableTarget(name: "LightPlanCLI", dependencies: ["LightPlanCore"]),
              .testTarget(name: "LightPlanCoreTests", dependencies: ["LightPlanCore"], resources: [.copy("Fixtures")])]
)
