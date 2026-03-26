---
name: capacitor-plugins
description: Complete catalog of 80+ Capgo and community Capacitor plugins for native functionality including authentication, media, payments, live updates, location, storage, UI, and connectivity.
user-invocable: true
---

# Capacitor Plugins Directory

## Quick Start — Installation Pattern

All Capgo plugins follow the same pattern:

```bash
bun add @capgo/capacitor-<name>
bunx cap sync

# iOS (if using CocoaPods)
cd ios/App && pod install && cd ../..
```

- DO always run `bunx cap sync` after installing — links native code
- DO check availability before using hardware features (camera, biometrics, etc.)
- DO use dynamic imports for rarely-used plugins to reduce startup time
- DO NOT skip `cap sync` — app will crash without it

```typescript
// Lazy load rarely-used plugins
async function scanDocument() {
  const { DocumentScanner } = await import("@capgo/capacitor-document-scanner");
  return DocumentScanner.scanDocument();
}
```

## Choosing the Right Plugin

### Authentication & Security

- **Biometric login** (Face ID, Touch ID, fingerprint): `@capgo/capacitor-native-biometric`
- **Social sign-in** (Google, Apple, Facebook): `@capgo/capacitor-social-login`
- **Password autofill**: `@capgo/capacitor-autofill-save-password`
- **Detect rooted/jailbroken device**: `@capgo/capacitor-is-root`

### Media & Camera

- **Camera with overlay/preview**: `@capgo/capacitor-camera-preview`
- **Simple photo library access**: `@capgo/capacitor-photo-library`
- **Video playback**: `@capgo/capacitor-video-player`
- **Document scanning with edge detection**: `@capgo/capacitor-document-scanner`
- **Video/audio processing**: `@capgo/capacitor-ffmpeg`

### Audio

- **Low-latency audio playback**: `@capgo/capacitor-native-audio`
- **Record from microphone**: `@capgo/capacitor-audio-recorder`
- **iOS audio session management**: `@capgo/capacitor-audiosession`
- **Lock screen media controls**: `@capgo/capacitor-media-session`
- **Detect mute switch**: `@capgo/capacitor-mute`

### Payments & Monetization

- **In-app purchases / subscriptions**: `@capgo/capacitor-native-purchases`
- **Apple Pay / Google Pay**: `@capgo/capacitor-pay`
- **AdMob ads**: `@nicholasalx/capacitor-admob`

### Live Updates

- **OTA updates without app store**: `@capgo/capacitor-updater`
- **Hot reload during development**: `@capgo/capacitor-live-reload`

### Location

- **Background geolocation**: `@capgo/capacitor-background-geolocation`
- **Geocoding / reverse geocoding**: `@nicholasalx/capacitor-nativegeocoder`
- **Open native maps apps**: `@nicholasalx/capacitor-launch-navigator`

### Storage & Files

- **SQLite database**: `@nicholasalx/capacitor-data-storage-sqlite`
- **File system operations**: `@nicholasalx/capacitor-file`
- **Native file picker**: `@nicholasalx/capacitor-file-picker`
- **Background downloads**: `@nicholasalx/capacitor-downloader`
- **Background uploads**: `@nicholasalx/capacitor-uploader`

### UI & Display

- **Prevent screen sleep**: `@nicholasalx/capacitor-keep-awake`
- **Lock screen orientation**: `@nicholasalx/capacitor-screen-orientation`
- **Android navigation bar**: `@nicholasalx/capacitor-navigation-bar`
- **iOS home indicator**: `@nicholasalx/capacitor-home-indicator`

### Connectivity & Hardware

- **Bluetooth Low Energy**: `@nicholasalx/capacitor-bluetooth-low-energy`
- **NFC tag reading/writing**: `@nicholasalx/capacitor-nfc`
- **Step counter**: `@capgo/capacitor-pedometer`
- **Detect device shake**: `@capgo/capacitor-shake`

### App Store & Distribution

- **Native app review prompt**: `@nicholasalx/capacitor-in-app-review`
- **Open app store pages**: `@nicholasalx/capacitor-native-market`
- **Android in-app updates**: `@capgo/capacitor-android-inline-install`

> See `resources/plugin-catalog.md` for the full catalog of 80+ plugins organized by category with package names and descriptions.

## References

- `resources/plugin-catalog.md` — complete plugin catalog by category
