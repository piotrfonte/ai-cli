# i18next Setup Guide

Complete setup reference for i18next v21, react-i18next v11, and i18next-browser-languagedetector v6 in a TypeScript React project.

## Full i18next.init() Configuration

### Minimal Setup

```typescript
// src/i18n/i18n.ts
import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';

i18n.use(initReactI18next).init({
  resources: {
    en: {
      translation: {
        welcome: 'Welcome',
      },
    },
  },
  lng: 'en',
  fallbackLng: 'en',
  interpolation: {
    escapeValue: false,
  },
});

export default i18n;
```

### Production Setup with All Options

```typescript
// src/i18n/i18n.ts
import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';
import LanguageDetector from 'i18next-browser-languagedetector';

// Import translation files
import enCommon from '../locales/en/common.json';
import enAuth from '../locales/en/auth.json';
import enDashboard from '../locales/en/dashboard.json';
import enSettings from '../locales/en/settings.json';
import enErrors from '../locales/en/errors.json';

import deCommon from '../locales/de/common.json';
import deAuth from '../locales/de/auth.json';
import deDashboard from '../locales/de/dashboard.json';
import deSettings from '../locales/de/settings.json';
import deErrors from '../locales/de/errors.json';

i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    // --- Resources ---
    resources: {
      en: {
        common: enCommon,
        auth: enAuth,
        dashboard: enDashboard,
        settings: enSettings,
        errors: enErrors,
      },
      de: {
        common: deCommon,
        auth: deAuth,
        dashboard: deDashboard,
        settings: deSettings,
        errors: deErrors,
      },
    },

    // --- Language ---
    // lng: 'en',              // Omit when using LanguageDetector
    fallbackLng: 'en',
    supportedLngs: ['en', 'de'],
    nonExplicitSupportedLngs: false,    // Don't match 'en-US' to 'en' unless listed
    load: 'languageOnly',               // Load 'en' not 'en-US'
    cleanCode: true,                    // Lowercase language codes

    // --- Namespaces ---
    defaultNS: 'common',
    fallbackNS: 'common',              // Fall back to common if key missing in namespace
    ns: ['common', 'auth', 'dashboard', 'settings', 'errors'],

    // --- Interpolation ---
    interpolation: {
      escapeValue: false,               // React handles XSS protection
      formatSeparator: ',',
      skipOnVariables: true,
    },

    // --- Key handling ---
    keySeparator: '.',                  // Nested key separator
    nsSeparator: ':',                   // Namespace separator (auth:login.title)
    pluralSeparator: '_',              // Plural suffix separator
    contextSeparator: '_',            // Context suffix separator
    returnNull: false,                 // Return empty string instead of null
    returnEmptyString: false,          // Treat empty string as missing

    // --- Missing keys ---
    saveMissing: false,                // Set true in dev to report missing keys
    missingKeyHandler: (lngs, ns, key, fallbackValue) => {
      if (process.env.NODE_ENV === 'development') {
        console.warn(`Missing translation: [${ns}] ${key} (${lngs.join(', ')})`);
      }
    },

    // --- Detection ---
    detection: {
      order: ['localStorage', 'navigator', 'htmlTag'],
      caches: ['localStorage'],
      lookupLocalStorage: 'i18nextLng',
    },

    // --- React ---
    react: {
      useSuspense: false,              // Non-suspense mode
      bindI18n: 'languageChanged',     // Re-render on language change
      bindI18nStore: '',               // Don't re-render on store events
      transEmptyNodeValue: '',         // Value for empty Trans nodes
      transSupportBasicHtmlNodes: true, // Allow <br/>, <strong>, etc. in Trans
      transKeepBasicHtmlNodesFor: ['br', 'strong', 'i', 'p', 'em', 'b', 'u', 'small', 'sub', 'sup'],
    },

    // --- Debug ---
    debug: process.env.NODE_ENV === 'development',
  });

export default i18n;
```

### Configuration Options Reference

| Option | Type | Default | Description |
|---|---|---|---|
| `lng` | `string` | - | Fixed language (omit when using detector) |
| `fallbackLng` | `string \| object` | `'dev'` | Fallback language(s) |
| `supportedLngs` | `string[]` | `false` | Restrict to these languages |
| `defaultNS` | `string` | `'translation'` | Default namespace |
| `fallbackNS` | `string \| string[]` | `false` | Fallback namespace(s) |
| `keySeparator` | `string \| false` | `'.'` | Separator for nested keys |
| `nsSeparator` | `string \| false` | `':'` | Namespace separator |
| `returnNull` | `boolean` | `true` | Return null for missing keys |
| `debug` | `boolean` | `false` | Log debug information |
| `saveMissing` | `boolean` | `false` | Send missing keys to backend |

## LanguageDetector Setup

### Installation

```bash
pnpm add i18next-browser-languagedetector
```

### Configuration

```typescript
import LanguageDetector from 'i18next-browser-languagedetector';

i18n.use(LanguageDetector).init({
  detection: {
    // Order of detection sources (first match wins)
    order: ['localStorage', 'navigator', 'htmlTag', 'path', 'subdomain'],

    // Where to cache the detected language
    caches: ['localStorage'],

    // Exclude caching for certain languages
    excludeCacheFor: ['cimode'],

    // localStorage settings
    lookupLocalStorage: 'i18nextLng',

    // Cookie settings (if using cookie caching)
    lookupCookie: 'i18next',
    cookieMinutes: 10080, // 7 days
    cookieDomain: 'example.com',

    // Query string settings
    lookupQuerystring: 'lng',

    // Path settings (e.g., /en/about)
    lookupFromPathIndex: 0,

    // Subdomain settings (e.g., en.example.com)
    lookupFromSubdomainIndex: 0,

    // HTML tag settings
    htmlTag: document.documentElement,

    // Only detect languages that are available
    checkWhitelist: true,
  },

  supportedLngs: ['en', 'de', 'fr', 'es'],
  fallbackLng: 'en',
});
```

### Detection Order Explained

| Source | How It Works | Best For |
|---|---|---|
| `localStorage` | Reads `localStorage.getItem('i18nextLng')` | Persisting user's explicit choice |
| `navigator` | Reads `navigator.language` / `navigator.languages` | First-time visitors |
| `htmlTag` | Reads `<html lang="...">` | Server-rendered apps |
| `path` | Reads URL path segment (`/en/about`) | SEO-friendly multilingual routes |
| `subdomain` | Reads subdomain (`en.example.com`) | Separate language subdomains |
| `querystring` | Reads URL parameter (`?lng=en`) | Debugging, email links |
| `cookie` | Reads cookie value | Cross-subdomain persistence |

### Recommended Detection Order

For a single-page application using localStorage:

```typescript
detection: {
  order: ['localStorage', 'navigator', 'htmlTag'],
  caches: ['localStorage'],
  lookupLocalStorage: 'i18nextLng',
}
```

## Namespace Organization

### Recommended Namespace Structure

```
src/locales/
  en/
    common.json         # Shared UI: buttons, labels, errors, validation
    auth.json           # Login, signup, password reset, MFA
    dashboard.json      # Dashboard stats, charts, summaries
    settings.json       # User settings, preferences
    errors.json         # Error messages and codes
    notifications.json  # Push/in-app notification content
  de/
    common.json
    auth.json
    dashboard.json
    settings.json
    errors.json
    notifications.json
```

### Namespace Content Guidelines

**common.json** - Shared across the entire app:

```json
{
  "buttons": {
    "save": "Save",
    "cancel": "Cancel",
    "delete": "Delete",
    "confirm": "Confirm",
    "back": "Back",
    "next": "Next",
    "close": "Close",
    "submit": "Submit",
    "retry": "Retry"
  },
  "labels": {
    "email": "Email",
    "password": "Password",
    "name": "Name",
    "search": "Search",
    "loading": "Loading..."
  },
  "validation": {
    "required": "{{field}} is required",
    "minLength": "{{field}} must be at least {{min}} characters",
    "maxLength": "{{field}} must be at most {{max}} characters",
    "email": "Please enter a valid email address",
    "passwordMatch": "Passwords do not match"
  },
  "errors": {
    "generic": "Something went wrong. Please try again.",
    "networkError": "Network error. Check your connection.",
    "notFound": "The requested resource was not found.",
    "unauthorized": "You are not authorized to perform this action."
  },
  "time": {
    "justNow": "Just now",
    "minutesAgo_one": "{{count}} minute ago",
    "minutesAgo_other": "{{count}} minutes ago",
    "hoursAgo_one": "{{count}} hour ago",
    "hoursAgo_other": "{{count}} hours ago",
    "daysAgo_one": "{{count}} day ago",
    "daysAgo_other": "{{count}} days ago"
  }
}
```

**auth.json** - Authentication flows:

```json
{
  "login": {
    "title": "Sign In",
    "subtitle": "Welcome back",
    "form": {
      "emailLabel": "Email Address",
      "emailPlaceholder": "Enter your email",
      "passwordLabel": "Password",
      "passwordPlaceholder": "Enter your password",
      "rememberMe": "Remember me",
      "submitButton": "Sign In",
      "forgotPassword": "Forgot your password?"
    },
    "errors": {
      "invalidCredentials": "Invalid email or password",
      "accountLocked": "Account locked. Please try again in {{minutes}} minutes.",
      "tooManyAttempts": "Too many attempts. Please try again later."
    },
    "success": "Welcome back, {{name}}!"
  },
  "signup": {
    "title": "Create Account",
    "subtitle": "Get started for free",
    "form": {
      "nameLabel": "Full Name",
      "namePlaceholder": "Enter your full name",
      "submitButton": "Create Account",
      "termsAgreement": "I agree to the <termsLink>Terms of Service</termsLink>"
    }
  }
}
```

### Using Namespaces in Components

```typescript
// Single namespace
function LoginPage() {
  const { t, ready } = useTranslation('auth');
  if (!ready) return <LoginSkeleton />;

  return (
    <div>
      <h1>{t('login.title')}</h1>
      <p>{t('login.subtitle')}</p>
    </div>
  );
}

// Multiple namespaces
function LoginPage() {
  const { t, ready } = useTranslation(['auth', 'common']);
  if (!ready) return <LoginSkeleton />;

  return (
    <div>
      <h1>{t('login.title')}</h1>
      <button>{t('buttons.submit', { ns: 'common' })}</button>
    </div>
  );
}

// With keyPrefix
function LoginForm() {
  const { t } = useTranslation('auth', { keyPrefix: 'login.form' });

  return (
    <form>
      <label>{t('emailLabel')}</label>
      <input placeholder={t('emailPlaceholder')} />
    </form>
  );
}
```

## Lazy Loading Namespaces

### With i18next-http-backend

For large apps, load translation files on demand instead of bundling them.

```bash
pnpm add i18next-http-backend
```

```typescript
import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';
import LanguageDetector from 'i18next-browser-languagedetector';
import HttpBackend from 'i18next-http-backend';

i18n
  .use(HttpBackend)
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    fallbackLng: 'en',
    defaultNS: 'common',
    ns: ['common'], // Only preload common namespace

    backend: {
      // Path to translation files
      loadPath: '/locales/{{lng}}/{{ns}}.json',

      // Optional: custom request function
      // request: (options, url, payload, callback) => { ... },
    },

    detection: {
      order: ['localStorage', 'navigator'],
      caches: ['localStorage'],
      lookupLocalStorage: 'i18nextLng',
    },

    react: {
      useSuspense: false,
    },
  });

export default i18n;
```

### Translation File Location

Place JSON files in the public directory for HTTP backend:

```
public/
  locales/
    en/
      common.json
      auth.json
      dashboard.json
    de/
      common.json
      auth.json
      dashboard.json
```

### Loading Namespaces on Route Change

```typescript
import { useTranslation } from 'react-i18next';

function SettingsPage() {
  // 'settings' namespace is automatically loaded when this component mounts
  const { t, ready } = useTranslation('settings');

  if (!ready) {
    return <SettingsPageSkeleton />;
  }

  return (
    <div>
      <h1>{t('page.title')}</h1>
      <p>{t('page.description')}</p>
    </div>
  );
}
```

### Preloading Namespaces

```typescript
import i18n from '../i18n/i18n';

// Preload before navigation
async function navigateToSettings() {
  await i18n.loadNamespaces('settings');
  router.navigate('/settings');
}

// Or preload multiple namespaces
await i18n.loadNamespaces(['settings', 'notifications']);
```

## Suspense vs Non-Suspense Mode

### Non-Suspense Mode (Project Default)

This project uses `useSuspense: false`. Translations may not be ready on the first render when using lazy loading.

```typescript
i18n.init({
  react: {
    useSuspense: false,
  },
});

function MyComponent() {
  const { t, ready } = useTranslation('dashboard');

  // IMPORTANT: Always check ready in non-suspense mode
  if (!ready) return <Skeleton />;

  return <h1>{t('title')}</h1>;
}
```

### Suspense Mode (Alternative)

If using Suspense, wrap components in a `Suspense` boundary:

```typescript
i18n.init({
  react: {
    useSuspense: true, // Default in react-i18next
  },
});

// Wrap with Suspense
function App() {
  return (
    <Suspense fallback={<GlobalLoader />}>
      <MyComponent />
    </Suspense>
  );
}

// Component doesn't need to check `ready`
function MyComponent() {
  const { t } = useTranslation('dashboard');
  return <h1>{t('title')}</h1>;
}
```

### When to Use Which

| Mode | Use When |
|---|---|
| Non-Suspense (`useSuspense: false`) | Granular loading states per component, no Suspense boundary needed |
| Suspense (`useSuspense: true`) | Using React Suspense for data fetching, want automatic loading boundaries |

## TypeScript Typing

### Type Declaration File

Create a declaration file to enable type-safe translation keys.

```typescript
// src/i18n/i18next.d.ts
import 'react-i18next';

import type common from '../locales/en/common.json';
import type auth from '../locales/en/auth.json';
import type dashboard from '../locales/en/dashboard.json';
import type settings from '../locales/en/settings.json';
import type errors from '../locales/en/errors.json';

declare module 'react-i18next' {
  interface CustomTypeOptions {
    defaultNS: 'common';
    resources: {
      common: typeof common;
      auth: typeof auth;
      dashboard: typeof dashboard;
      settings: typeof settings;
      errors: typeof errors;
    };
  }
}
```

### tsconfig.json Requirements

Ensure `resolveJsonModule` and `esModuleInterop` are enabled:

```json
{
  "compilerOptions": {
    "resolveJsonModule": true,
    "esModuleInterop": true,
    "strict": true
  }
}
```

### Type-Safe Usage

With the declaration in place:

```typescript
const { t } = useTranslation();

// Autocomplete works for keys
t('buttons.save');        // Valid
t('buttons.nonexistent'); // Type error

// Namespace-aware
const { t: tAuth } = useTranslation('auth');
tAuth('login.title');         // Valid - key exists in auth namespace
tAuth('buttons.save');        // Type error - key is in common, not auth

// Multiple namespaces
const { t } = useTranslation(['dashboard', 'common']);
t('stats.title');                      // From dashboard (default)
t('buttons.save', { ns: 'common' });   // From common
```

### Handling Dynamic Keys

When keys are constructed at runtime, TypeScript cannot verify them. Use these patterns:

```typescript
// Type assertion for known-safe dynamic keys
type StatusKey = 'status.active' | 'status.inactive' | 'status.pending';
const key: StatusKey = `status.${user.status}` as StatusKey;
t(key);

// Escape hatch for fully dynamic keys
t(dynamicKey as any);

// Better: use a mapping
const STATUS_KEYS: Record<UserStatus, string> = {
  active: 'status.active',
  inactive: 'status.inactive',
  pending: 'status.pending',
};
t(STATUS_KEYS[user.status]);
```

## Translation File Structure

### JSON File Format

Each namespace has one JSON file per language:

```
src/locales/
  en/
    common.json
    auth.json
  de/
    common.json
    auth.json
```

### File Content Structure

Use nested objects for organization. Keep nesting to a maximum of 3-4 levels.

```json
{
  "page": {
    "title": "Page Title",
    "description": "Page description text"
  },
  "section": {
    "heading": "Section Heading",
    "content": "Section content text",
    "actions": {
      "primary": "Primary Action",
      "secondary": "Secondary Action"
    }
  },
  "item_one": "{{count}} item",
  "item_other": "{{count}} items"
}
```

### Flat Key Format (Alternative)

Some teams prefer flat keys with dot notation in the key name and `keySeparator: false`:

```json
{
  "page.title": "Page Title",
  "page.description": "Page description text",
  "section.heading": "Section Heading"
}
```

```typescript
i18n.init({
  keySeparator: false,
});
```

## Adding a New Language Checklist

Follow these steps when adding support for a new language.

### 1. Create Translation Files

Copy the English locale files as a starting point:

```bash
cp -r src/locales/en src/locales/fr
```

### 2. Translate All Files

Translate each JSON file in the new locale directory. Pay attention to:

- **Pluralization rules**: Check how many plural forms the language needs (use [Unicode CLDR](https://www.unicode.org/cldr/charts/latest/supplemental/language_plural_rules.html))
- **Gender/context variations**: Add context suffixes if the language requires them
- **Interpolation variables**: Keep `{{variable}}` placeholders unchanged
- **Nesting references**: Keep `$t(key)` references unchanged

### 3. Import and Register Resources

```typescript
// src/i18n/i18n.ts
import frCommon from '../locales/fr/common.json';
import frAuth from '../locales/fr/auth.json';
import frDashboard from '../locales/fr/dashboard.json';
import frSettings from '../locales/fr/settings.json';
import frErrors from '../locales/fr/errors.json';

i18n.init({
  resources: {
    // ... existing languages
    fr: {
      common: frCommon,
      auth: frAuth,
      dashboard: frDashboard,
      settings: frSettings,
      errors: frErrors,
    },
  },
  supportedLngs: ['en', 'de', 'fr'], // Add new language
});
```

### 4. Update TypeScript Types (If Applicable)

The type declaration only needs the default language (English) resources. No changes needed unless you add new namespaces.

### 5. Add to Language Selector

```typescript
const LANGUAGES = [
  { code: 'en', label: 'English' },
  { code: 'de', label: 'Deutsch' },
  { code: 'fr', label: 'Fran\u00e7ais' }, // Add new language
] as const;
```

### 6. Test

- [ ] All translation keys resolve without missing key warnings
- [ ] Pluralization works correctly for the language's rules
- [ ] Date, number, and currency formatting respects the locale
- [ ] Language detection picks up the new language from browser settings
- [ ] Language switching works from the UI
- [ ] RTL layout adjustments if applicable (e.g., Arabic, Hebrew)
- [ ] Text expansion does not break layouts (German text is typically 30% longer than English)

## Backend Loading with i18next-http-backend

### Installation

```bash
pnpm add i18next-http-backend
```

### Configuration

```typescript
import HttpBackend from 'i18next-http-backend';

i18n.use(HttpBackend).init({
  backend: {
    // Where to load translations from
    loadPath: '/locales/{{lng}}/{{ns}}.json',

    // Where to send missing translations (if saveMissing: true)
    addPath: '/locales/add/{{lng}}/{{ns}}',

    // Custom headers
    customHeaders: {
      Authorization: 'Bearer token',
    },

    // Request timeout
    requestOptions: {
      cache: 'default',
    },

    // Cross-domain requests
    crossDomain: false,

    // Allow credentials for cross-domain
    withCredentials: false,

    // Override default load behavior
    reloadInterval: false, // Set to milliseconds to auto-reload

    // Custom request function
    request: (
      options: object,
      url: string,
      payload: object,
      callback: (err: Error | null, result: { status: number; data: string }) => void
    ) => {
      fetch(url)
        .then((response) => response.json())
        .then((data) => callback(null, { status: 200, data: JSON.stringify(data) }))
        .catch((err) => callback(err, { status: 500, data: '' }));
    },
  },
});
```

### Caching Strategy

For production, add cache headers to translation file responses:

```
Cache-Control: public, max-age=86400, stale-while-revalidate=604800
```

Or use a service worker to cache translation files for offline support:

```typescript
// In your service worker
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  if (url.pathname.startsWith('/locales/')) {
    event.respondWith(
      caches.open('translations-v1').then((cache) =>
        cache.match(event.request).then(
          (cached) =>
            cached ||
            fetch(event.request).then((response) => {
              cache.put(event.request, response.clone());
              return response;
            })
        )
      )
    );
  }
});
```

### Bundled vs Backend Loading

| Approach | Pros | Cons |
|---|---|---|
| **Bundled** (static imports) | No network requests, instant availability, works offline | Increases bundle size, requires rebuild to update translations |
| **HTTP Backend** | Small bundle, update translations without redeploy, lazy loading | Requires network, loading states needed, CORS considerations |
| **Hybrid** | Bundle default language, lazy-load others | More complex setup |

### Hybrid Approach

```typescript
import enCommon from '../locales/en/common.json';

i18n
  .use(HttpBackend)
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources: {
      en: { common: enCommon }, // Bundled: default language, default namespace
    },
    partialBundledLanguages: true, // Allow mixing bundled + backend
    backend: {
      loadPath: '/locales/{{lng}}/{{ns}}.json',
    },
    fallbackLng: 'en',
    defaultNS: 'common',
    react: {
      useSuspense: false,
    },
  });
```
