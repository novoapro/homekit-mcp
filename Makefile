.PHONY: generate dev dev-all prod test test-swift test-web web-dev web-build web-prod web-install clean kill help

WEB_PORT = 5173

DERIVED_DATA = .build/DerivedData
XCODEBUILD = xcodebuild -scheme HomeKitMCP -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath $(DERIVED_DATA)
PRODUCTS = $(DERIVED_DATA)/Build/Products

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

generate: ## Regenerate Xcode project from project.yml
	@command -v xcodegen >/dev/null 2>&1 || { echo "Installing XcodeGen..."; brew install xcodegen; }
	xcodegen generate

dev: kill generate ## Build and run in Dev config
	$(XCODEBUILD) -configuration 'Dev Debug' build
	@echo "Launching HomeKitMCP (Dev)..."
	@open "$(PRODUCTS)/Dev Debug-maccatalyst/HomeKitMCP.app"

dev-all: dev ## Build and run both apps in Dev mode
	@if lsof -iTCP:$(WEB_PORT) -sTCP:LISTEN >/dev/null 2>&1; then \
		echo "Web dev server already running, skipping browser open."; \
	else \
		echo "Starting web dashboard..."; \
		cd log-viewer-web && npm run dev & \
		sleep 3; \
		open "http://localhost:$(WEB_PORT)"; \
	fi

prod: kill generate ## Build and run in Prod config
	$(XCODEBUILD) -configuration 'Prod Debug' build
	@echo "Launching HomeKitMCP (Prod)..."
	@open "$(PRODUCTS)/Prod Debug-maccatalyst/HomeKitMCP.app"

test: test-swift test-web ## Run all tests

test-swift: generate ## Run Swift unit tests
	$(XCODEBUILD) -configuration 'Dev Debug' test

test-web: ## Run web app tests
	cd log-viewer-web && npm test

web-dev: ## Start web app dev server
	cd log-viewer-web && npm run dev

web-build: ## Build web app for production
	cd log-viewer-web && npm run build

web-prod: web-build ## Build and run web app via Docker
	cd log-viewer-web && docker compose up -d --build

web-install: ## Install web app dependencies
	cd log-viewer-web && npm ci

deploy: kill ## Pull latest, build & launch production MCP app + web app
	git pull origin main
	$(MAKE) generate
	$(XCODEBUILD) -configuration 'Prod Debug' build
	@echo "Launching HomeKitMCP (Prod)..."
	@open "$(PRODUCTS)/Prod Debug-maccatalyst/HomeKitMCP.app"
	cd log-viewer-web && docker compose up -d --build

clean: ## Clean build artifacts
	rm -rf $(DERIVED_DATA)
	rm -rf log-viewer-web/dist log-viewer-web/node_modules/.vite

kill: ## Kill running HomeKitMCP process
	pkill -9 -f HomeKitMCP || true
