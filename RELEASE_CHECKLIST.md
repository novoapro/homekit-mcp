# Mac App Store Release Checklist

## Code & Build

- [x] Enable App Sandbox entitlement (`com.apple.security.app-sandbox`)
- [x] Create `PrivacyInfo.xcprivacy` privacy manifest
- [x] Add `ITSAppUsesNonExemptEncryption = false` to Info.plist
- [x] Remove legacy file migration code (no prior release)
- [x] Verify build succeeds with sandbox enabled
- [x] Verify entitlements in signed binary (`codesign -d --entitlements -`)
- [x] Verify `PrivacyInfo.xcprivacy` is bundled in `Contents/Resources/`
- [ ] Add `com.apple.developer.in-app-purchases` entitlement
- [ ] Create `CompAI-Home-StoreKit.storekit` configuration file for testing
- [ ] Verify `SubscriptionService` correctly loads products and handles purchases in sandbox
- [ ] Verify 402 responses on gated endpoints for free-tier users

## Xcode Archive & Validation

- [ ] Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
- [ ] Archive with Prod Release configuration
- [ ] Run "Validate App" in Xcode Organizer — fix any issues before uploading
- [ ] Upload to App Store Connect via Xcode Organizer or `xcrun altool`

## App Store Connect Setup

- [ ] Create app record in App Store Connect (bundle ID: `com.mnplab.compai-home`)
- [ ] Set app name: **CompAI - Home**
- [ ] Set primary category: **Utilities**
- [ ] Set secondary category: **Developer Tools**
- [ ] Set pricing and availability (free with in-app purchases)
- [ ] Add support URL (required)
- [ ] Add marketing URL (optional)

## In-App Purchase Setup

- [ ] Create subscription group "CompAI Home Pro" in App Store Connect
- [ ] Create product: `com.mnplab.compai_home.pro.monthly` (monthly auto-renewable)
- [ ] Create product: `com.mnplab.compai_home.pro.yearly` (yearly auto-renewable, discounted)
- [ ] Configure pricing for each product (all territories)
- [ ] Add subscription localization (display name, description) for each product
- [ ] Upload subscription group marketing image (optional)
- [ ] Configure subscription grace period (recommended: 16 days billing retry)
- [ ] Set up App Store Server Notifications V2 URL (optional, for future server-side validation)

## App Store Listing

### App Description

> CompAI - Home connects your Apple HomeKit smart home to AI assistants through the Model Context Protocol (MCP).
>
> Run it as a lightweight menu bar app on your Mac, and any MCP-compatible AI assistant — like Claude — can query your device states, control accessories, and interact with your smart home using natural language.
>
> KEY FEATURES
>
> - MCP & REST Server — Exposes your HomeKit devices through a local server on your Mac. AI assistants connect via the Model Context Protocol (JSON-RPC) or a standard REST API.
>
> - Device Control — Turn lights on and off, adjust brightness and color temperature, set thermostats, lock doors, trigger scenes, and more — all from your AI assistant or the built-in interface.
>
> - Smart Automations — Create powerful automations with device state triggers, time schedules, sunrise/sunset events, and webhook triggers. Build complex flows with conditionals, loops, delays, and nested automation calls.
>
> - AI Automation Generation — Describe what you want in plain language and let AI generate the automation for you. Supports Claude, OpenAI, and Gemini.
>
> - Real-Time Monitoring — Track every device state change, API call, webhook event, and automation execution in a detailed activity log. Filter by category, device, service, or search by keyword.
>
> - Web Dashboard — A companion web interface for monitoring devices, managing automations, and viewing logs from any browser on your network.
>
> - Webhook Notifications — Receive HTTP callbacks when devices change state, signed with HMAC-SHA256 for security.
>
> - iCloud Sync — Optionally sync your automations across multiple Macs via CloudKit.
>
> - Privacy First — Everything runs locally on your Mac. No cloud dependency, no data leaves your network unless you configure webhooks or AI features.
>
> SUPPORTED DEVICES
>
> Works with 30+ HomeKit accessory types including lights, switches, outlets, thermostats, locks, doors, garage doors, sensors (motion, temperature, humidity, contact, leak, smoke, CO, air quality), security systems, fans, air purifiers, window coverings, speakers, and more.
>
> REQUIREMENTS
>
> - macOS 13.0 (Ventura) or later
> - HomeKit-compatible accessories configured in the Apple Home app

### Keywords (max 100 characters total)

```
homekit,mcp,smart home,automation,ai,claude,iot,home assistant,device control,scenes
```

### Subtitle (max 30 characters)

```
AI Companion for Apple HomeKit
```

### Promotional Text (max 170 characters, can be updated without a new build)

```
Connect AI assistants to your Apple HomeKit smart home. Control devices, create automations, and monitor your home — all running locally on your Mac.
```

- [ ] Update app description to mention free vs Pro features
- [ ] Add subscription terms to description (pricing, renewal period, cancellation)
- [ ] Link to subscription terms of use (required by Apple for auto-renewable subscriptions)

### Screenshots

- [ ] Prepare screenshots at required resolutions (at least one set for Mac)
  - Existing screenshots in `screenshots/` can be used as a starting point
  - Required: at least one screenshot for Mac display sizes
  - Recommended screenshots:
    - Device list with room sidebar
    - Automation editor showing triggers and blocks
    - Activity log with filters
    - Server settings
    - Web dashboard (optional, shows companion feature)
- [ ] Add app icon preview (1024x1024 already in asset catalog)

## Privacy & Legal

### Privacy Policy

- [ ] Create and host a privacy policy URL
- [ ] Link privacy policy in App Store Connect → App Privacy

Draft privacy policy points to cover:
- The app runs entirely locally on the user's Mac
- No personal data is collected, transmitted, or stored on external servers
- HomeKit data stays on-device and is only exposed through the local network server
- If AI features are enabled, prompts are sent to the user's chosen AI provider (Claude/OpenAI/Gemini) using the user's own API key
- If webhooks are enabled, device state change data is sent to the user-configured URL
- iCloud sync (if enabled) uses the user's own iCloud account via CloudKit
- No analytics, tracking, or advertising SDKs are included

### App Privacy Questionnaire

- [ ] Complete App Privacy questionnaire in App Store Connect
  - Data types collected: **None** (if AI/webhooks/iCloud are disabled)
  - If AI features are used: prompts and device names are sent to third-party AI providers, but this is user-initiated and uses their own API key
  - No tracking, no analytics, no advertising

- [ ] Add subscription terms of service URL in App Store Connect
- [ ] Update privacy policy to mention subscription data handling
- [ ] Ensure "Restore Purchases" button is visible in the app without a current subscription

### Age Rating

- [ ] Complete age rating questionnaire
  - No violence, gambling, horror, profanity, or mature content
  - No unrestricted web access (the app only makes requests to user-configured endpoints)
  - Suggested rating: **4+**

## App Review Preparation

### Review Notes

Draft review notes for Apple:

> CompAI - Home is a macOS menu bar application that acts as a local MCP (Model Context Protocol) server, allowing AI assistants like Claude to interact with the user's Apple HomeKit smart home devices.
>
> NETWORK SERVER ENTITLEMENT
> The app requires com.apple.security.network.server to run a local HTTP server (default port 3000) on the user's Mac. This server implements:
> - The Model Context Protocol (MCP) for AI assistant integration via JSON-RPC
> - A REST API for programmatic device access
> - WebSocket connections for real-time state updates
>
> All communication is local — the server listens on localhost by default and is only accessible from the same machine or local network if the user explicitly changes the bind address.
>
> HOW TO TEST
> 1. Launch the app — it appears as an icon in the Mac menu bar
> 2. Grant HomeKit access when prompted
> 3. The app will discover HomeKit accessories configured in the Apple Home app
> 4. Open the app window from the menu bar to see devices, automations, and logs
> 5. The MCP/REST server starts automatically and can be tested by visiting http://localhost:3000/health in a browser
>
> Note: The app requires HomeKit-compatible accessories to demonstrate full functionality. Without HomeKit devices, the app will launch and run but show an empty device list.

- [ ] Finalize and submit review notes
- [ ] If reviewer needs HomeKit devices, note that the app works with any HomeKit-compatible setup
- [ ] Provide demo account credentials if Sign in with Apple is required for review (Sign in with Apple is optional — only needed for iCloud backup features)
- [ ] Ensure "Restore Purchases" is accessible without a current subscription
- [ ] Update review notes to explain free vs Pro tier distinction
- [ ] Provide sandbox test account credentials for reviewer to test purchase flow

## TestFlight (Pre-Release Testing)

- [ ] Upload build to App Store Connect
- [ ] Enable internal testing in TestFlight
- [ ] Invite internal testers
- [ ] Test full app flow on a clean Mac:
  - HomeKit device discovery and control
  - MCP server start/stop and client connection
  - Automation creation, editing, and execution
  - Activity log filtering and search
  - Settings persistence across app restarts
  - Web dashboard connectivity
- [ ] Test in-app purchase flow in sandbox environment
- [ ] Test restore purchases
- [ ] Test subscription expiration and renewal
- [ ] Test free-tier feature gating (automations, AI blocked; devices, logs accessible)
- [ ] Test webclient behavior for free vs Pro users (upgrade prompts, 402 handling)
- [ ] Verify "Manage Subscription" link opens App Store subscription management
- [ ] For external TestFlight: complete privacy policy and age rating first

## Post-Submission

- [ ] Monitor App Review status
- [ ] If `network.server` entitlement is rejected, implement Unix domain socket fallback (see `SANDBOX.md`)
- [ ] Respond to any App Review feedback within 24 hours
- [ ] After approval: set release date (manual or automatic)
