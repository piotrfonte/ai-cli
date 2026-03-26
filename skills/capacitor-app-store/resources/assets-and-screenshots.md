# App Assets & Screenshots

## Generating Icons and Splash Screens

```bash
# Install capacitor-assets
bun add -D @capacitor/assets

# Place source images:
# resources/icon.png        — 1024×1024, no transparency (iOS requirement)
# resources/icon-foreground.png  — 1024×1024, Android adaptive icon foreground
# resources/splash.png      — 2732×2732, centered logo

# Generate all sizes
bunx capacitor-assets generate --iconBackgroundColor '#ffffff'
```

This generates all required sizes for both platforms automatically.

## iOS App Icon Sizes

| Size   | Scale  | Usage             |
| ------ | ------ | ----------------- |
| 20pt   | 2x, 3x | Notification      |
| 29pt   | 2x, 3x | Settings          |
| 40pt   | 2x, 3x | Spotlight         |
| 60pt   | 2x, 3x | App Icon (iPhone) |
| 76pt   | 1x, 2x | iPad              |
| 83.5pt | 2x     | iPad Pro          |
| 1024pt | 1x     | App Store listing |

Place in `ios/App/App/Assets.xcassets/AppIcon.appiconset/`.

## Android App Icon Sizes

| Density    | Size    | Folder            |
| ---------- | ------- | ----------------- |
| mdpi       | 48×48   | mipmap-mdpi       |
| hdpi       | 72×72   | mipmap-hdpi       |
| xhdpi      | 96×96   | mipmap-xhdpi      |
| xxhdpi     | 144×144 | mipmap-xxhdpi     |
| xxxhdpi    | 192×192 | mipmap-xxxhdpi    |
| Play Store | 512×512 | Upload separately |

Also required: Adaptive icon with separate foreground + background layers.

## iOS Screenshot Sizes

| Device                   | Dimensions | Required           |
| ------------------------ | ---------- | ------------------ |
| iPhone 6.7" (14 Pro Max) | 1290×2796  | Yes                |
| iPhone 6.5" (11 Pro Max) | 1284×2778  | Yes                |
| iPhone 5.5" (8 Plus)     | 1242×2208  | Yes                |
| iPad Pro 12.9"           | 2048×2732  | If supporting iPad |
| iPad Pro 11"             | 1668×2388  | If supporting iPad |

- Minimum 1 screenshot per required size, maximum 10
- Can use same screenshots for 6.7" and 6.5" if dimensions match

## Android Screenshot Sizes

| Type       | Dimensions             | Required      |
| ---------- | ---------------------- | ------------- |
| Phone      | 1080×1920 to 1080×2400 | Yes (2–8)     |
| 7" Tablet  | 1200×1920              | If supporting |
| 10" Tablet | 1600×2560              | If supporting |

## Feature Graphic (Android)

- Size: **1024×500** pixels
- Required for Play Store listing
- Appears at top of store listing when app is featured

## Automated Screenshot Generation

```typescript
// Using Playwright for automated screenshots
import { test } from "@playwright/test";

const devices = [
  { name: "iPhone-14-Pro-Max", viewport: { width: 430, height: 932 } },
  { name: "iPhone-8-Plus", viewport: { width: 414, height: 736 } },
  { name: "Pixel-7", viewport: { width: 412, height: 915 } },
];

test("generate screenshots", async ({ page }) => {
  for (const device of devices) {
    await page.setViewportSize(device.viewport);

    await page.goto("/");
    await page.screenshot({
      path: `screenshots/${device.name}-home.png`,
      fullPage: false,
    });

    await page.goto("/feature");
    await page.screenshot({
      path: `screenshots/${device.name}-feature.png`,
    });
  }
});
```

## Screenshot Best Practices

- Show the app's core value in the first screenshot
- Use device frames for a polished look
- Add captions/overlays to explain features
- Localize screenshots for key markets
- Test screenshots render correctly at small sizes in search results
