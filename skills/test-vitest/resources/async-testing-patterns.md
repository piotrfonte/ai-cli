# Async Testing Patterns

## findBy Queries — Elements That Appear Asynchronously

```typescript
it('shows user name after loading', async () => {
  render(<UserProfile userId="1" />);

  // findBy returns a Promise — waits up to 1000ms by default
  const heading = await screen.findByRole('heading', { name: /alice/i });
  expect(heading).toBeInTheDocument();
});
```

- DO use `findBy*` when an element appears after an async operation (fetch, timeout, animation)
- DO NOT use `waitFor` + `getBy` when `findBy` can do the job — `findBy` is cleaner

### Custom Timeout

```typescript
const element = await screen.findByText('Loaded', {}, { timeout: 3000 });
```

## waitFor — Retry Assertions Until They Pass

```typescript
import { waitFor } from '@testing-library/react';

it('updates the count display', async () => {
  const user = userEvent.setup();
  render(<Counter />);

  await user.click(screen.getByRole('button', { name: /increment/i }));

  await waitFor(() => {
    expect(screen.getByTestId('count')).toHaveTextContent('1');
  });
});
```

### waitFor Options

```typescript
await waitFor(
  () => expect(element).toBeVisible(),
  {
    timeout: 2000,    // Max wait time (default: 1000ms)
    interval: 50,     // Poll interval (default: 50ms)
  }
);
```

- DO keep assertions inside `waitFor` minimal — one assertion concept per `waitFor`
- DO NOT put side effects (clicks, typing) inside `waitFor` — only assertions

## waitForElementToBeRemoved

```typescript
it('hides loading spinner after data loads', async () => {
  render(<Dashboard />);

  // Element must exist when called
  expect(screen.getByRole('progressbar')).toBeInTheDocument();
  await waitForElementToBeRemoved(() => screen.queryByRole('progressbar'));

  expect(screen.getByText('Dashboard Content')).toBeInTheDocument();
});
```

- DO pass a callback (not the element) to `waitForElementToBeRemoved` — it re-queries on each poll
- DO use `queryBy*` inside the callback — it returns null when removed instead of throwing

## Testing Loading → Success → Error Flows

```typescript
describe('UserList', () => {
  it('shows loading then users on success', async () => {
    vi.mocked(fetchUsers).mockResolvedValue([
      { id: 1, name: 'Alice' },
      { id: 2, name: 'Bob' },
    ]);

    render(<UserList />);

    // Loading state
    expect(screen.getByRole('progressbar')).toBeInTheDocument();

    // Success state
    await waitForElementToBeRemoved(() => screen.queryByRole('progressbar'));
    expect(screen.getByText('Alice')).toBeInTheDocument();
    expect(screen.getByText('Bob')).toBeInTheDocument();
  });

  it('shows error message on failure', async () => {
    vi.mocked(fetchUsers).mockRejectedValue(new Error('Server error'));

    render(<UserList />);

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent(/server error/i);
  });
});
```

## Testing Debounced Inputs

```typescript
describe('SearchBox', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('debounces search requests', async () => {
    const onSearch = vi.fn();
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
    render(<SearchBox onSearch={onSearch} debounceMs={500} />);

    await user.type(screen.getByRole('searchbox'), 'react');

    // Not called yet during typing
    expect(onSearch).not.toHaveBeenCalled();

    // Advance past debounce
    vi.advanceTimersByTime(500);

    expect(onSearch).toHaveBeenCalledOnce();
    expect(onSearch).toHaveBeenCalledWith('react');
  });

  it('cancels previous debounce on new input', async () => {
    const onSearch = vi.fn();
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
    render(<SearchBox onSearch={onSearch} debounceMs={500} />);

    await user.type(screen.getByRole('searchbox'), 'rea');
    vi.advanceTimersByTime(300);
    await user.type(screen.getByRole('searchbox'), 'ct');
    vi.advanceTimersByTime(500);

    expect(onSearch).toHaveBeenCalledOnce();
    expect(onSearch).toHaveBeenCalledWith('react');
  });
});
```

## Testing Data Fetching with Mocked APIs

### Direct fetch Mock

```typescript
it('displays fetched data', async () => {
  globalThis.fetch = vi.fn().mockResolvedValue({
    ok: true,
    json: () => Promise.resolve({ users: [{ id: 1, name: 'Alice' }] }),
  });

  render(<UserPage />);

  expect(await screen.findByText('Alice')).toBeInTheDocument();
  expect(fetch).toHaveBeenCalledWith('/api/users', expect.any(Object));
});
```

### Testing Error Responses

```typescript
it('shows error on failed fetch', async () => {
  globalThis.fetch = vi.fn().mockResolvedValue({
    ok: false,
    status: 500,
    statusText: 'Internal Server Error',
  });

  render(<UserPage />);

  expect(await screen.findByRole('alert')).toHaveTextContent(/failed to load/i);
});
```

### Testing Network Errors

```typescript
it('shows network error message', async () => {
  globalThis.fetch = vi.fn().mockRejectedValue(new TypeError('Failed to fetch'));

  render(<UserPage />);

  expect(await screen.findByRole('alert')).toHaveTextContent(/network error/i);
});
```

## act() — When You Need It and When You Don't

### When RTL Handles It (most cases)

These already wrap in `act()` — DO NOT add an extra `act()` wrapper:

- `render(<Component />)`
- `await user.click(element)`
- `await screen.findByText('...')`
- `await waitFor(() => ...)`
- `await waitForElementToBeRemoved(() => ...)`

### When You Need act() Directly

Use `act()` for **direct state updates** outside of RTL utilities:

```typescript
import { act } from '@testing-library/react';

// Synchronous state update from renderHook
const { result } = renderHook(() => useCounter());
act(() => result.current.increment());

// Triggering a callback that was captured from a mock
const callback = vi.fn();
render(<Observer onChange={callback} />);
const [registeredCallback] = callback.mock.calls[0];
act(() => registeredCallback('new-value'));

// Advancing fake timers that trigger state updates
act(() => vi.advanceTimersByTime(1000));
```

- DO NOT wrap `render()` in `act()` — it already handles it
- DO NOT wrap `userEvent` calls in `act()` — they already handle it
- DO use `act()` for `renderHook` synchronous state changes
- DO use `act()` when manually triggering captured callbacks that update state

## expect.assertions() for Async Tests

Use when you need to guarantee that assertions inside callbacks actually ran:

```typescript
it('calls onError when request fails', async () => {
  expect.assertions(1);

  const onError = vi.fn();
  vi.mocked(fetchData).mockRejectedValue(new Error('fail'));

  render(<DataLoader onError={onError} />);

  await waitFor(() => {
    expect(onError).toHaveBeenCalledWith(expect.any(Error));
  });
});
```

## Testing Intervals and Polling

```typescript
describe('StatusPoller', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('polls status every 5 seconds', async () => {
    const checkStatus = vi.fn().mockResolvedValue({ status: 'pending' });
    render(<StatusPoller checkStatus={checkStatus} intervalMs={5000} />);

    // Initial call
    await waitFor(() => expect(checkStatus).toHaveBeenCalledTimes(1));

    // Advance 5s — second call
    await act(async () => { vi.advanceTimersByTime(5000); });
    await waitFor(() => expect(checkStatus).toHaveBeenCalledTimes(2));

    // Advance another 5s — third call
    await act(async () => { vi.advanceTimersByTime(5000); });
    await waitFor(() => expect(checkStatus).toHaveBeenCalledTimes(3));
  });

  it('stops polling when status is complete', async () => {
    const checkStatus = vi.fn()
      .mockResolvedValueOnce({ status: 'pending' })
      .mockResolvedValueOnce({ status: 'complete' });

    render(<StatusPoller checkStatus={checkStatus} intervalMs={5000} />);

    await waitFor(() => expect(checkStatus).toHaveBeenCalledTimes(1));
    await act(async () => { vi.advanceTimersByTime(5000); });
    await waitFor(() => expect(checkStatus).toHaveBeenCalledTimes(2));

    // No more calls after complete
    await act(async () => { vi.advanceTimersByTime(15000); });
    expect(checkStatus).toHaveBeenCalledTimes(2);

    expect(screen.getByText(/complete/i)).toBeInTheDocument();
  });
});
```
