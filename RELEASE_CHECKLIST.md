# Mac App Store Release Checklist

## Code & Build

- [x] Enable App Sandbox entitlement (`com.apple.security.app-sandbox`)
- [x] Create `PrivacyInfo.xcprivacy` privacy manifest
- [x] Add `ITSAppUsesNonExemptEncryption = false` to Info.plist
- [x] Remove legacy file migration code (no prior release)
- [x] Verify build succeeds with sandbox enabled
- [x] Verify entitlements in signed binary (`codesign -d --entitlements -`)
- [x] Verify `PrivacyInfo.xcprivacy` is bundled in `Contents/Resources/`

## Xcode Archive & Validation

- [ ] Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
- [ ] Archive with Prod Release configuration
- [ ] Run "Validate App" in Xcode Organizer — fix any issues before uploading
- [ ] Upload to App Store Connect via Xcode Organizer or `xcrun altool`

## App Store Connect Setup

- [ ] Create app record in App Store Connect (bundle ID: `com.mnplab.compai-home`)
- [ ] Set app name: **CompAI - Home**
- [ ] Set primary category: **Utilities**
- [ ] Set pricing and availability (free or paid)

## App Store Listing

- [ ] Write app description
- [ ] Add keywords for search
- [ ] Prepare screenshots (at least one set for Mac)
- [ ] Add app icon preview (1024x1024 already in asset catalog)
- [ ] Set subtitle (optional, max 30 characters)
- [ ] Add promotional text (optional)

## Privacy & Legal

- [ ] Create and host a privacy policy URL
- [ ] Link privacy policy in App Store Connect → App Privacy
- [ ] Complete App Privacy questionnaire (data collection declarations)
- [ ] Complete age rating questionnaire

## App Review Preparation

- [ ] Write App Review notes explaining:
  - The app is an MCP (Model Context Protocol) server that AI assistants connect to locally
  - The `network.server` entitlement is required for the localhost MCP/REST server
  - The app exposes HomeKit devices to AI tools running on the same machine
- [ ] Provide demo account credentials if Sign in with Apple is required for review
- [ ] If reviewer needs HomeKit devices, note that the app works with any HomeKit-compatible setup

## Post-Submission

- [ ] Monitor App Review status
- [ ] If `network.server` entitlement is rejected, implement Unix domain socket fallback (see `SANDBOX.md`)
- [ ] Respond to any App Review feedback within 24 hours
