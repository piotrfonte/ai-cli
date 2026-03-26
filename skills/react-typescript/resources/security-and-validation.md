# Security & Validation

## XSS Prevention

```typescript
// Dangerous — never use with user input
<div dangerouslySetInnerHTML={{ __html: userInput }} />

// Sanitize first if HTML rendering is required
import DOMPurify from 'dompurify'

<div dangerouslySetInnerHTML={{
  __html: DOMPurify.sanitize(userInput)
}} />

// Best — avoid dangerouslySetInnerHTML entirely
<div>{userInput}</div>
```

React's JSX interpolation (`{value}`) escapes strings by default. Only use `dangerouslySetInnerHTML` when rendering trusted HTML content, and always sanitize with DOMPurify.

## Environment Variables

Vite exposes only variables prefixed with `VITE_` to client-side code.

```typescript
// Public (exposed to client) — safe for non-secret config
const apiUrl = import.meta.env.VITE_API_URL

// NEVER prefix secrets with VITE_ — they will be bundled into client code
// Keep secrets server-side only (e.g., in .env without VITE_ prefix)
```

**Rules:**
- `VITE_*` variables are embedded in the build output — treat them as public
- API keys, tokens, and secrets must never have the `VITE_` prefix
- Use `.env.local` for local overrides (gitignored by default)

## Input Validation with Zod

Validate at system boundaries (user input, API responses).

```typescript
import { z } from 'zod'

const CreateMarketSchema = z.object({
  name: z.string().min(1).max(200),
  description: z.string().min(1).max(2000),
  endDate: z.string().datetime(),
  categories: z.array(z.string()).min(1),
})

type CreateMarketInput = z.infer<typeof CreateMarketSchema>

function createMarket(input: unknown) {
  const validated = CreateMarketSchema.parse(input)
  // Proceed with validated, typed data
}
```

### Zod Patterns

```typescript
// Optional fields with defaults
const ConfigSchema = z.object({
  limit: z.number().min(1).max(100).default(10),
  sortBy: z.enum(['name', 'date', 'relevance']).default('relevance'),
})

// Transform on parse
const UserInputSchema = z.object({
  email: z.string().email().transform(s => s.toLowerCase().trim()),
})

// Discriminated unions
const EventSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('click'), x: z.number(), y: z.number() }),
  z.object({ type: z.literal('keypress'), key: z.string() }),
])
```
