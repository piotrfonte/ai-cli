# Mocking Patterns

## vi.fn() — Creating Mock Functions

```typescript
// Basic mock
const handler = vi.fn();
handler('arg1', 'arg2');
expect(handler).toHaveBeenCalledWith('arg1', 'arg2');
expect(handler).toHaveBeenCalledTimes(1);

// Return values
const getId = vi.fn().mockReturnValue('abc-123');
const getIdOnce = vi.fn().mockReturnValueOnce('first').mockReturnValueOnce('second');

// Async return values
const fetchData = vi.fn().mockResolvedValue({ id: 1, name: 'Alice' });
const fetchWithError = vi.fn().mockRejectedValue(new Error('Network error'));

// Custom implementation
const transform = vi.fn().mockImplementation((x: number) => x * 2);
```

### Assertion Helpers

```typescript
expect(fn).toHaveBeenCalled();
expect(fn).toHaveBeenCalledOnce();
expect(fn).toHaveBeenCalledTimes(3);
expect(fn).toHaveBeenCalledWith('arg1', expect.any(Number));
expect(fn).toHaveBeenLastCalledWith('final');
expect(fn).toHaveBeenNthCalledWith(2, 'second-call-arg');
expect(fn).toHaveReturnedWith('value');
```

### Inspecting Calls

```typescript
const mock = vi.fn();
mock('a');
mock('b', 'c');

mock.mock.calls;       // [['a'], ['b', 'c']]
mock.mock.results;     // [{ type: 'return', value: undefined }, ...]
mock.mock.lastCall;    // ['b', 'c']
```

## vi.mock() — Module Mocking

### Full Module Mock with Factory

```typescript
vi.mock('./api', () => ({
  fetchUsers: vi.fn().mockResolvedValue([{ id: 1, name: 'Alice' }]),
  createUser: vi.fn().mockResolvedValue({ id: 2, name: 'Bob' }),
}));

import { fetchUsers, createUser } from './api';
// fetchUsers and createUser are now vi.fn() mocks
```

### Partial Mock — Preserve Real Exports

```typescript
vi.mock('./utils', async (importOriginal) => {
  const actual = await importOriginal<typeof import('./utils')>();
  return {
    ...actual,
    formatDate: vi.fn(() => '2024-01-01'),
    // All other exports remain real
  };
});
```

### Auto-mock — All Exports Become vi.fn()

```typescript
vi.mock('./service'); // No factory = auto-mock
import { fetchData } from './service';
// fetchData is vi.fn() returning undefined
vi.mocked(fetchData).mockResolvedValue({ data: 'test' });
```

### Default Export Mocking

```typescript
vi.mock('./Logger', () => ({
  default: vi.fn().mockImplementation(() => ({
    log: vi.fn(),
    error: vi.fn(),
  })),
}));
```

### Resetting Module Mocks Between Tests

```typescript
import { fetchUsers } from './api';

beforeEach(() => {
  vi.mocked(fetchUsers).mockResolvedValue([]);
});

it('handles empty state', async () => {
  // Uses default empty mock from beforeEach
});

it('renders users', async () => {
  vi.mocked(fetchUsers).mockResolvedValue([{ id: 1, name: 'Alice' }]);
  // Uses overridden mock
});
```

## vi.hoisted() — Variables in Mock Factories

`vi.mock()` is hoisted above imports. Use `vi.hoisted()` for variables referenced in factories:

```typescript
const { mockPush } = vi.hoisted(() => ({
  mockPush: vi.fn(),
}));

vi.mock('next/router', () => ({
  useRouter: () => ({ push: mockPush, pathname: '/' }),
}));

// In test:
expect(mockPush).toHaveBeenCalledWith('/dashboard');
```

## vi.spyOn() — Spying on Methods

```typescript
// Spy on object method
const spy = vi.spyOn(Math, 'random').mockReturnValue(0.5);
expect(generateId()).toBe('id-0.5');
spy.mockRestore(); // Restore original implementation

// Spy on prototype
const spy = vi.spyOn(Storage.prototype, 'getItem').mockReturnValue('cached');
expect(localStorage.getItem('key')).toBe('cached');

// Spy without replacing implementation
const consoleSpy = vi.spyOn(console, 'warn');
doSomethingWarnable();
expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('deprecated'));
```

## TypeScript Mock Typing — vi.mocked()

```typescript
import { fetchUsers } from './api';

vi.mock('./api');

// Type-safe access to mock methods
vi.mocked(fetchUsers).mockResolvedValue([{ id: 1, name: 'Alice' }]);

// Deep mocking (nested properties)
vi.mocked(complexModule, true);
```

## Timer Mocks

### Basic Timer Control

```typescript
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

describe('Debounced Search', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('debounces search input', async () => {
    const onSearch = vi.fn();
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
    render(<SearchInput onSearch={onSearch} debounceMs={300} />);

    await user.type(screen.getByRole('searchbox'), 'hello');

    expect(onSearch).not.toHaveBeenCalled();
    vi.advanceTimersByTime(300);
    expect(onSearch).toHaveBeenCalledWith('hello');
  });
});
```

- DO pass `advanceTimers: vi.advanceTimersByTime` to `userEvent.setup()` when using fake timers — user-event uses `setTimeout` internally

### Timer Utilities

```typescript
vi.useFakeTimers();           // Replace setTimeout, setInterval, Date, etc.
vi.advanceTimersByTime(1000); // Advance by 1 second
vi.advanceTimersToNextTimer(); // Advance to next pending timer
vi.runAllTimers();            // Execute all pending timers
vi.runOnlyPendingTimers();    // Execute only currently pending (avoids infinite recursion)
vi.getTimerCount();           // Number of pending timers
vi.useRealTimers();           // Restore real timers

// Fake Date
vi.setSystemTime(new Date('2024-06-15'));
expect(new Date().toISOString()).toContain('2024-06-15');
```

## Mocking Browser APIs

### IntersectionObserver

```typescript
const mockIntersectionObserver = vi.fn().mockImplementation((callback) => ({
  observe: vi.fn(),
  unobserve: vi.fn(),
  disconnect: vi.fn(),
  // Trigger intersection: callback([{ isIntersecting: true, target: element }]);
}));

vi.stubGlobal('IntersectionObserver', mockIntersectionObserver);
```

### matchMedia

```typescript
vi.stubGlobal('matchMedia', vi.fn().mockImplementation((query: string) => ({
  matches: query === '(prefers-color-scheme: dark)',
  media: query,
  onchange: null,
  addListener: vi.fn(),
  removeListener: vi.fn(),
  addEventListener: vi.fn(),
  removeEventListener: vi.fn(),
  dispatchEvent: vi.fn(),
})));
```

### localStorage

```typescript
const store: Record<string, string> = {};
vi.stubGlobal('localStorage', {
  getItem: vi.fn((key: string) => store[key] ?? null),
  setItem: vi.fn((key: string, value: string) => { store[key] = value; }),
  removeItem: vi.fn((key: string) => { delete store[key]; }),
  clear: vi.fn(() => { Object.keys(store).forEach(k => delete store[k]); }),
});
```

### fetch

```typescript
// Simple mock
globalThis.fetch = vi.fn().mockResolvedValue({
  ok: true,
  json: () => Promise.resolve({ data: 'test' }),
});

// Per-test override
vi.mocked(fetch).mockResolvedValueOnce({
  ok: false,
  status: 404,
  json: () => Promise.resolve({ error: 'Not found' }),
} as Response);
```

## Mock Cleanup Strategies

### Config-based (recommended)

```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    restoreMocks: true, // Restores all mocks after each test
    // Also available:
    // clearMocks: true,   // Clears mock history (calls, results)
    // mockReset: true,    // Clears + removes implementations
  },
});
```

### Manual Cleanup

```typescript
afterEach(() => {
  vi.restoreAllMocks(); // Restores spies to originals + clears mocks
});

// Or per-mock:
const spy = vi.spyOn(obj, 'method');
spy.mockClear();   // Clear calls/results
spy.mockReset();   // Clear + remove implementation
spy.mockRestore(); // Reset + restore original
```

- DO prefer `restoreMocks: true` in config — it's automatic and prevents leaks
- DO NOT mix `restoreMocks` config with manual `vi.restoreAllMocks()` — choose one approach
