import PackagePlugin

@main
struct MetaCapabilityCatalogPlugin: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
    let surface: String
    switch target.name {
    case "MetaMarketingGatewayReaderKit": surface = "reader"
    case "MetaMarketingGatewayWriterKit": surface = "writer"
    case "MetaMarketingGatewayDeleterKit": surface = "deleter"
    default: return []
    }
    let tool = try context.tool(named: "MetaCapabilityCatalogGenerator")
    let input = context.package.directoryURL.appending(path: "Catalog/meta-capabilities.json")
    let output = context.pluginWorkDirectoryURL.appending(
      path: "Generated\(surface.capitalized)CapabilityCatalog.swift")
    return [
      .buildCommand(
        displayName: "Generate \(surface) capability projection",
        executable: tool.url,
        arguments: [
          "--input", input.path(), "--surface", surface, "--swift-output", output.path(),
        ],
        inputFiles: [input], outputFiles: [output])
    ]
  }
}
