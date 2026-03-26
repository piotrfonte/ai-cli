---
name: react-query
description: React Query v3 patterns for server state management including useQuery, useMutation, query keys, cache invalidation, and optimistic updates.
user-invocable: true
---

# React Query v3 — Server State Management

This skill covers `react-query` ^3.0-3.39. Do NOT use `@tanstack/react-query` (v4/v5) APIs.

## Quick Start

```typescript
import { useQuery, useMutation, useQueryClient } from 'react-query';

// Fetch
const { data, isLoading, isError, error } = useQuery<User, Error>(
  ['user', userId],
  () => fetchUser(userId),
  { enabled: !!userId, staleTime: 5 * 60 * 1000 }
);

// Mutate + invalidate
const queryClient = useQueryClient();
const mutation = useMutation<Todo, Error, CreateTodoInput>(
  (input) => api.post('/todos', input).then(r => r.data),
  { onSuccess: () => queryClient.invalidateQueries(['todos']) }
);
```

## Version Constraints — DO NOT USE v4/v5 APIs

| v3 (correct) | v4/v5 (WRONG) |
|---|---|
| `import from 'react-query'` | `import from '@tanstack/react-query'` |
| `cacheTime` | `gcTime` |
| `isLoading` | `isPending` |
| `useErrorBoundary: true` | `throwOnError` |
| `keepPreviousData: true` | `placeholderData: keepPreviousData` |
| `onSuccess/onError/onSettled` on useQuery | Removed in v5 |

## useQuery Rules

- DO provide type params: `useQuery<TData, TError>(key, fn, opts)`
- DO use `enabled: !!value` for conditional queries
- DO set `staleTime` for data that doesn't change often
- DO use `select` to transform/subset data
- DO use `keepPreviousData: true` for pagination

### Key Options

- `staleTime`: ms before data is considered stale (default: 0)
- `cacheTime`: ms inactive cache is kept (default: 5min)
- `enabled`: disable query until condition is met
- `select`: transform data before returning
- `onSuccess/onError/onSettled`: lifecycle callbacks (v3 only)
- `useErrorBoundary`: throw to nearest ErrorBoundary
- `retry`: number of retries (default: 3)

## Query Keys

```typescript
useQuery(['todos'], fetchTodos);
useQuery(['todo', todoId], () => fetchTodo(todoId));
useQuery(['todos', { status: 'done', page: 1 }], fetchFiltered);
```

### Key Factory Pattern

```typescript
const todoKeys = {
  all: ['todos'] as const,
  lists: () => [...todoKeys.all, 'list'] as const,
  list: (filters: Filters) => [...todoKeys.lists(), filters] as const,
  detail: (id: string) => [...todoKeys.all, 'detail', id] as const,
};
```

## useMutation Rules

- DO invalidate related queries in `onSuccess` or `onSettled`
- DO handle errors with `onError` or try/catch with `mutateAsync`
- DO use `setFieldError`/`setErrors` for server validation errors

### Mutation Return Values

- `mutate(vars)` — fire and forget
- `mutateAsync(vars)` — returns Promise
- `isLoading`, `isError`, `isSuccess`, `isIdle`
- `data`, `error`, `reset()`

## Cache Invalidation

```typescript
queryClient.invalidateQueries(['todos']);           // prefix match
queryClient.invalidateQueries(['todos'], { exact: true }); // exact only
queryClient.setQueryData<Todo[]>(['todos'], old => [...(old ?? []), newTodo]);
queryClient.removeQueries(['todo', todoId]);
```

## Optimistic Updates

```typescript
useMutation(updateTodo, {
  onMutate: async (newTodo) => {
    await queryClient.cancelQueries(['todos']);
    const previous = queryClient.getQueryData<Todo[]>(['todos']);
    queryClient.setQueryData<Todo[]>(['todos'], old =>
      old?.map(t => t.id === newTodo.id ? { ...t, ...newTodo } : t) ?? []
    );
    return { previous };
  },
  onError: (_err, _vars, ctx) => {
    if (ctx?.previous) queryClient.setQueryData(['todos'], ctx.previous);
  },
  onSettled: () => queryClient.invalidateQueries(['todos']),
});
```

## Dependent Queries

```typescript
const userQuery = useQuery(['user', userId], () => fetchUser(userId!), { enabled: !!userId });
const postsQuery = useQuery(
  ['posts', userQuery.data?.id],
  () => fetchPosts(userQuery.data!.id),
  { enabled: !!userQuery.data?.id }
);
```

## References

- `resources/query-patterns.md` — pagination, infinite scroll, polling, prefetching, staleTime vs cacheTime
- `resources/mutation-patterns.md` — optimistic/pessimistic updates, cache manipulation, invalidation strategies
