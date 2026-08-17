// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MetaMarketingGateway",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "MetaMarketingGatewayReader", targets: ["MetaMarketingGatewayReaderKit"]),
    .library(name: "MetaMarketingGatewayWriter", targets: ["MetaMarketingGatewayWriterKit"]),
    .library(name: "MetaMarketingGatewayDeleter", targets: ["MetaMarketingGatewayDeleterKit"]),
    .executable(
      name: "meta-marketing-gateway-reader", targets: ["MetaMarketingGatewayReaderCommand"]),
    .executable(
      name: "meta-marketing-gateway-writer", targets: ["MetaMarketingGatewayWriterCommand"]),
    .executable(
      name: "meta-marketing-gateway-deleter", targets: ["MetaMarketingGatewayDeleterCommand"]),
    .executable(
      name: "meta-marketing-gateway-trusted-head-broker",
      targets: ["MetaMarketingGatewayTrustedHeadBroker"]),
  ],
  targets: [
    .target(name: "MetaGraphPrimitives"),
    .target(
      name: "MetaMarketingGatewayReaderKit",
      dependencies: ["MetaGraphPrimitives"],
      plugins: [.plugin(name: "MetaCapabilityCatalogPlugin")]),
    .target(
      name: "MetaTrustedHeadProtocol",
      dependencies: []),
    .target(
      name: "MetaMarketingGatewayWriterKit",
      dependencies: ["MetaGraphPrimitives", "MetaTrustedHeadProtocol"],
      plugins: [.plugin(name: "MetaCapabilityCatalogPlugin")]),
    .target(
      name: "MetaMarketingGatewayDeleterKit",
      dependencies: ["MetaGraphPrimitives"],
      plugins: [.plugin(name: "MetaCapabilityCatalogPlugin")]),
    .executableTarget(
      name: "MetaMarketingGatewayReaderCommand",
      dependencies: ["MetaMarketingGatewayReaderKit"],
      path: "Sources/MetaMarketingGatewayReader"),
    .executableTarget(
      name: "MetaMarketingGatewayWriterCommand",
      dependencies: ["MetaMarketingGatewayWriterKit"],
      path: "Sources/MetaMarketingGatewayWriter"),
    .executableTarget(
      name: "MetaMarketingGatewayDeleterCommand",
      dependencies: ["MetaMarketingGatewayDeleterKit"],
      path: "Sources/MetaMarketingGatewayDeleter"),
    .executableTarget(
      name: "MetaMarketingGatewayTrustedHeadBroker",
      dependencies: ["MetaTrustedHeadProtocol"]),
    .executableTarget(name: "MetaCapabilityCatalogGenerator"),
    .plugin(
      name: "MetaCapabilityCatalogPlugin",
      capability: .buildTool(),
      dependencies: ["MetaCapabilityCatalogGenerator"]),
    .testTarget(
      name: "MetaGraphPrimitivesTests",
      dependencies: ["MetaGraphPrimitives"]),
    .testTarget(
      name: "MetaMarketingGatewayReaderKitTests",
      dependencies: ["MetaMarketingGatewayReaderKit", "MetaGraphPrimitives"],
      resources: [.process("Fixtures")]),
    .testTarget(
      name: "MetaMarketingGatewayWriterKitTests",
      dependencies: [
        "MetaMarketingGatewayWriterKit", "MetaMarketingGatewayReaderKit", "MetaGraphPrimitives",
        "MetaTrustedHeadProtocol",
      ]),
    .testTarget(
      name: "MetaMarketingGatewayDeleterKitTests",
      dependencies: ["MetaMarketingGatewayDeleterKit", "MetaGraphPrimitives"]),
    .testTarget(
      name: "MetaTrustedHeadBrokerTests",
      dependencies: ["MetaTrustedHeadProtocol"]),
    .testTarget(
      name: "MetaCapabilityCatalogGeneratorTests",
      dependencies: ["MetaCapabilityCatalogGenerator"]),
  ]
)
