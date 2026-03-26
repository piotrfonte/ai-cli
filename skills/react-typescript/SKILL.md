---
name: react-typescript
description: React 18 and TypeScript patterns for components, hooks, TanStack Store state management, and code quality standards.
user-invocable: true
---

# React + TypeScript Patterns

## Quick Start — TanStack Store

```tsx
import { Store } from '@tanstack/store'
import { useStore } from '@tanstack/react-store'

const countStore = new Store(0)

function Counter() {
  const count = useStore(countStore, state => state)
  return (
    <button onClick={() => countStore.setState(prev => prev + 1)}>
      Count: {count}
    </button>
  )
}
```

## Component Rules

- DO type props with `interface`, not `type` alias for object shapes
- DO use `React.ReactNode` for children props
- DO use optional chaining for optional callbacks: `onSelect?.(value)`
- DO NOT use `React.FC` — use plain function with typed props
- DO NOT use `any` — use `unknown` and narrow, or proper generics

```tsx
interface UserCardProps {
  user: User
  onSelect?: (user: User) => void
  children?: React.ReactNode
}

export function UserCard({ user, onSelect, children }: UserCardProps) {
  return <div onClick={() => onSelect?.(user)}>{children}</div>
}
```

## Hooks Rules

- DO prefix custom hooks with `use`
- DO wrap expensive callbacks in `useCallback` with correct deps
- DO memoize expensive computations with `useMemo`
- DO NOT call hooks conditionally or inside loops

```tsx
export function useCounter(initial = 0) {
  const [count, setCount] = useState(initial)
  const increment = useCallback(() => setCount(c => c + 1), [])
  return { count, increment }
}
```

## State Management

- Use **TanStack Store** for global app state
- Use **React Context** for provider-scoped state (auth, theme)
- DO use selectors with `useStore(store, selector)` to avoid unnecessary re-renders

> See `resources/state-management.md` for derived stores, batching, selectors with custom comparators, and Context vs Store guidance.

## Form Handling

- Use controlled forms with MUI components (TextField, Button, Stack)
- Validate before submit; show errors with `Alert`
- Handle async submission with loading/error state

## Performance

- DO `useMemo` for expensive sorts/filters
- DO `useCallback` for callbacks passed to child components
- DO `memo()` for components receiving stable props
- DO `lazy()` + `Suspense` for code splitting
- DO NOT memoize everything — only when profiling shows a need

## Error Handling

- Wrap route-level components in `ErrorBoundary`
- Use class-based `ErrorBoundary` with `getDerivedStateFromError` + `componentDidCatch`

> See `resources/coding-standards.md` for full ErrorBoundary class, compound components, and generic list patterns.

## TypeScript Conventions

- **Variables:** `camelCase`, descriptive (`isUserAuthenticated`, not `flag`)
- **Functions:** verb-noun (`fetchMarketData`, `calculateSimilarity`)
- **Components:** `PascalCase` (`UserCard`, `SideNavigation`)
- **Hooks:** `camelCase` with `use` prefix (`useAuth`, `useCounter`)
- **Files:** `PascalCase.tsx` for components, `camelCase.ts` for utils, `use*.ts` for hooks
- **Types/Interfaces:** `PascalCase`, prefer `interface` for object shapes
- **Event handlers:** `React.MouseEventHandler<HTMLButtonElement>`

## File Structure

```
src/
├── components/     # common/, features/, layout/
├── hooks/          # Custom hooks
├── store/          # TanStack Store definitions
├── routes/         # TanStack Router route components
├── services/       # API services
├── types/          # TypeScript types
├── utils/          # Utilities
└── main.tsx
```

## Security

- DO use JSX interpolation `{value}` — NOT `dangerouslySetInnerHTML`
- DO sanitize with DOMPurify when rendering user HTML
- DO NOT prefix secrets with `VITE_` — only public config

> See `resources/security-and-validation.md` for XSS prevention and Zod validation patterns.

## References

- `resources/coding-standards.md` — naming, immutability, error handling, testing
- `resources/state-management.md` — TanStack Store patterns, Context guidance
- `resources/security-and-validation.md` — XSS prevention, Zod validation
