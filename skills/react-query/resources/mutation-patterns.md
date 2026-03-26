# Mutation Patterns -- React Query v3

Advanced mutation patterns for `react-query` ^3.0-3.39. All examples use TypeScript.

> **IMPORTANT**: This document covers React Query v3. Import from `react-query`, not `@tanstack/react-query`.

## useMutation Full API

### Signature and Type Parameters

```typescript
import { useMutation, useQueryClient } from 'react-query';

const mutation = useMutation<
  TData,       // Return type from mutationFn
  TError,      // Error type
  TVariables,  // Input type passed to mutate()
  TContext      // Context type returned from onMutate (used for rollback)
>(mutationFn, options?);
```

### All Options

```typescript
interface UpdateUserInput { id: string; name?: string; email?: string }
interface User { id: string; name: string; email: string; updatedAt: string }

function useUpdateUser() {
  const queryClient = useQueryClient();

  return useMutation<User, Error, UpdateUserInput, { previous: User | undefined }>(
    (input) => api.patch<User>(`/users/${input.id}`, input).then((r) => r.data),
    {
      onMutate: async (variables) => {
        // Runs BEFORE mutationFn. Return value becomes `context`.
        await queryClient.cancelQueries(['user', variables.id]);
        const previous = queryClient.getQueryData<User>(['user', variables.id]);
        return { previous };
      },
      onSuccess: (data, variables, context) => {
        // Runs when mutationFn resolves.
        queryClient.setQueryData(['user', variables.id], data);
      },
      onError: (error, variables, context) => {
        // Runs when mutationFn rejects.
        if (context?.previous) {
          queryClient.setQueryData(['user', variables.id], context.previous);
        }
      },
      onSettled: (data, error, variables, context) => {
        // Always runs after onSuccess or onError.
        queryClient.invalidateQueries(['user', variables.id]);
      },
      retry: false,              // Default for mutations (queries default to 3)
      useErrorBoundary: false,   // v3 name; v5 renamed to throwOnError
    }
  );
}
```

### Return Values and Status

```typescript
const mutation = useUpdateUser();

// Fire-and-forget
mutation.mutate(variables);

// Per-call callbacks (additive to hook-level)
mutation.mutate(variables, {
  onSuccess: (data) => { form.reset(); },
  onError: (error) => { /* additional handling */ },
  onSettled: () => { /* additional cleanup */ },
});

// Promise-based
const result = await mutation.mutateAsync(variables);

// Status flags
mutation.isIdle;      // Before first mutate() call
mutation.isLoading;   // While mutationFn is in flight
mutation.isSuccess;   // After mutationFn resolved
mutation.isError;     // After mutationFn rejected

// Data
mutation.data;        // TData from last success
mutation.error;       // TError from last failure
mutation.variables;   // TVariables from last call

// Reset to idle state
mutation.reset();
```

## Optimistic Updates -- Full Pattern

The canonical three-step pattern: snapshot in `onMutate`, rollback in `onError`, re-sync in `onSettled`.

```typescript
interface Todo { id: string; title: string; completed: boolean }
interface ToggleTodoInput { id: string; completed: boolean }

function useToggleTodo() {
  const queryClient = useQueryClient();

  return useMutation<Todo, Error, ToggleTodoInput, { previousTodos: Todo[] | undefined }>(
    (input) => api.patch<Todo>(`/todos/${input.id}`, input).then((r) => r.data),
    {
      // Step 1: Cancel queries, snapshot previous state, optimistically update cache
      onMutate: async (newTodo) => {
        await queryClient.cancelQueries(['todos']);
        const previousTodos = queryClient.getQueryData<Todo[]>(['todos']);

        queryClient.setQueryData<Todo[]>(['todos'], (old) =>
          (old ?? []).map((t) => (t.id === newTodo.id ? { ...t, ...newTodo } : t))
        );

        return { previousTodos };
      },

      // Step 2: Rollback from snapshot on error
      onError: (_err, _vars, context) => {
        if (context?.previousTodos) {
          queryClient.setQueryData(['todos'], context.previousTodos);
        }
      },

      // Step 3: Invalidate to refetch server truth
      onSettled: () => {
        queryClient.invalidateQueries(['todos']);
      },
    }
  );
}
```

### Multi-Cache Optimistic Update

When a mutation affects both list and detail caches, update and rollback both.

```typescript
type RollbackCtx = { previousList: User[] | undefined; previousDetail: User | undefined };

function useUpdateUser(userId: string) {
  const queryClient = useQueryClient();

  return useMutation<User, Error, Partial<User>, RollbackCtx>(
    (input) => api.patch<User>(`/users/${userId}`, input).then((r) => r.data),
    {
      onMutate: async (input) => {
        await Promise.all([
          queryClient.cancelQueries(['users']),
          queryClient.cancelQueries(['user', userId]),
        ]);
        const previousList = queryClient.getQueryData<User[]>(['users']);
        const previousDetail = queryClient.getQueryData<User>(['user', userId]);

        queryClient.setQueryData<User[]>(['users'], (old) =>
          (old ?? []).map((u) => (u.id === userId ? { ...u, ...input } : u))
        );
        if (previousDetail) {
          queryClient.setQueryData<User>(['user', userId], { ...previousDetail, ...input });
        }

        return { previousList, previousDetail };
      },
      onError: (_err, _vars, ctx) => {
        if (ctx?.previousList) queryClient.setQueryData(['users'], ctx.previousList);
        if (ctx?.previousDetail) queryClient.setQueryData(['user', userId], ctx.previousDetail);
      },
      onSettled: () => {
        queryClient.invalidateQueries(['users']);
        queryClient.invalidateQueries(['user', userId]);
      },
    }
  );
}
```

## Pessimistic Updates

Wait for the server to confirm before updating the cache. Simpler, no rollback needed.

```typescript
function useCreateTodo() {
  const queryClient = useQueryClient();

  return useMutation<Todo, Error, CreateTodoInput>(
    (input) => api.post<Todo>('/todos', input).then((r) => r.data),
    {
      onSuccess: (newTodo) => {
        // Server confirmed -- update cache with real data
        queryClient.setQueryData<Todo[]>(['todos'], (old) => [...(old ?? []), newTodo]);
        queryClient.setQueryData<Todo>(['todo', newTodo.id], newTodo);
      },
    }
  );
}

function useDeleteTodo() {
  const queryClient = useQueryClient();

  return useMutation<void, Error, string>(
    (todoId) => api.delete(`/todos/${todoId}`).then(() => undefined),
    {
      onSuccess: (_data, todoId) => {
        queryClient.setQueryData<Todo[]>(['todos'], (old) =>
          (old ?? []).filter((t) => t.id !== todoId)
        );
        queryClient.removeQueries(['todo', todoId]);
      },
    }
  );
}
```

## Direct Cache Manipulation with setQueryData

```typescript
const queryClient = useQueryClient();

// Read cache (undefined if not cached)
const cached = queryClient.getQueryData<User>(['user', userId]);

// Write a value
queryClient.setQueryData<User>(['user', userId], updatedUser);

// Updater function
queryClient.setQueryData<Todo[]>(['todos'], (old) => {
  if (!old) return [newTodo];
  return [...old, newTodo];
});

// Update nested structures
queryClient.setQueryData<Team>(['team', teamId], (old) => {
  if (!old) return old!;
  return { ...old, members: old.members.filter((m) => m.id !== memberId) };
});

// Update all matching queries (e.g., all paginated pages)
queryClient.setQueriesData<PaginatedResult<Todo>>(['todos', 'list'], (old) => {
  if (!old) return old!;
  return { ...old, items: old.items.filter((t) => t.id !== deletedId), total: old.total - 1 };
});
```

## Invalidation Strategies

### exact: true

```typescript
// Fuzzy: invalidates ['todos'], ['todos', 1], ['todos', { page: 1 }], etc.
queryClient.invalidateQueries(['todos']);

// Exact: invalidates ONLY ['todos'], nothing else
queryClient.invalidateQueries(['todos'], { exact: true });
```

### Fuzzy Matching by Query Key Prefix

```typescript
// Given active queries: ['users'], ['users', 'list'], ['users', 'detail', 'u1']

queryClient.invalidateQueries(['users']);                // All three
queryClient.invalidateQueries(['users', 'list']);        // Only list queries
queryClient.invalidateQueries(['users', 'detail']);      // Only detail queries

// Predicate for complex matching
queryClient.invalidateQueries({
  predicate: (query) =>
    query.queryKey[0] === 'users' &&
    (query.queryKey[2] as { role?: string })?.role === 'admin',
});
```

### invalidateQueries vs refetchQueries

```typescript
// invalidateQueries: marks stale. Active queries refetch. Inactive refetch on next mount.
queryClient.invalidateQueries(['todos']);

// refetchQueries: forces immediate refetch of active queries regardless of staleness.
queryClient.refetchQueries(['todos']);

// refetchQueries including inactive (unmounted) queries
queryClient.refetchQueries(['todos'], { inactive: true });

// Prefer invalidateQueries in most mutation callbacks.
// Use refetchQueries when you MUST guarantee fresh data even for unmounted queries.
```

### Cascading Invalidation After Mutation

```typescript
function useDeleteProject() {
  const queryClient = useQueryClient();

  return useMutation<void, Error, string>(
    (projectId) => api.delete(`/projects/${projectId}`).then(() => undefined),
    {
      onSuccess: (_data, projectId) => {
        queryClient.removeQueries(['project', projectId]);
        queryClient.invalidateQueries(['projects']);
        queryClient.invalidateQueries(['tasks', { projectId }]);
        queryClient.invalidateQueries(['dashboard']);
      },
    }
  );
}
```

## Combining Multiple Mutations

### Independent Mutations from One Hook

```typescript
function useProjectActions(projectId: string) {
  const queryClient = useQueryClient();

  const update = useMutation<Project, Error, Partial<Project>>(
    (data) => api.patch<Project>(`/projects/${projectId}`, data).then((r) => r.data),
    { onSuccess: () => queryClient.invalidateQueries(['project', projectId]) }
  );

  const archive = useMutation<void, Error, void>(
    () => api.post(`/projects/${projectId}/archive`).then(() => undefined),
    { onSuccess: () => { queryClient.invalidateQueries(['project', projectId]); queryClient.invalidateQueries(['projects']); } }
  );

  const remove = useMutation<void, Error, void>(
    () => api.delete(`/projects/${projectId}`).then(() => undefined),
    { onSuccess: () => { queryClient.removeQueries(['project', projectId]); queryClient.invalidateQueries(['projects']); } }
  );

  return { update, archive, remove };
}
```

### Sequential Mutations with mutateAsync

```typescript
function useOnboardUser() {
  const createUser = useMutation<User, Error, CreateUserInput>(createUserApi);
  const assignRole = useMutation<void, Error, { userId: string; role: string }>(assignRoleApi);
  const sendWelcome = useMutation<void, Error, string>(sendWelcomeApi);

  const onboard = async (input: CreateUserInput & { role: string }) => {
    const user = await createUser.mutateAsync(input);
    await assignRole.mutateAsync({ userId: user.id, role: input.role });
    await sendWelcome.mutateAsync(user.id);
    return user;
  };

  return {
    onboard,
    isLoading: createUser.isLoading || assignRole.isLoading || sendWelcome.isLoading,
    error: createUser.error || assignRole.error || sendWelcome.error,
  };
}
```

## Global Mutation Defaults via QueryClient

```typescript
const queryClient = new QueryClient({
  defaultOptions: {
    mutations: {
      retry: false,
      useErrorBoundary: false,
      onError: (error) => {
        toast.error(`Action failed: ${(error as Error).message}`);
      },
    },
  },
});

// Per-mutation-key defaults
queryClient.setMutationDefaults(['createTodo'], {
  mutationFn: (input: CreateTodoInput) =>
    api.post<Todo>('/todos', input).then((r) => r.data),
  onSuccess: () => {
    queryClient.invalidateQueries(['todos']);
  },
});

// Use with just the key -- picks up defaults automatically
function useCreateTodo() {
  return useMutation<Todo, Error, CreateTodoInput>(['createTodo']);
}
```

## Error Handling Patterns

### Typed API Errors

```typescript
interface ApiError { status: number; message: string; details?: Record<string, string[]> }

function useCreateUser() {
  const queryClient = useQueryClient();

  return useMutation<User, ApiError, CreateUserInput>(
    (input) => api.post<User>('/users', input).then((r) => r.data),
    {
      onError: (error) => {
        if (error.status === 409) toast.error('User already exists.');
        else if (error.status !== 422) toast.error(error.message);
        // 422 with details: let component display field-level errors
      },
      onSuccess: () => queryClient.invalidateQueries(['users']),
    }
  );
}
```

### Form-Level Error Handling

```typescript
function CreateUserForm() {
  const createUser = useCreateUser();
  const [fieldErrors, setFieldErrors] = useState<Record<string, string[]>>({});

  const handleSubmit = async (data: CreateUserInput) => {
    setFieldErrors({});
    try {
      await createUser.mutateAsync(data);
      navigate('/users');
    } catch (error) {
      const apiError = error as ApiError;
      if (apiError.status === 422 && apiError.details) {
        setFieldErrors(apiError.details);
      }
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      <input name="email" />
      {fieldErrors.email?.map((msg) => <p key={msg} className="error">{msg}</p>)}
      <button disabled={createUser.isLoading}>
        {createUser.isLoading ? 'Creating...' : 'Create'}
      </button>
    </form>
  );
}
```

### Error Boundary and Conditional Retry

```typescript
// Throw to error boundary
useMutation(criticalAction, { useErrorBoundary: true });

// Conditionally throw (only 5xx)
useMutation<void, ApiError, Input>(action, {
  useErrorBoundary: (error) => error.status >= 500,
  onError: (error) => {
    if (error.status < 500) toast.error(error.message);
  },
});

// Custom retry logic
useMutation<void, ApiError, PaymentInput>(processPayment, {
  retry: (failureCount, error) => {
    if (error.status >= 400 && error.status < 500) return false;
    return failureCount < 3;
  },
  retryDelay: (attempt) => Math.min(1000 * 2 ** attempt, 10000),
});
```
