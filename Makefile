# Teststrip task runner.
#
# One discoverable entry point for the common local workflows. Every target is
# a thin delegation to a script in script/ (or a swift invocation) -- no build
# logic lives here. Run `make` (or `make help`) to list targets.
#
# Interactive AX-driven scenario cards are deliberately NOT wrapped here: that
# flow is multi-step, per-card, and must run in the Tart VM, not on the host
# console. Drive it directly with script/vm_scenario_run.sh (see
# test/scenarios/README.md).

.DEFAULT_GOAL := help
.PHONY: help build test verify run smoke package package-dry reset clean

help: ## List available targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Compile all targets (swift build)
	swift build

test: ## Run the Swift unit tests (swift test)
	swift test

verify: ## Full host-safe gate: unit tests + sandboxed build + headless verifiers
	script/verify_headless_workflows.sh

run: ## Build and launch against your real library (dogfooding)
	script/build_and_run.sh

smoke: ## Launch an isolated throwaway library seeded with 24 synthetic photos
	script/build_and_run.sh --smoke

package: ## Signed + notarized release build in dist/ (needs signing credentials)
	script/package_release.sh

package-dry: ## Prove the packaging pipeline with an ad-hoc signature (no credentials)
	script/package_release.sh --dry-run

reset: ## Clean up throwaway isolated test catalogs left by smoke/scenario runs
	script/reset_isolated_test_data.sh

clean: ## Remove build artifacts (swift build products + dist bundle)
	swift package clean
	rm -rf dist/Teststrip.app
