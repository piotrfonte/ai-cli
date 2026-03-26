# Translation Patterns Reference

Comprehensive reference for i18next v21 translation patterns including interpolation, pluralization, context, nesting, and formatting.

## Interpolation

### Basic Interpolation

Insert dynamic values into translation strings using double curly braces.

```json
{
  "greeting": "Hello, {{name}}!",
  "welcome": "Welcome to {{appName}}, {{userName}}.",
  "notification": "You have {{count}} new messages from {{sender}}."
}
```

```typescript
t('greeting', { name: 'Alice' });
// "Hello, Alice!"

t('welcome', { appName: 'Securitas', userName: 'Bob' });
// "Welcome to Securitas, Bob."

t('notification', { count: 3, sender: 'Charlie' });
// "You have 3 new messages from Charlie."
```

### Unescaped Interpolation

By default, interpolation values are escaped for XSS safety. Use `{{- variable}}` to skip escaping. Since React handles escaping via JSX, i18next is typically configured with `escapeValue: false`.

```json
{
  "richContent": "{{- htmlContent}}"
}
```

```typescript
t('richContent', { htmlContent: '<strong>Bold</strong>' });
// "<strong>Bold</strong>" (rendered as HTML if used with dangerouslySetInnerHTML)
```

### Default Values for Missing Variables

Provide fallbacks for interpolation variables:

```typescript
t('greeting', { name: undefined, defaultValue: 'Hello, {{name}}!' });
// "Hello, !"

// Better: set a default in the translation or use fallback
```

### Interpolation with Formatting

Combine interpolation with inline format options.

```json
{
  "price": "Total: {{amount, number(style: currency; currency: USD)}}",
  "date": "Due by {{deadline, datetime(dateStyle: medium)}}",
  "percent": "{{val, number(style: percent)}}"
}
```

```typescript
t('price', { amount: 99.99 });
// "Total: $99.99"

t('date', { deadline: new Date('2024-06-15') });
// "Due by Jun 15, 2024"

t('percent', { val: 0.85 });
// "85%"
```

### Nested Object Interpolation

Access nested object properties in translations:

```json
{
  "userInfo": "{{user.name}} ({{user.email}})"
}
```

```typescript
t('userInfo', { user: { name: 'Alice', email: 'alice@example.com' } });
// "Alice (alice@example.com)"
```

## Pluralization

### English (Two Forms)

English requires only `_one` and `_other` suffixes.

```json
{
  "file_one": "{{count}} file",
  "file_other": "{{count}} files",
  "result_one": "Found {{count}} result",
  "result_other": "Found {{count}} results",
  "day_one": "{{count}} day remaining",
  "day_other": "{{count}} days remaining"
}
```

```typescript
t('file', { count: 0 });   // "0 files"
t('file', { count: 1 });   // "1 file"
t('file', { count: 2 });   // "2 files"
t('file', { count: 100 }); // "100 files"
```

### Zero Form (Optional Override)

The `_zero` suffix provides a special case for count 0.

```json
{
  "notification_zero": "No new notifications",
  "notification_one": "{{count}} new notification",
  "notification_other": "{{count}} new notifications"
}
```

```typescript
t('notification', { count: 0 });  // "No new notifications"
t('notification', { count: 1 });  // "1 new notification"
t('notification', { count: 7 });  // "7 new notifications"
```

### Complex Plural Languages

Languages like Arabic have six plural forms. The `Intl.PluralRules` API determines which form to use.

**Arabic (ar):**

```json
{
  "book_zero": "\u0644\u0627 \u0643\u062a\u0628",
  "book_one": "\u0643\u062a\u0627\u0628 \u0648\u0627\u062d\u062f",
  "book_two": "\u0643\u062a\u0627\u0628\u0627\u0646",
  "book_few": "{{count}} \u0643\u062a\u0628",
  "book_many": "{{count}} \u0643\u062a\u0627\u0628\u064b\u0627",
  "book_other": "{{count}} \u0643\u062a\u0627\u0628"
}
```

**Polish (pl):**

```json
{
  "item_one": "{{count}} element",
  "item_few": "{{count}} elementy",
  "item_many": "{{count}} element\u00f3w",
  "item_other": "{{count}} elementu"
}
```

**Russian (ru):**

```json
{
  "comment_one": "{{count}} \u043a\u043e\u043c\u043c\u0435\u043d\u0442\u0430\u0440\u0438\u0439",
  "comment_few": "{{count}} \u043a\u043e\u043c\u043c\u0435\u043d\u0442\u0430\u0440\u0438\u044f",
  "comment_many": "{{count}} \u043a\u043e\u043c\u043c\u0435\u043d\u0442\u0430\u0440\u0438\u0435\u0432",
  "comment_other": "{{count}} \u043a\u043e\u043c\u043c\u0435\u043d\u0442\u0430\u0440\u0438\u044f"
}
```

### Ordinal Plurals

Ordinal plurals use the `_ordinal_` infix.

```json
{
  "rank_ordinal_one": "{{count}}st",
  "rank_ordinal_two": "{{count}}nd",
  "rank_ordinal_few": "{{count}}rd",
  "rank_ordinal_other": "{{count}}th"
}
```

```typescript
t('rank', { count: 1, ordinal: true });   // "1st"
t('rank', { count: 2, ordinal: true });   // "2nd"
t('rank', { count: 3, ordinal: true });   // "3rd"
t('rank', { count: 4, ordinal: true });   // "4th"
t('rank', { count: 11, ordinal: true });  // "11th"
t('rank', { count: 21, ordinal: true });  // "21st"
t('rank', { count: 22, ordinal: true });  // "22nd"
t('rank', { count: 23, ordinal: true });  // "23rd"
t('rank', { count: 111, ordinal: true }); // "111th"
```

## Context Suffixes

Context suffixes allow different translations based on a contextual parameter, such as gender.

### Gender Context

```json
{
  "greeting": "They left a comment.",
  "greeting_male": "He left a comment.",
  "greeting_female": "She left a comment.",
  "profileUpdate": "They updated their profile.",
  "profileUpdate_male": "He updated his profile.",
  "profileUpdate_female": "She updated her profile."
}
```

```typescript
t('greeting');                               // "They left a comment."
t('greeting', { context: 'male' });          // "He left a comment."
t('greeting', { context: 'female' });        // "She left a comment."
```

### Context + Plural

Context and plural suffixes can be combined. The order is: `key_context_plural`.

```json
{
  "friend_male_one": "He has {{count}} friend",
  "friend_male_other": "He has {{count}} friends",
  "friend_female_one": "She has {{count}} friend",
  "friend_female_other": "She has {{count}} friends"
}
```

```typescript
t('friend', { context: 'male', count: 1 });    // "He has 1 friend"
t('friend', { context: 'female', count: 5 });   // "She has 5 friends"
```

### Custom Context (Status, Role, etc.)

Context is not limited to gender. Use it for any variation.

```json
{
  "badge_admin": "Administrator",
  "badge_editor": "Editor",
  "badge_viewer": "Viewer",
  "accessLevel_free": "Free Plan",
  "accessLevel_pro": "Pro Plan",
  "accessLevel_enterprise": "Enterprise Plan"
}
```

```typescript
t('badge', { context: user.role });
t('accessLevel', { context: subscription.tier });
```

## Nesting Translations

Reference other translation keys within a value using `$t(key)`.

```json
{
  "appName": "Securitas",
  "welcomeTitle": "Welcome to $t(appName)",
  "footerText": "2024 $t(appName). All rights reserved.",
  "error": {
    "generic": "Something went wrong. Please $t(error.tryAgain).",
    "tryAgain": "try again"
  }
}
```

```typescript
t('welcomeTitle');
// "Welcome to Securitas"

t('footerText');
// "2024 Securitas. All rights reserved."

t('error.generic');
// "Something went wrong. Please try again."
```

### Nesting with Interpolation

```json
{
  "animal": "{{animal, lowercase}}",
  "sentence": "The $t(animal, {\"animal\": \"{{creature}}\"}) jumped over the fence."
}
```

## Default Values and Fallbacks

### Default Value for Missing Keys

```typescript
// Simple default
t('maybe.missing.key', 'Fallback text');

// Default with interpolation
t('maybe.missing', { defaultValue: 'Hello {{name}}', name: 'World' });
```

### Fallback Keys

Try multiple keys in order:

```typescript
// Array of keys - uses first one found
t(['specific.error.404', 'generic.error', 'error.unknown']);
```

### Fallback Namespace

```typescript
i18n.init({
  fallbackNS: 'common', // Fall back to common namespace if key not found
});
```

### Fallback Language Chain

```typescript
i18n.init({
  fallbackLng: {
    'de-CH': ['de', 'en'],      // Swiss German -> German -> English
    'zh-Hant': ['zh-Hans', 'en'], // Traditional Chinese -> Simplified -> English
    default: ['en'],
  },
});
```

## Key Naming Conventions

### Dot Notation Structure

Organize keys by feature, page, or component using dot notation.

```json
{
  "page": {
    "dashboard": {
      "title": "Dashboard",
      "subtitle": "Welcome back, {{name}}"
    },
    "settings": {
      "title": "Settings",
      "sections": {
        "profile": "Profile",
        "security": "Security",
        "notifications": "Notifications"
      }
    }
  },
  "common": {
    "buttons": {
      "save": "Save",
      "cancel": "Cancel",
      "delete": "Delete",
      "confirm": "Confirm"
    },
    "labels": {
      "email": "Email",
      "password": "Password",
      "name": "Name"
    },
    "errors": {
      "required": "{{field}} is required",
      "invalid": "{{field}} is invalid",
      "networkError": "Network error. Please try again."
    }
  }
}
```

### Recommended Naming Patterns

| Pattern | Example | Use For |
|---|---|---|
| `page.section.element` | `dashboard.stats.title` | Page-specific content |
| `common.category.item` | `common.buttons.save` | Shared UI elements |
| `feature.action.state` | `auth.login.success` | Feature-specific messages |
| `error.type.detail` | `error.validation.email` | Error messages |
| `noun_pluralSuffix` | `item_one`, `item_other` | Countable items |

## Arrays and Objects in Translations

### Array Values

```json
{
  "features": [
    "Real-time sync",
    "End-to-end encryption",
    "Cross-platform support"
  ]
}
```

```typescript
// Access by index
t('features.0'); // "Real-time sync"
t('features.1'); // "End-to-end encryption"

// Get entire array
const features = t('features', { returnObjects: true }) as string[];
features.map((feature) => <li key={feature}>{feature}</li>);
```

### Object Values

```json
{
  "address": {
    "street": "123 Main St",
    "city": "Springfield",
    "state": "IL"
  }
}
```

```typescript
const address = t('address', { returnObjects: true }) as {
  street: string;
  city: string;
  state: string;
};
```

## Formatting Numbers, Dates, and Currencies

### Number Formatting

```json
{
  "fileSize": "File size: {{size, number}} bytes",
  "largeNumber": "Population: {{pop, number(useGrouping: true)}}",
  "decimal": "Score: {{score, number(minimumFractionDigits: 2; maximumFractionDigits: 2)}}"
}
```

```typescript
t('fileSize', { size: 1024 });
// "File size: 1,024 bytes" (in en locale)

t('largeNumber', { pop: 8900000 });
// "Population: 8,900,000"

t('decimal', { score: 4.5 });
// "Score: 4.50"
```

### Currency Formatting

```json
{
  "price": "{{val, number(style: currency; currency: USD)}}",
  "priceEur": "{{val, number(style: currency; currency: EUR)}}"
}
```

```typescript
t('price', { val: 29.99 });
// "$29.99" (in en locale)
// "29,99\u00a0$" (in fr locale)
```

Using `formatParams` for dynamic currency:

```typescript
t('price', {
  val: 29.99,
  formatParams: {
    val: { style: 'currency', currency: userCurrency },
  },
});
```

### Date Formatting

```json
{
  "today": "Today is {{date, datetime}}",
  "shortDate": "{{date, datetime(dateStyle: short)}}",
  "longDate": "{{date, datetime(dateStyle: long)}}",
  "fullDateTime": "{{date, datetime(dateStyle: full; timeStyle: short)}}",
  "timeOnly": "{{date, datetime(timeStyle: medium)}}"
}
```

```typescript
const now = new Date('2024-03-15T14:30:00');

t('today', { date: now });
// "Today is 3/15/2024, 2:30:00 PM"

t('shortDate', { date: now });
// "3/15/24"

t('longDate', { date: now });
// "March 15, 2024"

t('fullDateTime', { date: now });
// "Friday, March 15, 2024 at 2:30 PM"

t('timeOnly', { date: now });
// "2:30:00 PM"
```

### Relative Time

```json
{
  "relDays": "{{val, relativetime(range: day)}}",
  "relHours": "{{val, relativetime(range: hour)}}",
  "relMinutes": "{{val, relativetime(range: minute)}}"
}
```

```typescript
t('relDays', { val: -1 });    // "1 day ago"
t('relDays', { val: 3 });     // "in 3 days"
t('relHours', { val: -2 });   // "2 hours ago"
t('relMinutes', { val: 5 });  // "in 5 minutes"
```

### List Formatting

```json
{
  "attendees": "Attendees: {{val, list}}"
}
```

```typescript
t('attendees', { val: ['Alice', 'Bob', 'Charlie'] });
// "Attendees: Alice, Bob, and Charlie" (en)
// "Attendees: Alice, Bob und Charlie" (de)
```

### Custom Format Functions

Register custom formatters during init:

```typescript
i18n.init({
  interpolation: {
    escapeValue: false,
    format: (value: unknown, format?: string, lng?: string) => {
      if (format === 'uppercase') return String(value).toUpperCase();
      if (format === 'lowercase') return String(value).toLowerCase();
      if (format === 'capitalize') {
        const str = String(value);
        return str.charAt(0).toUpperCase() + str.slice(1);
      }
      if (format === 'filesize') {
        const num = Number(value);
        if (num >= 1_073_741_824) return `${(num / 1_073_741_824).toFixed(1)} GB`;
        if (num >= 1_048_576) return `${(num / 1_048_576).toFixed(1)} MB`;
        if (num >= 1024) return `${(num / 1024).toFixed(1)} KB`;
        return `${num} B`;
      }
      return String(value);
    },
  },
});
```

```json
{
  "status": "Status: {{val, uppercase}}",
  "fileName": "{{val, capitalize}}",
  "size": "Size: {{val, filesize}}"
}
```

```typescript
t('status', { val: 'active' });       // "Status: ACTIVE"
t('fileName', { val: 'document' });   // "Document"
t('size', { val: 5242880 });          // "Size: 5.0 MB"
```

---

## Displaced Patterns from SKILL.md

### Full i18next.init() Configuration

```typescript
import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';
import LanguageDetector from 'i18next-browser-languagedetector';
import enCommon from '../locales/en/common.json';
import deCommon from '../locales/de/common.json';

i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources: {
      en: { common: enCommon },
      de: { common: deCommon },
    },
    defaultNS: 'common',
    fallbackLng: 'en',
    interpolation: { escapeValue: false },
    detection: {
      order: ['localStorage', 'navigator', 'htmlTag'],
      caches: ['localStorage'],
      lookupLocalStorage: 'i18nextLng',
    },
    react: { useSuspense: false },
  });

export default i18n;
```

### Language Detection Sources

| Source | Description |
|---|---|
| `localStorage` | `localStorage.getItem('i18nextLng')` |
| `navigator` | `navigator.language` |
| `htmlTag` | `<html lang="en">` |
| `path` | URL path segment `/en/about` |
| `subdomain` | `en.example.com` |
| `querystring` | `?lng=en` |
| `cookie` | `i18next=en` |

### Language Selector Dropdown

```typescript
const LANGUAGES = [
  { code: 'en', label: 'English' },
  { code: 'de', label: 'Deutsch' },
] as const;

function LanguageSelector() {
  const { i18n } = useTranslation();
  return (
    <select value={i18n.language} onChange={(e) => i18n.changeLanguage(e.target.value)}>
      {LANGUAGES.map(({ code, label }) => <option key={code} value={code}>{label}</option>)}
    </select>
  );
}
```

### Formatting Examples

```json
{ "price": "{{val, number(style: currency; currency: USD)}}", "lastLogin": "Last login: {{date, datetime}}" }
```

```typescript
t('price', { val: 42.5 });                // "$42.50"
t('lastLogin', { date: new Date() });      // "Last login: 3/15/2024, 2:30:00 PM"
t('balance', { amount: 1234, formatParams: { amount: { style: 'currency', currency: 'EUR' } } });
```

### Custom Formatters

```typescript
i18n.init({
  interpolation: {
    format: (value, format) => {
      if (format === 'uppercase') return value.toUpperCase();
      if (format === 'lowercase') return value.toLowerCase();
      return value;
    },
  },
});
```

### Watching Language Changes

```typescript
function DocumentTitle() {
  const { t, i18n } = useTranslation();
  useEffect(() => { document.title = t('app.title'); }, [t, i18n.language]);
  return null;
}
```

### Extracting t Outside Components

```typescript
import i18n from '../i18n/i18n';
export function getValidationMessage(field: string): string {
  return i18n.t('validation.required', { field });
}
const tGerman = i18n.getFixedT('de');
```

### Fallback Chain

```typescript
i18n.init({
  fallbackLng: { 'de-CH': ['de', 'en'], 'pt-BR': ['pt', 'en'], default: ['en'] },
});
```

### Complex Plurals (Arabic)

```json
{ "item_zero": "...", "item_one": "...", "item_two": "...", "item_few": "...", "item_many": "...", "item_other": "..." }
```

### Ordinal Plurals

```json
{ "place_ordinal_one": "{{count}}st", "place_ordinal_two": "{{count}}nd", "place_ordinal_few": "{{count}}rd", "place_ordinal_other": "{{count}}th" }
```

```typescript
t('place', { count: 1, ordinal: true }); // "1st"
```
