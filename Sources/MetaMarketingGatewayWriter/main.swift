import Foundation
import MetaMarketingGatewayWriterKit

let code = await WriterCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(code)
