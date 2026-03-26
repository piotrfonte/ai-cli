---
name: capacitor-keyboard
description: Keyboard handling in Capacitor apps including visibility detection, height tracking, accessory bar, scroll behavior, input focus, and platform-specific configuration.
user-invocable: true
---

# Keyboard Handling in Capacitor

## Quick Start

```bash
bun add @capacitor/keyboard
bunx cap sync
```

```typescript
import { Capacitor } from "@capacitor/core";
import { Keyboard } from "@capacitor/keyboard";

// Show / hide
await Keyboard.show();
await Keyboard.hide();

// Listen for events
Keyboard.addListener("keyboardWillShow", (info) => {
  console.log("Keyboard height:", info.keyboardHeight);
});
Keyboard.addListener("keyboardWillHide", () => {
  console.log("Keyboard hiding");
});
```

## Configuration

```typescript
// capacitor.config.ts
plugins: {
  Keyboard: {
    resize: 'body',   // 'body' | 'ionic' | 'native' | 'none'
    style: 'default', // 'dark' | 'light' | 'default'
    resizeOnFullScreen: true,
  },
},
```

| Resize Mode | Description                                         |
| ----------- | --------------------------------------------------- |
| `body`      | Resize the body element (recommended for most apps) |
| `ionic`     | Use Ionic's keyboard handling                       |
| `native`    | Native WebView resize                               |
| `none`      | No automatic resize — handle manually               |

## Keyboard Height CSS Variable (Recommended Pattern)

- DO use a CSS variable to track keyboard height — works with any layout
- DO listen on `keyboardWillShow` (not `keyboardDidShow`) for smooth animation
- DO guard with `Capacitor.isNativePlatform()` — keyboard plugin is native-only
- DO NOT use fixed pixel values for bottom offsets — keyboard height varies by device

```typescript
if (Capacitor.isNativePlatform()) {
  Keyboard.addListener("keyboardWillShow", (info) => {
    document.body.style.setProperty(
      "--keyboard-height",
      `${info.keyboardHeight}px`,
    );
  });
  Keyboard.addListener("keyboardWillHide", () => {
    document.body.style.setProperty("--keyboard-height", "0px");
  });
}
```

```css
.chat-input {
  position: fixed;
  bottom: calc(var(--keyboard-height, 0px) + env(safe-area-inset-bottom));
  left: 0;
  right: 0;
}
```

## Form Rules

- DO use `font-size: 16px` minimum on inputs — prevents iOS auto-zoom
- DO hide keyboard on form submit before processing
- DO move focus to next field on Enter, hide keyboard on last field
- DO NOT rely on `resize: 'native'` for chat/messaging layouts — use CSS variable instead

```typescript
// Hide keyboard on submit
form.addEventListener("submit", async (e) => {
  e.preventDefault();
  await Keyboard.hide();
  // process form...
});
```

## Troubleshooting

| Issue                          | Solution                                         |
| ------------------------------ | ------------------------------------------------ |
| Content hidden behind keyboard | Use `resize: 'body'` or CSS variable pattern     |
| Jerky animation                | Use `keyboardWillShow` not `keyboardDidShow`     |
| iOS input zoom                 | Set `font-size: 16px` on all inputs              |
| Android content overlap        | Set `windowSoftInputMode` in AndroidManifest.xml |
| Keyboard not hiding            | Call `Keyboard.hide()` explicitly on submit      |

> See `resources/keyboard-patterns.md` for scroll-to-input, iOS accessory bar, React hook pattern, and platform-specific differences.

## References

- `resources/keyboard-patterns.md` — scroll-to-input, accessory bar, React hook, platform differences
