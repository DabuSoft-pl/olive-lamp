// swift-tools-version: 6.2
import PackageDescription

// Clean Architecture: dependencies point inwards only.
// Domain <- Application <- Infrastructure. The compiler enforces it: Domain cannot import anything of ours,
// Application sees only Domain, and only Infrastructure (and the app's composition root) touches the network,
// files and the Keychain.
let package = Package(
    name: "LampKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LampDomain", targets: ["LampDomain"]),
        .library(name: "LampApplication", targets: ["LampApplication"]),
        .library(name: "LampInfrastructure", targets: ["LampInfrastructure"]),
    ],
    targets: [
        .target(name: "LampDomain"),
        .target(name: "LampApplication", dependencies: ["LampDomain"]),
        .target(name: "LampInfrastructure", dependencies: ["LampDomain", "LampApplication"]),
        .testTarget(name: "LampDomainTests", dependencies: ["LampDomain"]),
        .testTarget(name: "LampApplicationTests", dependencies: ["LampDomain", "LampApplication"]),
        .testTarget(name: "LampInfrastructureTests", dependencies: ["LampDomain", "LampApplication", "LampInfrastructure"]),
    ]
)
