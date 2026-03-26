# Store Setup Patterns

## configureStore

### Basic Store Configuration

```typescript
// src/store/store.ts
import { configureStore } from '@reduxjs/toolkit';
import usersReducer from './slices/usersSlice';
import postsReducer from './slices/postsSlice';
import notificationsReducer from './slices/notificationsSlice';

export const store = configureStore({
  reducer: {
    users: usersReducer,
    posts: postsReducer,
    notifications: notificationsReducer,
  },
});

// Extract types from the store itself
export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;
```

### Type Extraction

Always extract `RootState` and `AppDispatch` from the store, not from reducers manually:

```typescript
// These types automatically update when you add/remove slices
export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;

// AppDispatch includes thunk dispatch signatures automatically
// when using configureStore (thunk middleware is included by default)
```

---

## Middleware Configuration

### Adding Custom Middleware

Use `.concat()` to add middleware after defaults, `.prepend()` to add before:

```typescript
import { configureStore } from '@reduxjs/toolkit';
import logger from 'redux-logger';

export const store = configureStore({
  reducer: rootReducer,
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware().concat(logger),
});
```

### Multiple Custom Middleware

```typescript
import { configureStore } from '@reduxjs/toolkit';
import type { Middleware } from '@reduxjs/toolkit';

const analyticsMiddleware: Middleware = (storeAPI) => (next) => (action) => {
  // Track dispatched actions
  if (typeof action === 'object' && action !== null && 'type' in action) {
    console.log('Dispatching:', (action as { type: string }).type);
  }
  return next(action);
};

const errorMiddleware: Middleware = (storeAPI) => (next) => (action) => {
  try {
    return next(action);
  } catch (err) {
    console.error('Caught error in middleware:', err);
    throw err;
  }
};

export const store = configureStore({
  reducer: rootReducer,
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware()
      .prepend(errorMiddleware)
      .concat(analyticsMiddleware)
      .concat(logger),
});
```

### Why NOT to Spread getDefaultMiddleware

```typescript
// BAD -- loses type information, can cause issues
middleware: (getDefaultMiddleware) =>
  [...getDefaultMiddleware(), logger],

// GOOD -- preserves types, chainable
middleware: (getDefaultMiddleware) =>
  getDefaultMiddleware().concat(logger),
```

### Configuring Default Middleware

```typescript
export const store = configureStore({
  reducer: rootReducer,
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware({
      // Customize serializable check (e.g., for redux-persist)
      serializableCheck: {
        ignoredActions: [
          'persist/PERSIST',
          'persist/REHYDRATE',
          'persist/REGISTER',
        ],
        ignoredPaths: ['some.path.with.nonSerializableData'],
      },
      // Customize immutability check
      immutableCheck: {
        ignoredPaths: ['largeDataSet'],
      },
      // Thunk middleware extra argument
      thunk: {
        extraArgument: { api: apiClient },
      },
    }),
});
```

### Typed Extra Argument for Thunks

```typescript
// Define the extra argument type
interface ThunkExtra {
  api: typeof apiClient;
}

export const store = configureStore({
  reducer: rootReducer,
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware({
      thunk: {
        extraArgument: { api: apiClient } as ThunkExtra,
      },
    }),
});

// Use in thunks
export const fetchData = createAsyncThunk<
  Data[],
  void,
  { extra: ThunkExtra }
>(
  'data/fetch',
  async (_, { extra: { api } }) => {
    return api.getData();
  }
);
```

---

## Typed Hooks

### Standard Pattern (react-redux v7/v8)

```typescript
// src/store/hooks.ts
import { useDispatch, useSelector } from 'react-redux';
import type { TypedUseSelectorHook } from 'react-redux';
import type { RootState, AppDispatch } from './store';

// The casting pattern -- .withTypes() is NOT available in v7/v8
export const useAppDispatch: () => AppDispatch = useDispatch;
export const useAppSelector: TypedUseSelectorHook<RootState> = useSelector;
```

### Why Typed Hooks Matter

```typescript
// Without typed hooks -- no type safety
const dispatch = useDispatch(); // dispatch is typed as Dispatch<AnyAction>
const count = useSelector((state) => state.counter.value); // state is unknown

// With typed hooks -- full type safety
const dispatch = useAppDispatch(); // dispatch is AppDispatch (includes thunk types)
const count = useAppSelector((state) => state.counter.value); // state is RootState
```

### Usage in Components

```typescript
import { useAppDispatch, useAppSelector } from '../store/hooks';
import { fetchUsers, selectAllUsers, selectUsersStatus } from '../store/slices/usersSlice';

function UserList() {
  const dispatch = useAppDispatch();
  const users = useAppSelector(selectAllUsers);
  const status = useAppSelector(selectUsersStatus);

  useEffect(() => {
    if (status === 'idle') {
      dispatch(fetchUsers());
    }
  }, [dispatch, status]);

  if (status === 'loading') {
    return <div>Loading...</div>;
  }

  if (status === 'failed') {
    return <div>Error loading users</div>;
  }

  return (
    <ul>
      {users.map((user) => (
        <li key={user.id}>{user.name}</li>
      ))}
    </ul>
  );
}
```

---

## Provider Setup

### React 18 with createRoot

```typescript
// src/main.tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { Provider } from 'react-redux';
import { store } from './store/store';
import App from './App';

const root = createRoot(document.getElementById('root')!);

root.render(
  <StrictMode>
    <Provider store={store}>
      <App />
    </Provider>
  </StrictMode>
);
```

### React 17 with render

```typescript
// src/index.tsx
import { StrictMode } from 'react';
import { render } from 'react-dom';
import { Provider } from 'react-redux';
import { store } from './store/store';
import App from './App';

render(
  <StrictMode>
    <Provider store={store}>
      <App />
    </Provider>
  </StrictMode>,
  document.getElementById('root')
);
```

---

## DevTools Configuration

```typescript
export const store = configureStore({
  reducer: rootReducer,
  // Disable devtools in production
  devTools: process.env.NODE_ENV !== 'production',
});
```

### Advanced DevTools Options

```typescript
export const store = configureStore({
  reducer: rootReducer,
  devTools: process.env.NODE_ENV !== 'production' && {
    name: 'MyApp',
    maxAge: 50,           // Max number of actions to keep
    trace: true,          // Record call stack for actions
    traceLimit: 25,       // Max stack trace frames
  },
});
```

---

## Preloaded State

```typescript
// Load persisted state
function loadState(): Partial<RootState> | undefined {
  try {
    const serialized = localStorage.getItem('reduxState');
    if (serialized === null) return undefined;
    return JSON.parse(serialized) as Partial<RootState>;
  } catch {
    return undefined;
  }
}

export const store = configureStore({
  reducer: rootReducer,
  preloadedState: loadState(),
});

// Subscribe to save state
store.subscribe(() => {
  const state = store.getState();
  try {
    localStorage.setItem(
      'reduxState',
      JSON.stringify({
        // Only persist specific slices
        settings: state.settings,
      })
    );
  } catch {
    // Ignore write errors
  }
});
```

---

## Store for Testing

```typescript
// src/store/testUtils.ts
import { configureStore } from '@reduxjs/toolkit';
import type { PreloadedState } from '@reduxjs/toolkit';
import type { RootState } from './store';
import usersReducer from './slices/usersSlice';
import postsReducer from './slices/postsSlice';

export function setupStore(preloadedState?: PreloadedState<RootState>) {
  return configureStore({
    reducer: {
      users: usersReducer,
      posts: postsReducer,
    },
    preloadedState,
  });
}

export type AppStore = ReturnType<typeof setupStore>;
```

### Test Helper with Provider

```typescript
import { render } from '@testing-library/react';
import type { RenderOptions } from '@testing-library/react';
import { Provider } from 'react-redux';
import type { PreloadedState } from '@reduxjs/toolkit';
import type { RootState } from './store';
import { setupStore } from './testUtils';
import type { AppStore } from './testUtils';

interface ExtendedRenderOptions extends Omit<RenderOptions, 'queries'> {
  preloadedState?: PreloadedState<RootState>;
  store?: AppStore;
}

export function renderWithProviders(
  ui: React.ReactElement,
  {
    preloadedState = {},
    store = setupStore(preloadedState),
    ...renderOptions
  }: ExtendedRenderOptions = {}
) {
  function Wrapper({ children }: { children: React.ReactNode }) {
    return <Provider store={store}>{children}</Provider>;
  }

  return {
    store,
    ...render(ui, { wrapper: Wrapper, ...renderOptions }),
  };
}
```

### Usage in Tests

```typescript
import { renderWithProviders } from '../store/testUtils';
import UserList from './UserList';

test('renders users from preloaded state', () => {
  const { getByText } = renderWithProviders(<UserList />, {
    preloadedState: {
      users: {
        items: [{ id: '1', name: 'Alice', email: 'alice@test.com' }],
        status: 'succeeded',
        error: null,
      },
    },
  });

  expect(getByText('Alice')).toBeInTheDocument();
});
```

---

## Complete Store File Example

```typescript
// src/store/store.ts
import { configureStore } from '@reduxjs/toolkit';
import usersReducer from './slices/usersSlice';
import postsReducer from './slices/postsSlice';
import notificationsReducer from './slices/notificationsSlice';
import settingsReducer from './slices/settingsSlice';

export const store = configureStore({
  reducer: {
    users: usersReducer,
    posts: postsReducer,
    notifications: notificationsReducer,
    settings: settingsReducer,
  },
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware({
      serializableCheck: {
        ignoredActions: ['persist/PERSIST'],
      },
    }),
  devTools: process.env.NODE_ENV !== 'production',
});

export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;
```

```typescript
// src/store/hooks.ts
import { useDispatch, useSelector } from 'react-redux';
import type { TypedUseSelectorHook } from 'react-redux';
import type { RootState, AppDispatch } from './store';

export const useAppDispatch: () => AppDispatch = useDispatch;
export const useAppSelector: TypedUseSelectorHook<RootState> = useSelector;
```

---

## Displaced Patterns from SKILL.md

### DevTools Configuration

```typescript
export const store = configureStore({
  reducer: rootReducer,
  devTools: process.env.NODE_ENV !== 'production',
});
```

### Preloaded State

```typescript
export const store = configureStore({
  reducer: rootReducer,
  preloadedState: { counter: { value: 10 } },
});
```

### Provider Setup

```typescript
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { Provider } from 'react-redux';
import { store } from './store/store';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Provider store={store}>
      <App />
    </Provider>
  </StrictMode>
);
```

### Responding to Actions from Other Slices

```typescript
// authSlice.ts
export const logout = createAction('auth/logout');

// usersSlice.ts
extraReducers: (builder) => {
  builder.addCase(logout, () => initialState);
},
```

### addMatcher and addDefaultCase

```typescript
extraReducers: (builder) => {
  builder.addMatcher(
    (action) => action.type.endsWith('/rejected'),
    (state, action) => { state.globalError = action.error.message ?? 'Something went wrong'; }
  );
  builder.addDefaultCase((state) => { /* optional fallback */ });
},
```

### Prepare Callbacks

```typescript
const postsSlice = createSlice({
  name: 'posts',
  initialState: { items: [] as Post[] },
  reducers: {
    addPost: {
      reducer(state, action: PayloadAction<Post>) { state.items.push(action.payload) },
      prepare(title: string, body: string) {
        return { payload: { id: nanoid(), title, body, createdAt: new Date().toISOString() } };
      },
    },
  },
});
```

### Immer Patterns

```typescript
reducers: {
  // Mutate directly
  addItem(state, action: PayloadAction<Item>) { state.items.push(action.payload) },
  // Return new state (replaces entire slice)
  resetItems() { return initialState },
  // Nested mutations
  updateNested(state, action: PayloadAction<{ id: string; name: string }>) {
    const item = state.items.find(i => i.id === action.payload.id);
    if (item) item.details.name = action.payload.name;
  },
  // Partial update
  updateSettings(state, action: PayloadAction<Partial<Settings>>) {
    Object.assign(state.settings, action.payload);
  },
},
```

### File Organization

```
src/store/
  store.ts              # configureStore, type exports
  hooks.ts              # useAppDispatch, useAppSelector
  slices/
    usersSlice.ts       # Slice + selectors + thunks
    postsSlice.ts
```

For larger projects:

```
src/store/slices/users/
  usersSlice.ts
  usersThunks.ts
  usersSelectors.ts
  types.ts
```
