---
name: capacitor-app-store
description: Complete guide to publishing Capacitor apps to Apple App Store and Google Play Store including app preparation, screenshots, metadata, review guidelines, submission process, and phased rollout.
user-invocable: true
---

# Publishing to App Stores

## Quick Start — Pre-Submission Checklist

```
Universal:  icon, splash, bundle ID, version, privacy policy, screenshots
iOS:        Developer Program, signing certs, Info.plist descriptions, export compliance
Android:    Play Developer account, release keystore, target SDK 34+, data safety form
```

## Version & Build Numbers

- DO increment build number on every upload (iOS: `CFBundleVersion`, Android: `versionCode`)
- DO use semantic versioning for user-visible version (`1.2.3`)
- DO keep iOS and Android version names in sync
- DO NOT reuse build numbers — stores reject duplicate uploads

```bash
# Generate icons and splash screens from a single source image
bun add -D @capacitor/assets
bunx capacitor-assets generate --iconBackgroundColor '#ffffff'
```

## iOS Rules

- DO complete all `NS*UsageDescription` keys in Info.plist for every permission used
- DO set `ITSAppUsesNonExemptEncryption` to `false` (unless using non-exempt encryption)
- DO provide a demo account in review notes if login is required
- DO implement Sign in with Apple if any third-party social login is offered
- DO NOT hardcode development server URLs in production builds

## Android Rules

- DO build AAB format (required for new apps on Play Store)
- DO enable ProGuard/R8 for release builds (`minifyEnabled true`)
- DO include all ABI filters for 64-bit support
- DO complete the Data Safety form before submission
- DO NOT target SDK below API 34

## Common Rejection Reasons

### iOS

| Reason                                | Fix                                      |
| ------------------------------------- | ---------------------------------------- |
| Crashes on launch                     | Test on real devices, all screen sizes   |
| Missing privacy descriptions          | Add all `NS*UsageDescription` keys       |
| Guideline 4.2 (Minimum Functionality) | Ensure meaningful native features        |
| Guideline 5.1.1 (Data Collection)     | Justify data usage in privacy section    |
| Login issues during review            | Provide demo credentials in review notes |

### Android

| Reason              | Fix                                    |
| ------------------- | -------------------------------------- |
| Target SDK too low  | Update to API 34+                      |
| Policy violation    | Review Play Developer policies         |
| Missing data safety | Complete the Data Safety questionnaire |
| Crashes/ANRs        | Fix stability, test on real devices    |

## Submission Workflow

### iOS

1. Archive in Xcode → Distribute to App Store Connect
2. Fill metadata: description, screenshots, privacy, age rating
3. Submit for review (answer export compliance questions)

### Android

1. `cd android && ./gradlew bundleRelease`
2. Upload AAB to Play Console → Create new release
3. Start with Internal Testing track, promote to Production

### Phased Rollout

- **iOS**: Enable in App Store Connect — 7-day gradual (1% → 2% → 5% → 10% → 20% → 50% → 100%)
- **Android**: Set rollout percentage per release — monitor crash rate before increasing

> See `resources/ios-submission.md` for full App Store Connect walkthrough, Info.plist configuration, and signing setup.

> See `resources/android-submission.md` for Play Console walkthrough, build.gradle configuration, and release tracks.

> See `resources/assets-and-screenshots.md` for all icon sizes, screenshot dimensions, feature graphic specs, and automated generation.

## References

- `resources/ios-submission.md` — App Store Connect, Info.plist, certificates, phased rollout
- `resources/android-submission.md` — Play Console, build.gradle, release tracks, data safety
- `resources/assets-and-screenshots.md` — icon sizes, screenshot dimensions, generation scripts
