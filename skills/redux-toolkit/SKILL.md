---
name: redux-toolkit
description: Redux Toolkit v1 patterns for state management including configureStore, createSlice, createAsyncThunk, typed hooks, and entity adapter.
user-invocable: true
---

# Redux Toolkit v1 Patterns

## Version Constraints — CRITICAL

- **@reduxjs/toolkit**: ^1.6 (v1.x ONLY)
- **react-redux**: ^7 or ^8
- `.withTypes()` is NOT available — use the casting pattern
- RTK Query (`createApi`) is NOT in v1.x — DO NOT use it
- `extraReducers`: builder callback pattern ONLY (object notation deprecated)
- Middleware: use `.concat()`/`.prepend()` — DO NOT spread `getDefaultMiddleware()`

## Quick Start

```typescript
// store.ts
import { configureStore } from '@reduxjs/toolkit';
import counterReducer from './slices/counterSlice';

export const store = configureStore({ reducer: { counter: counterReducer } });
export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;

// hooks.ts — casting pattern (.withTypes() NOT available)
import { useDispatch, useSelector } from 'react-redux';
import type { TypedUseSelectorHook } from 'react-redux';
export const useAppDispatch: () => AppDispatch = useDispatch;
export const useAppSelector: TypedUseSelectorHook<RootState> = useSelector;

// counterSlice.ts
import { createSlice, PayloadAction } from '@reduxjs/toolkit';
const counterSlice = createSlice({
  name: 'counter',
  initialState: { value: 0 },
  reducers: {
    increment(state) { state.value += 1 },
    incrementByAmount(state, action: PayloadAction<number>) { state.value += action.payload },
  },
});
export const { increment, incrementByAmount } = counterSlice.actions;
export default counterSlice.reducer;
```

## createSlice Rules

- DO type `initialState` with an interface
- DO type actions with `PayloadAction<T>`
- DO mutate state directly (Immer handles immutability) OR return new state — never both
- DO use `prepare` callbacks for payload transformation (e.g., adding `nanoid()`)
- DO export actions and reducer from the slice file

## createAsyncThunk

```typescript
export const fetchUsers = createAsyncThunk<User[], void, { rejectValue: string }>(
  'users/fetch',
  async (_, { rejectWithValue }) => {
    try {
      const res = await fetch('/api/users');
      if (!res.ok) return rejectWithValue('Failed');
      return (await res.json()) as User[];
    } catch { return rejectWithValue('Network error'); }
  }
);
```

### In extraReducers (builder ONLY)

```typescript
extraReducers: (builder) => {
  builder
    .addCase(fetchUsers.pending, (state) => { state.status = 'loading'; state.error = null })
    .addCase(fetchUsers.fulfilled, (state, action) => { state.status = 'succeeded'; state.items = action.payload })
    .addCase(fetchUsers.rejected, (state, action) => {
      state.status = 'failed';
      state.error = action.payload ?? action.error.message ?? 'Unknown';
    });
},
```

### Usage in Components

```typescript
const user = await dispatch(createUser(data)).unwrap(); // throws on rejection
```

### Cancellation

```typescript
const fetchUser = createAsyncThunk('users/fetchById', async (id: string, { signal }) => {
  return fetch(`/api/users/${id}`, { signal }).then(r => r.json());
});
// In useEffect: const promise = dispatch(fetchUser(id)); return () => promise.abort();
```

## Middleware

```typescript
middleware: (getDefaultMiddleware) =>
  getDefaultMiddleware({ serializableCheck: { ignoredActions: ['persist/PERSIST'] } })
    .concat(logger)
    .concat(analytics),
```

## createEntityAdapter

```typescript
const adapter = createEntityAdapter<Article>({
  sortComparer: (a, b) => b.createdAt.localeCompare(a.createdAt),
});

const slice = createSlice({
  name: 'articles',
  initialState: adapter.getInitialState({ status: 'idle' as string, error: null as string | null }),
  reducers: {
    articleAdded: adapter.addOne,
    articleRemoved: adapter.removeOne,
  },
  extraReducers: (builder) => {
    builder.addCase(fetchArticles.fulfilled, (state, action) => {
      adapter.setAll(state, action.payload);
    });
  },
});

export const { selectAll, selectById } = adapter.getSelectors<RootState>(s => s.articles);
```

## Selectors

```typescript
// Inline
export const selectCount = (state: RootState) => state.counter.value;

// Memoized
import { createSelector } from '@reduxjs/toolkit';
export const selectFilteredTodos = createSelector(
  [selectTodos, selectFilter],
  (todos, filter) => filter === 'all' ? todos : todos.filter(t => t.completed === (filter === 'completed'))
);

// Parameterized factory
export const makeSelectUserById = (id: string) =>
  createSelector([(s: RootState) => s.users.items], users => users.find(u => u.id === id));
```

## Best Practices

- DO use typed hooks (`useAppDispatch`, `useAppSelector`) everywhere
- DO keep slices focused on one domain
- DO co-locate selectors with slices
- DO use `'idle' | 'loading' | 'succeeded' | 'failed'` status enum
- DO use `createEntityAdapter` for normalized collections
- DO handle all thunk states (pending, fulfilled, rejected)

## References

- `resources/store-setup.md` — configureStore, middleware, devTools, preloaded state
- `resources/async-patterns.md` — createAsyncThunk lifecycle, error handling, cancellation
- `resources/entity-adapter.md` — normalized state, CRUD operations, selectors
