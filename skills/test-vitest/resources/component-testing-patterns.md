# Component Testing Patterns

## Testing Basic Rendering & Props

```typescript
import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { Greeting } from './Greeting';

describe('Greeting', () => {
  it('renders the name prop', () => {
    render(<Greeting name="Alice" />);
    expect(screen.getByRole('heading')).toHaveTextContent('Hello, Alice');
  });

  it('renders default greeting when no name provided', () => {
    render(<Greeting />);
    expect(screen.getByRole('heading')).toHaveTextContent('Hello, stranger');
  });

  it('applies className prop', () => {
    render(<Greeting name="Alice" className="highlight" />);
    expect(screen.getByRole('heading')).toHaveClass('highlight');
  });
});
```

## Testing Conditional Rendering

```typescript
describe('Alert', () => {
  it('renders message when visible', () => {
    render(<Alert visible message="Warning!" />);
    expect(screen.getByRole('alert')).toHaveTextContent('Warning!');
  });

  it('does not render when not visible', () => {
    render(<Alert visible={false} message="Warning!" />);
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });

  it('renders close button only when dismissible', () => {
    render(<Alert visible message="Info" dismissible />);
    expect(screen.getByRole('button', { name: /close/i })).toBeInTheDocument();
  });
});
```

- DO use `queryBy*` when asserting an element does NOT exist — `getBy*` throws if not found

## Testing Lists and Iteration

```typescript
describe('UserList', () => {
  it('renders all users', () => {
    const users = [
      { id: '1', name: 'Alice' },
      { id: '2', name: 'Bob' },
    ];
    render(<UserList users={users} />);
    expect(screen.getAllByRole('listitem')).toHaveLength(2);
    expect(screen.getByText('Alice')).toBeInTheDocument();
    expect(screen.getByText('Bob')).toBeInTheDocument();
  });

  it('renders empty state when no users', () => {
    render(<UserList users={[]} />);
    expect(screen.getByText(/no users found/i)).toBeInTheDocument();
    expect(screen.queryByRole('listitem')).not.toBeInTheDocument();
  });
});
```

## Testing Forms

### Controlled Inputs

```typescript
describe('LoginForm', () => {
  it('submits with entered credentials', async () => {
    const user = userEvent.setup();
    const onSubmit = vi.fn();
    render(<LoginForm onSubmit={onSubmit} />);

    await user.type(screen.getByLabelText(/email/i), 'alice@example.com');
    await user.type(screen.getByLabelText(/password/i), 'secret123');
    await user.click(screen.getByRole('button', { name: /log in/i }));

    expect(onSubmit).toHaveBeenCalledWith({
      email: 'alice@example.com',
      password: 'secret123',
    });
  });

  it('disables submit button when fields are empty', () => {
    render(<LoginForm onSubmit={vi.fn()} />);
    expect(screen.getByRole('button', { name: /log in/i })).toBeDisabled();
  });
});
```

### Validation Messages

```typescript
it('shows validation error for invalid email', async () => {
  const user = userEvent.setup();
  render(<LoginForm onSubmit={vi.fn()} />);

  await user.type(screen.getByLabelText(/email/i), 'not-an-email');
  await user.tab(); // triggers blur validation

  expect(screen.getByRole('alert')).toHaveTextContent(/invalid email/i);
});
```

### Select and Checkbox

```typescript
it('submits selected options', async () => {
  const user = userEvent.setup();
  const onSubmit = vi.fn();
  render(<PreferencesForm onSubmit={onSubmit} />);

  await user.selectOptions(screen.getByLabelText(/language/i), 'es');
  await user.click(screen.getByLabelText(/receive updates/i));
  await user.click(screen.getByRole('button', { name: /save/i }));

  expect(onSubmit).toHaveBeenCalledWith(
    expect.objectContaining({ language: 'es', updates: true })
  );
});
```

## Testing Custom Hooks

```typescript
import { renderHook, act } from '@testing-library/react';
import { useCounter } from './useCounter';

describe('useCounter', () => {
  it('initializes with default value', () => {
    const { result } = renderHook(() => useCounter());
    expect(result.current.count).toBe(0);
  });

  it('initializes with provided value', () => {
    const { result } = renderHook(() => useCounter(10));
    expect(result.current.count).toBe(10);
  });

  it('increments the count', () => {
    const { result } = renderHook(() => useCounter());
    act(() => result.current.increment());
    expect(result.current.count).toBe(1);
  });

  it('resets to initial value', () => {
    const { result } = renderHook(() => useCounter(5));
    act(() => result.current.increment());
    act(() => result.current.reset());
    expect(result.current.count).toBe(5);
  });
});
```

- DO use `act()` for synchronous state updates in `renderHook`
- DO use `waitFor` for async hook updates instead of `act()`

### Hooks with Providers

```typescript
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from 'react-query';
import { useUsers } from './useUsers';

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return function Wrapper({ children }: { children: React.ReactNode }) {
    return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>;
  };
}

describe('useUsers', () => {
  it('fetches users', async () => {
    const { result } = renderHook(() => useUsers(), { wrapper: createWrapper() });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data).toHaveLength(3);
  });
});
```

## Testing Components with Context

```typescript
import { ThemeContext } from './ThemeContext';

describe('ThemedButton', () => {
  it('uses theme from context', () => {
    render(
      <ThemeContext.Provider value={{ color: 'blue' }}>
        <ThemedButton>Click</ThemedButton>
      </ThemeContext.Provider>
    );
    expect(screen.getByRole('button')).toHaveStyle({ color: 'blue' });
  });
});
```

## Testing Error Boundaries

```typescript
import { ErrorBoundary } from './ErrorBoundary';

const ThrowingComponent = () => {
  throw new Error('Test error');
};

describe('ErrorBoundary', () => {
  it('renders fallback UI on error', () => {
    // Suppress console.error for expected error
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});

    render(
      <ErrorBoundary fallback={<div>Something went wrong</div>}>
        <ThrowingComponent />
      </ErrorBoundary>
    );

    expect(screen.getByText('Something went wrong')).toBeInTheDocument();
    spy.mockRestore();
  });

  it('renders children when no error', () => {
    render(
      <ErrorBoundary fallback={<div>Error</div>}>
        <div>Content</div>
      </ErrorBoundary>
    );
    expect(screen.getByText('Content')).toBeInTheDocument();
    expect(screen.queryByText('Error')).not.toBeInTheDocument();
  });
});
```

## Testing Modals and Portals

```typescript
describe('Modal', () => {
  it('renders content in portal when open', () => {
    render(<Modal isOpen title="Confirm">Are you sure?</Modal>);
    expect(screen.getByRole('dialog')).toBeInTheDocument();
    expect(screen.getByText('Are you sure?')).toBeInTheDocument();
  });

  it('does not render when closed', () => {
    render(<Modal isOpen={false} title="Confirm">Are you sure?</Modal>);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('calls onClose when backdrop is clicked', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    render(<Modal isOpen title="Confirm" onClose={onClose}>Content</Modal>);

    await user.click(screen.getByRole('dialog').parentElement!);
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('calls onClose when Escape is pressed', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    render(<Modal isOpen title="Confirm" onClose={onClose}>Content</Modal>);

    await user.keyboard('{Escape}');
    expect(onClose).toHaveBeenCalledOnce();
  });
});
```

## Testing with React Router

```typescript
import { MemoryRouter, Route, Routes } from 'react-router-dom';

describe('UserProfile', () => {
  it('renders user details for given route param', () => {
    render(
      <MemoryRouter initialEntries={['/users/42']}>
        <Routes>
          <Route path="/users/:id" element={<UserProfile />} />
        </Routes>
      </MemoryRouter>
    );
    expect(screen.getByRole('heading')).toHaveTextContent('User 42');
  });
});
```

### Testing Navigation

```typescript
const mockNavigate = vi.hoisted(() => vi.fn());
vi.mock('react-router-dom', async (importOriginal) => ({
  ...(await importOriginal<typeof import('react-router-dom')>()),
  useNavigate: () => mockNavigate,
}));

describe('BackButton', () => {
  it('navigates back when clicked', async () => {
    const user = userEvent.setup();
    render(<BackButton />, { wrapper: MemoryRouter });

    await user.click(screen.getByRole('button', { name: /back/i }));
    expect(mockNavigate).toHaveBeenCalledWith(-1);
  });
});
```
