# Android Play Store Submission

## build.gradle Configuration

```groovy
// android/app/build.gradle
android {
    defaultConfig {
        applicationId "com.yourcompany.yourapp"
        minSdkVersion 22
        targetSdkVersion 34
        versionCode 1          // Increment on every upload
        versionName "1.0.0"    // User-visible version

        // 64-bit support (required)
        ndk {
            abiFilters 'armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'
        }
    }

    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
        }
    }

    bundle {
        language { enableSplit = true }
        density { enableSplit = true }
        abi { enableSplit = true }
    }
}
```

## Build AAB (Required for New Apps)

```bash
# Build release AAB
cd android && ./gradlew bundleRelease

# Output: android/app/build/outputs/bundle/release/app-release.aab

# Sign with release keystore (if not configured in build.gradle)
jarsigner -verbose -sigalg SHA256withRSA -digestalg SHA-256 \
  -keystore release.keystore app-release.aab alias_name
```

## Keystore Setup

```bash
# Generate release keystore (do this ONCE, keep it safe)
keytool -genkey -v -keystore release.keystore \
  -alias release -keyalg RSA -keysize 2048 -validity 10000

# Add to android/app/build.gradle signingConfigs
signingConfigs {
    release {
        storeFile file('../../release.keystore')
        storePassword System.getenv('KEYSTORE_PASSWORD')
        keyAlias 'release'
        keyPassword System.getenv('KEY_PASSWORD')
    }
}
```

**CRITICAL**: Never commit the keystore to git. Store passwords in environment variables or a secrets manager.

## Play Console Setup

1. Go to https://play.google.com/console → All apps → **Create app**
2. Fill in: App name, Default language, App or game, Free or paid
3. Complete all required setup tasks in the dashboard

## Store Listing

- **Short description** (80 chars): Appears in search results
- **Full description** (4000 chars): Full app description
- **Screenshots**: 2–8 per device type (see assets-and-screenshots.md)
- **Feature graphic**: 1024×500 (required)
- **App icon**: 512×512 PNG

## Content Rating

Complete the IARC questionnaire:

- Violence, sexual content, language, controlled substances
- Result generates ratings for all regions automatically

## Data Safety Form (Required)

Declare:

- Data types collected (location, contacts, personal info, etc.)
- Whether data is shared with third parties
- Security practices (data encrypted in transit, deletion requests)

## Release Tracks

| Track            | Purpose                    | Review Required |
| ---------------- | -------------------------- | --------------- |
| Internal testing | Up to 100 testers, instant | No              |
| Closed testing   | Invite-only groups         | Yes             |
| Open testing     | Public beta                | Yes             |
| Production       | Full release               | Yes             |

**Recommended flow**: Internal → Closed → Open → Production (10% rollout → 100%)

## Rollout Strategy

```
Production release → set rollout to 10%
Monitor: crash rate, ANR rate, ratings
If stable after 24-48h → increase to 50% → 100%
If issues → halt rollout, fix, upload new build
```

## Resources

- Google Play Policy Center: https://play.google.com/about/developer-content-policy
- Google Play Console: https://play.google.com/console
