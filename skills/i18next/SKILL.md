---
name: i18next
description: i18next v21 and react-i18next v11 patterns for internationalization including useTranslation hook, interpolation, pluralization, namespaces, and Trans component.
user-invocable: true
---

# i18next v21 + react-i18next v11

## Quick Start

```typescript
import { useTranslation } from 'react-i18next';

function WelcomeBanner() {
  const { t, i18n, ready } = useTranslation();
  if (!ready) return <div>Loading...</div>;
  return (
    <div>
      <h1>{t('welcome.title')}</h1>
      <p>{t('greeting', { name: 'Alice' })}</p>
      <span>{i18n.language}</span>
    </div>
  );
}
```

## Core Rules

- DO use `useTranslation()` hook in functional components
- DO handle `ready` state (project uses `useSuspense: false`)
- DO use `_one`/`_other` plural suffixes (v21+) — NOT `_plural`
- DO use `{{variable}}` double curly braces for interpolation
- DO use `keyPrefix` to scope translations: `useTranslation('ns', { keyPrefix: 'form' })`
- DO NOT concatenate translated strings — use single key with interpolation
- DO NOT use `_plural` suffix (legacy v3 behavior)

## Interpolation

```json
{ "greeting": "Hello, {{name}}!", "notification": "You have {{count}} messages from {{sender}}." }
```

```typescript
t('greeting', { name: 'Alice' });           // "Hello, Alice!"
t('notification', { count: 3, sender: 'Bob' }); // "You have 3 messages from Bob."
t('missing.key', 'Default text');            // fallback
```

## Pluralization (v21 — ICU-aligned)

```json
{ "item_one": "{{count}} item", "item_other": "{{count}} items", "cart_zero": "Cart is empty" }
```

```typescript
t('item', { count: 1 }); // "1 item"
t('item', { count: 5 }); // "5 items"
t('cart', { count: 0 });  // "Cart is empty"
```

Ordinal: `_ordinal_one`, `_ordinal_two`, `_ordinal_few`, `_ordinal_other`

## Namespaces

```typescript
// Single namespace
const { t } = useTranslation('dashboard');
t('stats.title');

// Multiple namespaces
const { t } = useTranslation(['dashboard', 'common']);
t('stats.title');                        // from 'dashboard'
t('buttons.save', { ns: 'common' });     // from 'common'
```

File structure: `src/locales/{lang}/{namespace}.json`

## Trans Component (JSX in translations)

```json
{ "termsNotice": "Agree to our <termsLink>Terms</termsLink> and <privacyLink>Privacy</privacyLink>." }
```

```typescript
<Trans i18nKey="termsNotice" components={{
  termsLink: <a href="/terms" />,
  privacyLink: <a href="/privacy" />,
}} />
```

## Language Switching

```typescript
const { i18n } = useTranslation();
i18n.changeLanguage('de');  // persisted to localStorage automatically
i18n.language;               // current language
i18n.resolvedLanguage;       // without region (e.g., 'en' not 'en-US')
```

## TypeScript Typing

```typescript
// src/i18n/types.ts
import 'react-i18next';
import type common from '../locales/en/common.json';

declare module 'react-i18next' {
  interface CustomTypeOptions {
    defaultNS: 'common';
    resources: { common: typeof common };
  }
}
```

Provides autocomplete and type errors for invalid keys.

## Formatting

```json
{ "price": "Price: {{val, number(style: currency; currency: USD)}}" }
```

```typescript
t('price', { val: 42.5 }); // "Price: $42.50"
```

## Key Naming Conventions

- Use dot-separated keys: `page.title`, `stats.activeUsers`, `actions.refresh`
- Group by feature area in JSON
- Use context suffixes for variants: `greeting_male`, `greeting_female`

## Common Mistakes

- DO NOT use `_plural` — use `_one`/`_other` (v21+)
- DO NOT forget `{ count: number }` for plurals
- DO NOT hardcode user-facing strings — always use `t()`
- DO NOT use `useMemo(() => t('key'), [])` — include `t` in deps

## References

- `resources/translation-patterns.md` — interpolation, plural, context patterns
- `resources/setup-guide.md` — init config, detection, namespaces, TypeScript setup
