# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CompAI - Home — a macOS Mac Catalyst application that exposes HomeKit devices through the Model Context Protocol (MCP). It provides real-time state monitoring, device control via MCP tools, and webhook notifications for state changes. Runs as a background menu bar app.

## Technology Stack

- **Platform**: Mac Catalyst (iOS app running on macOS)
- **Language**: Swift 5.9+, minimum macOS 13.0 (Ventura)
- **UI**: SwiftUI with MVVM + Combine
- **HTTP/MCP Server**: Vapor 4.x (SSE transport)
- **HomeKit**: Apple HomeKit framework (HMHomeManager, HMAccessoryDelegate)
- **Distribution**: Non-sandboxed, direct download (notarized for public release)

## Applications

Keep in mind that there are two applications withing this project. A swift application called CompAI-Home and a web application called webclient. The web application is used to view the logs of the swift application. The web application is not part of the swift application. The web application is a separate application that is run independently of the swift application. The web application is run using the following command:

```bash
cd webclient
npm run dev
```

If I am referring to the web application, I will use the term "web app". If I am referring to the swift application, I will use the term "app", or "server app", or "server", or "mcp app".

## Architecture

The app has four layers:

1. **Views** (SwiftUI): MenuBarView (NSStatusItem via Catalyst), DeviceListView, LogViewerView, SettingsView
2. **ViewModels**: HomeKitViewModel, LogViewModel, SettingsViewModel — bridge services to UI via @Published properties
3. **Services**:
   - `HomeKitManager` — HMHomeManager/HMAccessoryDelegate, device discovery, state monitoring, control
   - `MCPServer` — Vapor HTTP server on localhost:3000, implements MCP JSON-RPC over SSE, exposes `homekit://devices` resource and `control_device` tool
   - `WebhookService` — actor, sends HTTP POST on state changes with exponential backoff retry (max 3)
   - `LoggingService` — actor, circular buffer of 200 state change entries, persisted to JSON in Application Support
   - `StorageService` — @AppStorage wrapper for webhook URL, MCP port, server toggle
4. **Models**: DeviceModel, ServiceModel, CharacteristicModel (with AnyCodable), StateChangeLog, StateChange

### Key Data Flows

- **State change**: HomeKit delegate → HomeKitManager → (LoggingService + WebhookService + ViewModel update)
- **MCP request**: HTTP/SSE client → Vapor MCPServer → HomeKitManager → response
- **UI interaction**: Menu bar → SwiftUI window → ViewModel → Service

## Build & Run

This is an Xcode project (Mac Catalyst). Use the Makefile targets to build and run.

### After completing changes, rebuild only what you changed:

- **Swift-only changes** (files under `CompAI-Home/`): run `make dev` — builds and relaunches the MCP server app.
- **Web-only changes** (files under `webclient/`): no build step needed if the Vite dev server is already running (HMR auto-updates the browser). If the dev server is not running, run `make web-dev`.
- **Both Swift and web changes**: run `make dev` for the server app. The web app updates automatically via HMR if the dev server is running; otherwise run `make web-dev` as well.
- **Full rebuild of both apps**: run `make dev-all` — builds the Swift app, starts the web dev server (if not already running), and opens the browser.

Do NOT run `make dev-all` if you only changed one side. Pick the narrowest target that covers your changes.

### Dependencies

Managed via Swift Package Manager. Primary dependency:

```
vapor/vapor 4.89.0+
```

### Required Capabilities

- HomeKit entitlement must be enabled in Xcode Signing & Capabilities
- `NSHomeKitUsageDescription` in Info.plist
- `LSUIElement = true` in Info.plist (hides Dock icon)

### Subscription Testing

The app uses StoreKit 2 auto-renewable subscriptions to gate Pro features (automations, AI, web dashboard). Since `make dev` doesn't connect to StoreKit sandbox, use the debug override to switch tiers:

```bash
# Enable Pro tier
defaults write com.mnplab.compai-home subscription.debugOverrideTier pro

# Switch back to Free tier
defaults delete com.mnplab.compai-home subscription.debugOverrideTier
```

Restart the app after changing. The override is `#if DEBUG` only and stripped from release builds.

To test the actual purchase flow (product listing, payment sheet, restore purchases), use Xcode:

1. Open `CompAI-Home.xcodeproj` in Xcode
2. Edit scheme → Run → Options → set **StoreKit Configuration** to `CompAI-Home-StoreKit.storekit`
3. Run with Cmd+R
4. Use **Debug → StoreKit → Manage Transactions** to delete/expire/refund transactions for repeated testing


**Very Important:**
Everytime you complete a task that changes in any way the model that we expose through the MCP server, you need to update the documentation at `API.md` file to reflect the changes.

Everytime we add something new to the automation definition, you need to update a few things: 
- How we display and edit automations including the new fields, blocks, and options in the MCP server app and in the web app
- update how we log them. 
- update how we expose the new update to the automation schema externally via MCP or REST server.
- Update the documentation at `API.md` file to reflect the changes.
