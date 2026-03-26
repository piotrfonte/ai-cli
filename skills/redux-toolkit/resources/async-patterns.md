# Async Patterns with createAsyncThunk

## createAsyncThunk Basics

### Type Signature

```typescript
createAsyncThunk<
  ReturnType,     // What the thunk returns on success
  ArgType,        // What you pass when dispatching
  ThunkApiConfig  // Optional config for rejectValue, state, extra, etc.
>(
  typePrefix,     // Action type prefix string
  payloadCreator, // Async function
  options?        // Optional: condition, dispatchConditionRejection, etc.
)
```

### Simple Thunk

```typescript
import { createAsyncThunk } from '@reduxjs/toolkit';

interface User {
  id: string;
  name: string;
  email: string;
}

export const fetchUsers = createAsyncThunk<User[]>(
  'users/fetchAll',
  async () => {
    const response = await fetch('/api/users');
    return (await response.json()) as User[];
  }
);
```

### Thunk with Arguments

```typescript
export const fetchUserById = createAsyncThunk<User, string>(
  'users/fetchById',
  async (userId) => {
    const response = await fetch(`/api/users/${userId}`);
    return (await response.json()) as User;
  }
);

// Dispatch: dispatch(fetchUserById('user-123'))
```

---

## Lifecycle States

Every createAsyncThunk generates three action types:

- `pending` - dispatched when the thunk starts
- `fulfilled` - dispatched when the async function resolves
- `rejected` - dispatched when the async function throws or rejectWithValue is called

### Handling All States with extraReducers Builder

```typescript
import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';

interface UsersState {
  items: User[];
  status: 'idle' | 'loading' | 'succeeded' | 'failed';
  error: string | null;
}

const initialState: UsersState = {
  items: [],
  status: 'idle',
  error: null,
};

const usersSlice = createSlice({
  name: 'users',
  initialState,
  reducers: {
    usersCleared(state) {
      state.items = [];
      state.status = 'idle';
    },
  },
  extraReducers: (builder) => {
    builder
      .addCase(fetchUsers.pending, (state) => {
        state.status = 'loading';
        state.error = null;
      })
      .addCase(fetchUsers.fulfilled, (state, action) => {
        state.status = 'succeeded';
        state.items = action.payload;
      })
      .addCase(fetchUsers.rejected, (state, action) => {
        state.status = 'failed';
        state.error = action.error.message ?? 'Unknown error';
      });
  },
});
```

### Loading State Pattern for Components

```typescript
import { useEffect } from 'react';
import { useAppDispatch, useAppSelector } from '../store/hooks';

function UserList() {
  const dispatch = useAppDispatch();
  const users = useAppSelector((state) => state.users.items);
  const status = useAppSelector((state) => state.users.status);
  const error = useAppSelector((state) => state.users.error);

  useEffect(() => {
    if (status === 'idle') {
      dispatch(fetchUsers());
    }
  }, [dispatch, status]);

  if (status === 'loading') {
    return <div>Loading users...</div>;
  }

  if (status === 'failed') {
    return <div>Error: {error}</div>;
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

## Error Handling

### rejectWithValue for Typed Errors

```typescript
interface ApiError {
  status: number;
  message: string;
  errors?: Record<string, string[]>;
}

export const createUser = createAsyncThunk<
  User,
  { name: string; email: string },
  { rejectValue: ApiError }
>(
  'users/create',
  async (userData, { rejectWithValue }) => {
    const response = await fetch('/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(userData),
    });

    if (!response.ok) {
      const error = await response.json();
      return rejectWithValue(error as ApiError);
    }

    return (await response.json()) as User;
  }
);
```

### Distinguishing rejectWithValue from Unexpected Errors

```typescript
extraReducers: (builder) => {
  builder.addCase(createUser.rejected, (state, action) => {
    state.status = 'failed';

    if (action.payload) {
      // This is a known error from rejectWithValue
      // action.payload is typed as ApiError
      state.apiError = action.payload;
    } else {
      // This is an unexpected error (thrown exception)
      // action.error is a SerializedError
      state.error = action.error.message ?? 'An unexpected error occurred';
    }
  });
},
```

### Network Error Handling

```typescript
export const fetchData = createAsyncThunk<
  Data[],
  void,
  { rejectValue: string }
>(
  'data/fetch',
  async (_, { rejectWithValue }) => {
    try {
      const response = await fetch('/api/data');

      if (!response.ok) {
        if (response.status === 401) {
          return rejectWithValue('Unauthorized -- please log in');
        }
        if (response.status === 403) {
          return rejectWithValue('Forbidden -- insufficient permissions');
        }
        if (response.status === 404) {
          return rejectWithValue('Resource not found');
        }
        return rejectWithValue(`Server error: ${response.status}`);
      }

      return (await response.json()) as Data[];
    } catch (err) {
      if (err instanceof TypeError && err.message === 'Failed to fetch') {
        return rejectWithValue('Network error -- check your connection');
      }
      return rejectWithValue('An unexpected error occurred');
    }
  }
);
```

---

## .unwrap() in Components

Use `.unwrap()` to get the fulfilled value or throw the rejected value as an exception:

```typescript
function CreateUserForm() {
  const dispatch = useAppDispatch();
  const [formError, setFormError] = useState<string | null>(null);

  const handleSubmit = async (data: { name: string; email: string }) => {
    setFormError(null);

    try {
      const newUser = await dispatch(createUser(data)).unwrap();
      // Success -- newUser is the fulfilled payload (User)
      navigate(`/users/${newUser.id}`);
    } catch (err) {
      // err is the rejectWithValue payload (ApiError) or SerializedError
      if (typeof err === 'object' && err !== null && 'message' in err) {
        setFormError((err as { message: string }).message);
      } else {
        setFormError('Failed to create user');
      }
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      {formError && <div className="error">{formError}</div>}
      {/* form fields */}
    </form>
  );
}
```

---

## Cancellation

### AbortController via signal

createAsyncThunk passes an `AbortSignal` via the thunkAPI. The signal is wired to an
AbortController that RTK creates automatically for each dispatched thunk:

```typescript
export const fetchUserById = createAsyncThunk<User, string>(
  'users/fetchById',
  async (userId, { signal }) => {
    const response = await fetch(`/api/users/${userId}`, { signal });
    if (!response.ok) {
      throw new Error('Failed to fetch user');
    }
    return (await response.json()) as User;
  }
);
```

### Cancel on Unmount

```typescript
function UserDetail({ userId }: { userId: string }) {
  const dispatch = useAppDispatch();

  useEffect(() => {
    const promise = dispatch(fetchUserById(userId));

    return () => {
      // Aborts the fetch and dispatches a rejected action
      promise.abort();
    };
  }, [dispatch, userId]);
}
```

### Cancel Previous Request on New Request

```typescript
function SearchResults() {
  const dispatch = useAppDispatch();
  const promiseRef = useRef<ReturnType<typeof dispatch> | null>(null);

  const handleSearch = (query: string) => {
    // Cancel the previous search if still pending
    if (promiseRef.current) {
      (promiseRef.current as { abort: () => void }).abort();
    }
    promiseRef.current = dispatch(searchUsers(query));
  };

  return <input onChange={(e) => handleSearch(e.target.value)} />;
}
```

### Checking Cancellation with thunkAPI.signal

For long-running operations that are not a single fetch call, check the signal
between steps:

```typescript
export const processLargeDataset = createAsyncThunk<
  ProcessResult,
  string,
  { rejectValue: string }
>(
  'data/processLarge',
  async (datasetId, { signal, rejectWithValue }) => {
    const dataset = await fetch(`/api/datasets/${datasetId}`, { signal });
    const items = (await dataset.json()) as DataItem[];

    const results: ProcessedItem[] = [];
    for (const item of items) {
      if (signal.aborted) {
        return rejectWithValue('Processing cancelled');
      }
      const processed = await processItem(item);
      results.push(processed);
    }

    return { datasetId, results };
  }
);
```

### Handling Cancelled Actions in Reducers

```typescript
extraReducers: (builder) => {
  builder.addCase(fetchUserById.rejected, (state, action) => {
    if (action.meta.aborted) {
      // Request was cancelled -- don't update error state
      return;
    }
    state.status = 'failed';
    state.error = action.error.message ?? null;
  });
},
```

---

## Conditional Fetching

### condition Callback to Prevent Duplicate Requests

```typescript
export const fetchUsers = createAsyncThunk<
  User[],
  void,
  { state: RootState }
>(
  'users/fetchAll',
  async () => {
    const response = await fetch('/api/users');
    return (await response.json()) as User[];
  },
  {
    condition(_, { getState }) {
      const { users } = getState();
      if (users.status === 'loading' || users.status === 'succeeded') {
        // Returning false cancels the thunk before it starts.
        // No pending action is dispatched.
        return false;
      }
    },
  }
);
```

### Force Refresh Option

```typescript
export const fetchUsers = createAsyncThunk<
  User[],
  { forceRefresh?: boolean } | void,
  { state: RootState }
>(
  'users/fetchAll',
  async () => {
    const response = await fetch('/api/users');
    return (await response.json()) as User[];
  },
  {
    condition(arg, { getState }) {
      const forceRefresh = arg && typeof arg === 'object' ? arg.forceRefresh : false;
      if (forceRefresh) return true;

      const { users } = getState();
      if (users.status === 'loading' || users.status === 'succeeded') {
        return false;
      }
    },
  }
);

// Usage
dispatch(fetchUsers());                       // Conditional
dispatch(fetchUsers({ forceRefresh: true })); // Always fetch
```

---

## Accessing State and Dispatch in Thunks

### getState

```typescript
export const fetchRelatedPosts = createAsyncThunk<
  Post[],
  void,
  { state: RootState }
>(
  'posts/fetchRelated',
  async (_, { getState }) => {
    const state = getState();
    const currentUserId = state.auth.currentUser?.id;

    if (!currentUserId) {
      throw new Error('Not authenticated');
    }

    const response = await fetch(`/api/users/${currentUserId}/posts`);
    return (await response.json()) as Post[];
  }
);
```

### Dispatching Other Actions from a Thunk

```typescript
export const deleteUserAndCleanup = createAsyncThunk<
  void,
  string,
  { state: RootState }
>(
  'users/deleteWithCleanup',
  async (userId, { dispatch }) => {
    await fetch(`/api/users/${userId}/posts`, { method: 'DELETE' });
    await fetch(`/api/users/${userId}`, { method: 'DELETE' });

    // Dispatch actions to update other slices
    dispatch(postsRemoved(userId));
    dispatch(commentsRemoved(userId));
  }
);
```

---

## Multiple Async Thunks in One Slice

A single slice can handle lifecycle actions from many thunks:

```typescript
interface ProjectsState {
  items: Project[];
  selectedProject: Project | null;
  status: 'idle' | 'loading' | 'succeeded' | 'failed';
  saveStatus: 'idle' | 'saving' | 'saved' | 'failed';
  deleteStatus: 'idle' | 'deleting' | 'deleted' | 'failed';
  error: string | null;
}

const initialState: ProjectsState = {
  items: [],
  selectedProject: null,
  status: 'idle',
  saveStatus: 'idle',
  deleteStatus: 'idle',
  error: null,
};

export const fetchProjects = createAsyncThunk<Project[]>(
  'projects/fetchAll',
  async () => {
    const response = await fetch('/api/projects');
    return (await response.json()) as Project[];
  }
);

export const saveProject = createAsyncThunk<
  Project,
  { id: string; data: Partial<Project> },
  { rejectValue: string }
>(
  'projects/save',
  async ({ id, data }, { rejectWithValue }) => {
    const response = await fetch(`/api/projects/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    if (!response.ok) {
      return rejectWithValue('Failed to save project');
    }
    return (await response.json()) as Project;
  }
);

export const deleteProject = createAsyncThunk<
  string,
  string,
  { rejectValue: string }
>(
  'projects/delete',
  async (projectId, { rejectWithValue }) => {
    const response = await fetch(`/api/projects/${projectId}`, {
      method: 'DELETE',
    });
    if (!response.ok) {
      return rejectWithValue('Failed to delete project');
    }
    return projectId;
  }
);

const projectsSlice = createSlice({
  name: 'projects',
  initialState,
  reducers: {
    resetSaveStatus(state) {
      state.saveStatus = 'idle';
    },
    resetDeleteStatus(state) {
      state.deleteStatus = 'idle';
    },
  },
  extraReducers: (builder) => {
    // Fetch lifecycle
    builder
      .addCase(fetchProjects.pending, (state) => {
        state.status = 'loading';
        state.error = null;
      })
      .addCase(fetchProjects.fulfilled, (state, action) => {
        state.status = 'succeeded';
        state.items = action.payload;
      })
      .addCase(fetchProjects.rejected, (state, action) => {
        state.status = 'failed';
        state.error = action.error.message ?? 'Failed to load projects';
      });

    // Save lifecycle
    builder
      .addCase(saveProject.pending, (state) => {
        state.saveStatus = 'saving';
      })
      .addCase(saveProject.fulfilled, (state, action) => {
        state.saveStatus = 'saved';
        const index = state.items.findIndex((p) => p.id === action.payload.id);
        if (index !== -1) {
          state.items[index] = action.payload;
        }
      })
      .addCase(saveProject.rejected, (state, action) => {
        state.saveStatus = 'failed';
        state.error = action.payload ?? action.error.message ?? null;
      });

    // Delete lifecycle
    builder
      .addCase(deleteProject.pending, (state) => {
        state.deleteStatus = 'deleting';
      })
      .addCase(deleteProject.fulfilled, (state, action) => {
        state.deleteStatus = 'deleted';
        state.items = state.items.filter((p) => p.id !== action.payload);
      })
      .addCase(deleteProject.rejected, (state, action) => {
        state.deleteStatus = 'failed';
        state.error = action.payload ?? action.error.message ?? null;
      });
  },
});

export const { resetSaveStatus, resetDeleteStatus } = projectsSlice.actions;
export default projectsSlice.reducer;
```

---

## Sequential Multi-Step Operations

### Chained Async Steps in a Single Thunk

```typescript
export const submitOrder = createAsyncThunk<
  Order,
  OrderRequest,
  { rejectValue: string }
>(
  'orders/submit',
  async (orderData, { rejectWithValue }) => {
    try {
      // Step 1: Validate inventory
      const validationRes = await fetch('/api/inventory/validate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(orderData.items),
      });

      if (!validationRes.ok) {
        return rejectWithValue('Some items are out of stock');
      }

      // Step 2: Process payment
      const paymentRes = await fetch('/api/payments', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(orderData.payment),
      });

      if (!paymentRes.ok) {
        return rejectWithValue('Payment failed');
      }

      // Step 3: Create order
      const orderRes = await fetch('/api/orders', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(orderData),
      });

      if (!orderRes.ok) {
        return rejectWithValue('Failed to create order');
      }

      return (await orderRes.json()) as Order;
    } catch {
      return rejectWithValue('Network error');
    }
  }
);
```

---

## Matching Multiple Action Types

### addMatcher for Cross-Cutting Concerns

```typescript
import { createSlice, isRejected, isPending, isFulfilled } from '@reduxjs/toolkit';

const appSlice = createSlice({
  name: 'app',
  initialState: {
    globalLoading: false,
    globalError: null as string | null,
  },
  reducers: {
    clearError(state) {
      state.globalError = null;
    },
  },
  extraReducers: (builder) => {
    builder.addMatcher(isPending, (state) => {
      state.globalLoading = true;
    });

    builder.addMatcher(isFulfilled, (state) => {
      state.globalLoading = false;
    });

    builder.addMatcher(isRejected, (state, action) => {
      state.globalLoading = false;
      state.globalError = action.error.message ?? 'Something went wrong';
    });
  },
});
```

### Custom Matchers for Specific Thunks

```typescript
// Match rejected actions from specific thunks only
const isUserActionRejected = isRejected(fetchUsers, createUser, deleteUser);

extraReducers: (builder) => {
  builder.addMatcher(isUserActionRejected, (state, action) => {
    state.userError = action.error.message ?? null;
  });
},
```

---

## Per-Item Loading State

For tracking loading state per entity (e.g., individual delete buttons):

```typescript
interface UsersState {
  items: Record<string, User>;
  loadingIds: Record<string, boolean>;
  errors: Record<string, string>;
}

const initialState: UsersState = {
  items: {},
  loadingIds: {},
  errors: {},
};

export const fetchUserById = createAsyncThunk<User, string>(
  'users/fetchById',
  async (userId) => {
    const response = await fetch(`/api/users/${userId}`);
    return (await response.json()) as User;
  }
);

const usersSlice = createSlice({
  name: 'users',
  initialState,
  reducers: {},
  extraReducers: (builder) => {
    builder
      .addCase(fetchUserById.pending, (state, action) => {
        // action.meta.arg is the original argument passed to the thunk
        state.loadingIds[action.meta.arg] = true;
        delete state.errors[action.meta.arg];
      })
      .addCase(fetchUserById.fulfilled, (state, action) => {
        delete state.loadingIds[action.meta.arg];
        state.items[action.payload.id] = action.payload;
      })
      .addCase(fetchUserById.rejected, (state, action) => {
        delete state.loadingIds[action.meta.arg];
        state.errors[action.meta.arg] =
          action.error.message ?? 'Failed to fetch';
      });
  },
});
```

### Usage in Component

```typescript
function UserCard({ userId }: { userId: string }) {
  const dispatch = useAppDispatch();
  const user = useAppSelector((state) => state.users.items[userId]);
  const isLoading = useAppSelector((state) => !!state.users.loadingIds[userId]);
  const error = useAppSelector((state) => state.users.errors[userId]);

  useEffect(() => {
    if (!user && !isLoading) {
      dispatch(fetchUserById(userId));
    }
  }, [dispatch, userId, user, isLoading]);

  if (isLoading) return <Spinner />;
  if (error) return <ErrorMessage message={error} />;
  if (!user) return null;

  return <div>{user.name}</div>;
}
```
