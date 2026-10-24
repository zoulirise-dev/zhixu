// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Zhixu",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Zhixu", targets: ["Zhixu"])],
    targets: [.executableTarget(name: "Zhixu")],
    swiftLanguageModes: [.v5]
)
