# Keyboard Patterns

## React Hook — useKeyboardHeight

Encapsulate keyboard height tracking in a reusable hook:

```typescript
import { useEffect, useState } from 'react'
import { Keyboard } from '@capacitor/keyboard'
import { Capacitor } from '@capacitor/core'

export function useKeyboardHeight() {
  const [keyboardHeight, setKeyboardHeight] = useState(0)

  useEffect(() => {
    if (!Capacitor.isNativePlatform()) return

    const showListener = Keyboard.addListener('keyboardWillShow', (info) => {
      setKeyboardHeight(info.keyboardHeight)
    })
    const hideListener = Keyboard.addListener('keyboardWillHide', () => {
      setKeyboardHeight(0)
    })

    return () => {
      showListener.then(l => l.remove())
      hideListener.then(l => l.remove())
    }
  }, [])

  return keyboardHeight
}

// Usage
function ChatInput() {
  const keyboardHeight = useKeyboardHeight()
  return (
    <div style={{ paddingBottom: keyboardHeight }}>
      <input type="text" />
    </div>
  )
}
```

## Scroll to Active Input

Ensure the focused input is visible when the keyboard appears:

```typescript
Keyboard.addListener("keyboardWillShow", async () => {
  const activeElement = document.activeElement as HTMLElement;

  if (activeElement) {
    // Wait for keyboard animation to start
    await new Promise((r) => setTimeout(r, 100));

    activeElement.scrollIntoView({
      behavior: "smooth",
      block: "center",
    });
  }
});
```

## iOS Accessory Bar

The toolbar above the keyboard (with Previous/Next/Done buttons):

```typescript
// Show the accessory bar (default: visible)
await Keyboard.setAccessoryBarVisible({ isVisible: true });

// Hide the accessory bar
await Keyboard.setAccessoryBarVisible({ isVisible: false });
```

Useful for full-screen input experiences where the toolbar is distracting.

## Multi-Field Form Navigation

Move focus between fields on Enter, hide keyboard on last field:

```typescript
function setupFormNavigation(form: HTMLFormElement) {
  const inputs = Array.from(form.querySelectorAll("input, textarea"));

  inputs.forEach((input, index) => {
    input.addEventListener("keypress", async (e: Event) => {
      const keyEvent = e as KeyboardEvent;
      if (keyEvent.key !== "Enter") return;

      keyEvent.preventDefault();
      const next = inputs[index + 1] as HTMLElement | undefined;

      if (next) {
        next.focus();
      } else {
        await Keyboard.hide();
        form.dispatchEvent(new Event("submit"));
      }
    });
  });
}
```

## Android: windowSoftInputMode

Control how Android resizes the layout when the keyboard appears:

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<activity
    android:windowSoftInputMode="adjustResize">
    <!-- adjustResize: resize the layout (recommended with resize: 'none') -->
    <!-- adjustPan: pan the layout up (default) -->
    <!-- adjustNothing: no automatic adjustment -->
</activity>
```

Pair with `resize: 'none'` in `capacitor.config.ts` when using `adjustResize` for full manual control.

## Platform Differences

| Behavior                                  | iOS           | Android  |
| ----------------------------------------- | ------------- | -------- |
| Keyboard height in `keyboardWillShow`     | Accurate      | Accurate |
| `keyboardWillShow` fires before animation | Yes           | Yes      |
| Auto-zoom on small inputs                 | Yes (< 16px)  | No       |
| Accessory bar                             | Yes           | No       |
| Safe area inset at bottom                 | Yes           | No       |
| `windowSoftInputMode`                     | No equivalent | Yes      |

## Cleanup Pattern

Always remove listeners to prevent memory leaks:

```typescript
useEffect(() => {
  let showHandle: PluginListenerHandle;
  let hideHandle: PluginListenerHandle;

  async function setup() {
    showHandle = await Keyboard.addListener("keyboardWillShow", handler);
    hideHandle = await Keyboard.addListener("keyboardWillHide", handler);
  }

  setup();

  return () => {
    showHandle?.remove();
    hideHandle?.remove();
  };
}, []);
```
