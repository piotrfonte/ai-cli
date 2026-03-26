---
name: test-vitest
description: Vitest and React Testing Library patterns for unit and integration testing of React TypeScript components, hooks, and async flows.
user-invocable: true
---

# Vitest + React Testing Library Patterns

## Quick Start

```typescript
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect } from 'vitest';
import { Counter } from './Counter';

describe('Counter', () => {
  it('increments count when button is clicked', async () => {
    const user = userEvent.setup();
    render(<Counter initialCount={0} />);

    expect(screen.getByRole('heading')).toHaveTextContent('0');
    await user.click(screen.getByRole('button', { name: /increment/i }));
    expect(screen.getByRole('heading')).toHaveTextContent('1');
  });
});
```

## Version Constraints

- **vitest**: >=1.0
- **@testing-library/react**: >=14
- **@testing-library/user-event**: >=14
- **@testing-library/jest-dom**: >=6
- **Environment**: `jsdom` or `happy-dom` in vitest config

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
export default defineConfig({
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    restoreMocks: true,
  },
});
```

```typescript
// src/test/setup.ts
import '@testing-library/jest-dom/vitest';
```

## Query Priority

| Priority | Query | Use for |
|---|---|---|
| 1st | `getByRole` | Anything with an ARIA role (buttons, headings, textboxes, etc.) |
| 2nd | `getByLabelText` | Form fields with labels |
| 3rd | `getByPlaceholderText` | Inputs with placeholder (when no label) |
| 4th | `getByText` | Non-interactive content |
| 5th | `getByDisplayValue` | Filled-in form elements |
| Last resort | `getByTestId` | Only when no semantic query works |

- DO use `screen.getByRole('button', { name: /submit/i })` — accessible, resilient to markup changes
- DO use `*ByRole` with `name` option for specificity
- DO NOT use `container.querySelector` — bypasses accessibility, breaks on refactors
- DO NOT use `getByTestId` as a first choice — prefer semantic queries

## User Interaction Rules

- DO use `userEvent.setup()` — creates an instance with realistic event sequencing
- DO `await` all user-event calls — they are async in v14+
- DO NOT use `fireEvent` unless testing a specific DOM event that user-event doesn't support

```typescript
const user = userEvent.setup();
await user.click(button);
await user.type(input, 'hello');
await user.clear(input);
await user.selectOptions(select, 'option-value');
await user.keyboard('{Enter}');
await user.tab();
```

## Assertions

- DO use jest-dom matchers — they produce clear failure messages
- DO NOT manually check DOM attributes when a jest-dom matcher exists

```typescript
expect(element).toBeInTheDocument();
expect(element).toBeVisible();
expect(element).toBeDisabled();
expect(element).toHaveTextContent('hello');
expect(element).toHaveValue('input value');
expect(element).toHaveAttribute('href', '/path');
expect(element).toHaveClass('active');
expect(element).toBeChecked();
expect(element).toHaveAccessibleName('Submit form');
expect(element).toHaveAccessibleDescription('Click to submit');
```

## Mocking Rules

```typescript
// vi.fn — standalone mock function
const onClick = vi.fn();
render(<Button onClick={onClick} />);
await user.click(screen.getByRole('button'));
expect(onClick).toHaveBeenCalledOnce();

// vi.mock — module mock with factory
vi.mock('./api', () => ({
  fetchUsers: vi.fn(),
}));

// vi.mock — partial mock preserving real exports
vi.mock('./utils', async (importOriginal) => {
  const actual = await importOriginal<typeof import('./utils')>();
  return { ...actual, formatDate: vi.fn(() => '2024-01-01') };
});

// vi.spyOn — spy on object method
const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
// ... test ...
expect(spy).toHaveBeenCalledWith(expect.stringContaining('failed'));

// vi.hoisted — declare variables for use in vi.mock factory
const mockNavigate = vi.hoisted(() => vi.fn());
vi.mock('react-router-dom', async (importOriginal) => ({
  ...(await importOriginal<typeof import('react-router-dom')>()),
  useNavigate: () => mockNavigate,
}));
```

- DO set `restoreMocks: true` in vitest config — auto-restores spies/mocks after each test
- DO use `vi.hoisted()` when mock variables are referenced inside `vi.mock()` factories
- DO NOT forget that `vi.mock()` is hoisted — it runs before imports regardless of placement

## Test Structure

Use **AAA pattern**: Arrange → Act → Assert.

```typescript
describe('ComponentName', () => {
  it('renders default state', () => {
    render(<ComponentName />);
    expect(screen.getByRole('heading')).toHaveTextContent('Title');
  });

  it('calls onSubmit with form data when submitted', async () => {
    const user = userEvent.setup();
    const onSubmit = vi.fn();
    render(<Form onSubmit={onSubmit} />);

    await user.type(screen.getByLabelText(/name/i), 'Alice');
    await user.click(screen.getByRole('button', { name: /submit/i }));

    expect(onSubmit).toHaveBeenCalledWith({ name: 'Alice' });
  });
});
```

### Naming Conventions

- `describe` block: component or hook name
- `it` block: `"renders X when Y"`, `"calls handler when Z"`, `"disables button when form is invalid"`
- One assertion concept per test — multiple `expect` calls are fine if they verify the same behavior

## Anti-patterns

- DO NOT test implementation details — don't assert on state values, internal method calls, or component internals
- DO NOT use snapshot tests by default — they break on any markup change and rarely catch real bugs
- DO NOT test third-party library behavior — test your code's integration with the library, not the library itself
- DO NOT use `act()` directly when RTL utilities handle it — `render`, `userEvent`, `waitFor`, and `findBy` already wrap in `act()`
- DO NOT use `cleanup` manually — Vitest + RTL auto-cleans after each test
- DO NOT assert `toMatchSnapshot()` unless explicitly asked — prefer explicit assertions

## Render with Providers

```typescript
// src/test/test-utils.tsx
import { render, type RenderOptions } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from 'react-query';
import { MemoryRouter } from 'react-router-dom';
import { ThemeProvider } from './ThemeContext';

interface WrapperProps {
  children: React.ReactNode;
}

function createTestQueryClient() {
  return new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
}

export function renderWithProviders(
  ui: React.ReactElement,
  { route = '/', ...options }: RenderOptions & { route?: string } = {}
) {
  const queryClient = createTestQueryClient();

  function Wrapper({ children }: WrapperProps) {
    return (
      <QueryClientProvider client={queryClient}>
        <MemoryRouter initialEntries={[route]}>
          <ThemeProvider>{children}</ThemeProvider>
        </MemoryRouter>
      </QueryClientProvider>
    );
  }

  return { ...render(ui, { wrapper: Wrapper, ...options }), queryClient };
}
```

- DO create a fresh `QueryClient` per test — prevents cache leakage
- DO set `retry: false` in test QueryClient — avoids slow retries in tests
- DO use `MemoryRouter` with `initialEntries` for route-dependent components

## References

- `resources/component-testing-patterns.md` — testing components, hooks, forms, routing, error boundaries, modals
- `resources/mocking-patterns.md` — vi.fn, vi.mock, vi.spyOn, timers, browser APIs, TypeScript typing
- `resources/async-testing-patterns.md` — waitFor, findBy, act(), loading/error states, debounce, data fetching
