import Foundation
import MetaMarketingGatewayDeleterKit

let code = await DeleterCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(code)
