#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sh "$script_dir/run-swiftpm-external.sh" package describe --type json >/dev/null
! rg -n 'MetaGraphWriter|MetaGraphWriting|MutationJournal|TrustedHead|graph post|graph delete' \
  Sources/MetaMarketingGatewayReader Sources/MetaMarketingGatewayReaderKit
! rg -n 'GraphUpload|\bURLSessionGraphTransport\b|GraphMultipart|GraphMethod\.post|GraphMethod\.delete' \
  Sources/MetaMarketingGatewayReader Sources/MetaMarketingGatewayReaderKit
! rg -n 'MetaMarketingGatewayReaderKit' Sources/MetaMarketingGatewayWriterKit
! rg -n 'MetaMarketingGatewayDeleterKit|DeleteGraphRequest|DELETE|meta\.generic\.delete' \
  Sources/MetaMarketingGatewayWriter Sources/MetaMarketingGatewayWriterKit
! rg -n 'MetaMarketingGatewayWriterKit|GraphRequest|GraphMethod|POST' \
  Sources/MetaMarketingGatewayDeleter Sources/MetaMarketingGatewayDeleterKit
! rg -n 'MetaMarketingGatewayWriterKit|MetaTrustedHeadProtocol|meta\.ads\..*create' \
  Sources/MetaMarketingGatewayReader Sources/MetaMarketingGatewayReaderKit
! rg -n 'public (enum|struct|protocol) (GraphMethod|GraphRequest|GraphTransport|GraphCredential|GraphCredentialResolving|KinkoEnvironmentCredentials)|case (post|delete)|bodyMediaType|operationID' \
  Sources/MetaGraphPrimitives
rg -q 'MetaMarketingGatewayReaderKit' Package.swift
rg -q 'MetaMarketingGatewayWriterKit' Package.swift
rg -q 'MetaMarketingGatewayDeleterKit' Package.swift
rg -q 'MetaMarketingGatewayTrustedHeadBroker' Package.swift
rg -q 'MetaCapabilityCatalogPlugin' Package.swift
