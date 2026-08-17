import Foundation
import MetaMarketingGatewayReaderKit

let code = await ReaderCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(code)
