# iOS App Store Submission

## Info.plist Configuration

```xml
<!-- ios/App/App/Info.plist -->
<key>CFBundleDisplayName</key>
<string>My App</string>

<key>CFBundleShortVersionString</key>
<string>1.0.0</string>

<key>CFBundleVersion</key>
<string>1</string>

<!-- Privacy descriptions — REQUIRED for every permission used -->
<key>NSCameraUsageDescription</key>
<string>Take photos for your profile</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Select photos from your library</string>

<key>NSMicrophoneUsageDescription</key>
<string>Record voice messages</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Find nearby locations</string>

<key>NSFaceIDUsageDescription</key>
<string>Secure login with Face ID</string>

<key>NSUserTrackingUsageDescription</key>
<string>Allow tracking for personalized experience</string>

<!-- Export compliance — set false unless using non-exempt encryption -->
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

## Signing & Certificates

1. **Apple Developer Program**: $99/year at developer.apple.com
2. **Certificates**: Create Distribution certificate in Xcode → Preferences → Accounts
3. **Provisioning Profile**: App Store Distribution profile for your Bundle ID
4. **Xcode signing**: Set to "Automatically manage signing" for simplicity

## App Store Connect Setup

1. Go to https://appstoreconnect.apple.com → My Apps → **+** → New App
2. Fill in:
   - Platform: iOS
   - Name: Your App Name (max 30 chars)
   - Primary Language
   - Bundle ID (must match `capacitor.config.ts`)
   - SKU (unique internal identifier)

## Version Information

- **Promotional Text** (170 chars): Appears above description, can be updated without new build
- **Description** (4000 chars): Full app description
- **Keywords** (100 chars, comma-separated): Used for search ranking
- **Support URL**: Required
- **What's New**: Required for updates

## Build Upload

```bash
# Via Xcode
# Product → Archive → Distribute App → App Store Connect

# Via Fastlane
fastlane ios release

# Via xcrun (CI/CD)
xcrun altool --upload-app --type ios --file App.ipa \
  --apiKey KEY_ID --apiIssuer ISSUER_ID
```

## App Privacy (Required)

Complete the Data collection questionnaire:

- Contact Info, Health & Fitness, Financial Info, Location
- Identifiers, Usage Data, Diagnostics
- Declare data linked to user identity vs. not linked

## Age Rating

Complete the content questionnaire — covers:

- Violence, sexual content, profanity, gambling, horror
- Result determines age rating (4+, 9+, 12+, 17+)

## Phased Release

Enable in App Store Connect → Version → Phased Release:

- Day 1: 1% of users
- Day 2: 2%
- Day 3: 5%
- Day 4: 10%
- Day 5: 20%
- Day 6: 50%
- Day 7: 100%

Can pause at any day if crash rate spikes. Full release can be forced at any time.

## TestFlight (Beta Testing)

- Internal testers: up to 100, instant availability
- External testers: up to 10,000, requires Beta App Review
- Builds expire after 90 days
- Add testers by email or public link

## Resources

- App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines
- App Store Connect: https://appstoreconnect.apple.com
