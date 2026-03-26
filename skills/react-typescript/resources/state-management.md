# State Management with TanStack Store

Patterns for state management using TanStack Store (the project's actual state library) and React Context.

## TanStack Store Basics

```typescript
import { Store, createStore } from '@tanstack/store'
import { useStore } from '@tanstack/react-store'
```

### Mutable Store (pass a value)

```typescript
const countStore = new Store(0)

// Update state
countStore.setState(prev => prev + 1)

// Read state outside React
countStore.state // 0 -> 1
```

### Readonly/Derived Store (pass a function)

```typescript
const doubleStore = createStore(() => countStore.state * 2)

// doubleStore.state auto-updates when countStore changes
```

### React Integration

```typescript
function Counter() {
  const count = useStore(countStore, state => state)
  const double = useStore(doubleStore, state => state)

  return (
    <div>
      <p>{count} x2 = {double}</p>
      <button onClick={() => countStore.setState(prev => prev + 1)}>
        Increment
      </button>
    </div>
  )
}
```

### Selectors with Custom Comparator

```typescript
import { shallow } from '@tanstack/react-store'

// Only re-render when name or email changes (shallow comparison)
const user = useStore(
  userStore,
  s => ({ name: s.name, email: s.email }),
  shallow
)
```

## Complex Store Example

```typescript
interface AppState {
  user: User | null
  notifications: Notification[]
  theme: 'light' | 'dark'
}

const appStore = new Store<AppState>({
  user: null,
  notifications: [],
  theme: 'light',
})

// Update specific fields
function setUser(user: User | null) {
  appStore.setState(prev => ({ ...prev, user }))
}

function addNotification(notification: Notification) {
  appStore.setState(prev => ({
    ...prev,
    notifications: [...prev.notifications, notification],
  }))
}

function toggleTheme() {
  appStore.setState(prev => ({
    ...prev,
    theme: prev.theme === 'light' ? 'dark' : 'light',
  }))
}
```

## Batching Updates

Use `batch()` to group multiple store updates into a single render:

```typescript
import { batch } from '@tanstack/store'

batch(() => {
  appStore.setState(prev => ({ ...prev, user: newUser }))
  appStore.setState(prev => ({ ...prev, theme: 'dark' }))
})
// Components only re-render once
```

## Store Subscriptions (Outside React)

```typescript
const unsubscribe = countStore.subscribe(() => {
  console.log('Count changed:', countStore.state)
})

// Clean up when done
unsubscribe()
```

## When to Use Context vs TanStack Store

| Use Case | Approach |
|----------|----------|
| Auth state, current user | Context (provider-scoped) |
| Theme provider | Context (provider-scoped) |
| Global app state (notifications, UI flags) | TanStack Store |
| Feature-specific state (chat messages, calendar events) | TanStack Store |
| State shared across unrelated component trees | TanStack Store |
| State that needs to be read outside React | TanStack Store |

### Context Pattern (for provider-scoped state)

```typescript
interface AuthContextValue {
  user: User | null
  login: (credentials: Credentials) => Promise<void>
  logout: () => void
  isAuthenticated: boolean
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null)

  const login = async (credentials: Credentials) => {
    const user = await authService.login(credentials)
    setUser(user)
  }

  const logout = () => {
    authService.logout()
    setUser(null)
  }

  return (
    <AuthContext.Provider
      value={{ user, login, logout, isAuthenticated: !!user }}
    >
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used within AuthProvider')
  return context
}
```
