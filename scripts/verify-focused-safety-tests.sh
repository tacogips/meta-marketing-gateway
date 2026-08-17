#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
run_test() {
  sh "$script_dir/run-swiftpm-external.sh" test --filter "$1"
}

run_test 'GraphSecurityTests.testPublicReconcileDeniesWithoutProductionComposition'
run_test 'GraphSecurityTests.testBrokerBackedJournalRetainsOutcomeUnknownWithoutCASForPendingOrUnavailable'
run_test 'GraphSecurityTests.testWriterReconciliationNeverReplaysUnknownOutcome'
run_test 'GraphSecurityTests.testProductionApplyDependenciesRequireTrustedHeadAnchor'
run_test 'MetaCapabilityCatalogGeneratorTests.CatalogGeneratorTests/testGeneratorRequiresPerOperationReviewAndAvailabilityPrecedence'
