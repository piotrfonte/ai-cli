# Query Patterns -- React Query v3

Advanced query patterns for `react-query` ^3.0-3.39. All examples use TypeScript.

> **IMPORTANT**: This document covers React Query v3. Import from `react-query`, not `@tanstack/react-query`.

## Dependent (Serial) Queries

Dependent queries execute in sequence where one query's result feeds into the next. Use the `enabled` option to control execution.

### Basic Dependency Chain

```typescript
import { useQuery } from 'react-query';

interface Organization {
  id: string;
  name: string;
  settingsId: string;
}

interface OrgSettings {
  theme: string;
  features: string[];
}

function useOrgSettings(orgId: string | undefined) {
  const orgQuery = useQuery<Organization, Error>(
    ['org', orgId],
    () => api.get<Organization>(`/orgs/${orgId}`).then((r) => r.data),
    {
      enabled: !!orgId,
    }
  );

  const settingsQuery = useQuery<OrgSettings, Error>(
    ['orgSettings', orgQuery.data?.settingsId],
    () =>
      api
        .get<OrgSettings>(`/settings/${orgQuery.data!.settingsId}`)
        .then((r) => r.data),
    {
      enabled: !!orgQuery.data?.settingsId,
    }
  );

  return {
    org: orgQuery.data,
    settings: settingsQuery.data,
    isLoading: orgQuery.isLoading || (orgQuery.isSuccess && settingsQuery.isLoading),
    error: orgQuery.error || settingsQuery.error,
  };
}
```

### Parallel-Then-Dependent Pattern

```typescript
function useProjectDashboard(projectId: string) {
  // These two run in parallel
  const project = useQuery(
    ['project', projectId],
    () => fetchProject(projectId)
  );

  const team = useQuery(
    ['project', projectId, 'team'],
    () => fetchProjectTeam(projectId)
  );

  // This depends on both completing
  const metrics = useQuery(
    ['project', projectId, 'metrics', { memberCount: team.data?.length }],
    () =>
      fetchProjectMetrics(projectId, {
        memberCount: team.data!.length,
        startDate: project.data!.startDate,
      }),
    {
      enabled: !!project.data && !!team.data,
    }
  );

  return { project, team, metrics };
}
```

## Polling with refetchInterval

Polling queries automatically refetch at a specified interval.

```typescript
interface JobStatus {
  id: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  progress: number;
}

function useJobStatus(jobId: string) {
  return useQuery<JobStatus, Error>(
    ['job', jobId],
    () => api.get<JobStatus>(`/jobs/${jobId}`).then((r) => r.data),
    {
      // Poll every 2 seconds
      refetchInterval: 2000,

      // Stop polling when job is done
      refetchInterval: (data) => {
        if (data?.status === 'completed' || data?.status === 'failed') {
          return false; // Stop polling
        }
        return 2000;
      },

      // Continue polling even when tab is backgrounded
      refetchIntervalInBackground: true,

      onSuccess: (data) => {
        if (data.status === 'completed') {
          toast.success('Job completed!');
        }
      },
    }
  );
}
```

### Smart Polling with Backoff

```typescript
function useSmartPolling(resourceId: string) {
  const [pollInterval, setPollInterval] = useState(1000);

  return useQuery<ResourceStatus, Error>(
    ['resource', resourceId],
    () => fetchResourceStatus(resourceId),
    {
      refetchInterval: pollInterval,
      onSuccess: (data) => {
        if (data.status === 'completed') {
          setPollInterval(0); // Stop polling
        } else {
          // Exponential backoff: 1s, 2s, 4s, 8s, max 30s
          setPollInterval((prev) => Math.min(prev * 2, 30000));
        }
      },
    }
  );
}
```

## Pagination

### Offset-Based Pagination

```typescript
interface PaginatedResult<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
  totalPages: number;
}

interface TodoFilters {
  status?: 'all' | 'active' | 'completed';
  search?: string;
}

function usePaginatedTodos(page: number, pageSize: number, filters: TodoFilters) {
  return useQuery<PaginatedResult<Todo>, Error>(
    ['todos', 'list', { page, pageSize, ...filters }],
    () =>
      api
        .get<PaginatedResult<Todo>>('/todos', {
          params: { page, pageSize, ...filters },
        })
        .then((r) => r.data),
    {
      keepPreviousData: true,   // Keep old data while new page loads
      staleTime: 30 * 1000,    // 30 seconds
    }
  );
}

function TodoListPage() {
  const [page, setPage] = useState(1);
  const [filters, setFilters] = useState<TodoFilters>({ status: 'all' });
  const pageSize = 25;

  const { data, isLoading, isPreviousData, isFetching } = usePaginatedTodos(
    page,
    pageSize,
    filters
  );

  // Reset to page 1 when filters change
  const handleFilterChange = (newFilters: TodoFilters) => {
    setFilters(newFilters);
    setPage(1);
  };

  return (
    <div>
      <FilterBar filters={filters} onChange={handleFilterChange} />

      {isLoading ? (
        <Skeleton count={pageSize} />
      ) : (
        <div style={{ opacity: isPreviousData ? 0.6 : 1, transition: 'opacity 0.2s' }}>
          {data?.items.map((todo) => (
            <TodoRow key={todo.id} todo={todo} />
          ))}
        </div>
      )}

      {isFetching && !isLoading && <InlineSpinner />}

      <Pagination
        currentPage={page}
        totalPages={data?.totalPages ?? 1}
        onPageChange={setPage}
        disabled={isPreviousData}
      />
    </div>
  );
}
```

### Prefetching Next Page

```typescript
function usePaginatedTodosWithPrefetch(page: number, pageSize: number) {
  const queryClient = useQueryClient();

  const query = useQuery<PaginatedResult<Todo>, Error>(
    ['todos', 'list', { page, pageSize }],
    () => fetchTodoPage(page, pageSize),
    {
      keepPreviousData: true,
      staleTime: 30 * 1000,
      onSuccess: (data) => {
        // Prefetch the next page when current page loads
        if (page < data.totalPages) {
          queryClient.prefetchQuery(
            ['todos', 'list', { page: page + 1, pageSize }],
            () => fetchTodoPage(page + 1, pageSize)
          );
        }
      },
    }
  );

  return query;
}
```

## Infinite Scroll with useInfiniteQuery

### Cursor-Based Infinite Query

```typescript
import { useInfiniteQuery } from 'react-query';

interface CursorPage<T> {
  items: T[];
  nextCursor: string | null;
  previousCursor: string | null;
}

function useInfiniteMessages(channelId: string) {
  return useInfiniteQuery<CursorPage<Message>, Error>(
    ['messages', channelId],
    ({ pageParam }) =>
      api
        .get<CursorPage<Message>>(`/channels/${channelId}/messages`, {
          params: { cursor: pageParam, limit: 50 },
        })
        .then((r) => r.data),
    {
      getNextPageParam: (lastPage) => lastPage.nextCursor ?? undefined,
      getPreviousPageParam: (firstPage) => firstPage.previousCursor ?? undefined,
      staleTime: 60 * 1000,
      refetchOnWindowFocus: false,
    }
  );
}

function MessageFeed({ channelId }: { channelId: string }) {
  const {
    data,
    isLoading,
    isError,
    error,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
    fetchPreviousPage,
    hasPreviousPage,
    isFetchingPreviousPage,
  } = useInfiniteMessages(channelId);

  const observerRef = useRef<IntersectionObserver | null>(null);
  const loadMoreRef = useRef<HTMLDivElement | null>(null);

  // Intersection Observer for automatic loading
  useEffect(() => {
    if (observerRef.current) observerRef.current.disconnect();

    observerRef.current = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && hasNextPage && !isFetchingNextPage) {
          fetchNextPage();
        }
      },
      { threshold: 0.5 }
    );

    if (loadMoreRef.current) {
      observerRef.current.observe(loadMoreRef.current);
    }

    return () => observerRef.current?.disconnect();
  }, [hasNextPage, isFetchingNextPage, fetchNextPage]);

  if (isLoading) return <Spinner />;
  if (isError) return <ErrorDisplay error={error} />;

  const allMessages = data.pages.flatMap((page) => page.items);

  return (
    <div>
      {allMessages.map((message) => (
        <MessageBubble key={message.id} message={message} />
      ))}
      <div ref={loadMoreRef}>
        {isFetchingNextPage && <Spinner size="small" />}
      </div>
    </div>
  );
}
```

### Offset-Based Infinite Query

```typescript
function useInfinitePosts() {
  return useInfiniteQuery<PaginatedResult<Post>, Error>(
    ['posts', 'infinite'],
    ({ pageParam = 1 }) =>
      api.get<PaginatedResult<Post>>('/posts', {
        params: { page: pageParam, pageSize: 20 },
      }).then((r) => r.data),
    {
      getNextPageParam: (lastPage) => {
        if (lastPage.page < lastPage.totalPages) {
          return lastPage.page + 1;
        }
        return undefined; // No more pages
      },
    }
  );
}
```

## staleTime vs cacheTime

Understanding these two timers is critical for correct caching behavior.

### staleTime -- How Long Data is "Fresh"

- **Default**: `0` (data is stale immediately)
- While data is fresh, React Query serves cached data without triggering a background refetch.
- Once stale, data is still served from cache but a background refetch is triggered on certain events (window focus, mount, reconnect).

```typescript
// Data is fresh for 5 minutes. No refetch triggered during this period.
useQuery(['user', userId], fetchUser, {
  staleTime: 5 * 60 * 1000,
});

// Data is NEVER stale. Fetch only once (until cache is cleared or invalidated).
useQuery(['config'], fetchConfig, {
  staleTime: Infinity,
});
```

### cacheTime -- How Long Inactive Data is Kept

- **Default**: `5 * 60 * 1000` (5 minutes)
- Once no component is subscribed to a query (all instances unmount), the cache entry becomes "inactive."
- After `cacheTime` elapses, the inactive data is garbage-collected.
- **v3 uses `cacheTime`**. v5 renamed it to `gcTime`.

```typescript
// Cache inactive data for 30 minutes
useQuery(['large-dataset'], fetchDataset, {
  cacheTime: 30 * 60 * 1000,
});

// Never garbage-collect (keep in cache forever)
useQuery(['static-data'], fetchStaticData, {
  cacheTime: Infinity,
  staleTime: Infinity,
});
```

### Timeline Example

```
Component mounts -> fetchUser() called -> data arrives
  |--- staleTime (5 min) ---|
  While fresh: refetchOnWindowFocus, refetchOnMount do nothing.
  After stale: these triggers cause background refetch.

Component unmounts -> data becomes inactive
  |--- cacheTime (30 min) ---|
  Component remounts during this time -> cached data served instantly + background refetch.
  After cacheTime: data is garbage-collected. Next mount = loading state.
```

## Prefetching

Prefetch data before the user needs it, so it loads instantly from cache.

### prefetchQuery

```typescript
import { useQueryClient } from 'react-query';

function TodoList({ todos }: { todos: Todo[] }) {
  const queryClient = useQueryClient();

  const handleHover = (todoId: string) => {
    // Prefetch on hover so detail view loads instantly
    queryClient.prefetchQuery(
      ['todo', todoId],
      () => fetchTodo(todoId),
      {
        staleTime: 5 * 60 * 1000, // Only prefetch if data is older than 5 min
      }
    );
  };

  return (
    <ul>
      {todos.map((todo) => (
        <li key={todo.id} onMouseEnter={() => handleHover(todo.id)}>
          <Link to={`/todos/${todo.id}`}>{todo.title}</Link>
        </li>
      ))}
    </ul>
  );
}
```

### Prefetching on Route Change

```typescript
// With React Router
function AppRoutes() {
  const queryClient = useQueryClient();

  return (
    <Routes>
      <Route
        path="/dashboard"
        element={<Dashboard />}
        loader={() => {
          // Prefetch dashboard data before render
          queryClient.prefetchQuery(['dashboard', 'stats'], fetchDashboardStats);
          queryClient.prefetchQuery(['dashboard', 'activity'], fetchRecentActivity);
          return null;
        }}
      />
    </Routes>
  );
}
```

### Seeding Cache from List Data

```typescript
function useUserList() {
  const queryClient = useQueryClient();

  return useQuery<User[], Error>(
    ['users', 'list'],
    () => fetchUsers(),
    {
      onSuccess: (users) => {
        // Seed individual user caches from the list response
        users.forEach((user) => {
          queryClient.setQueryData(['user', user.id], user);
        });
      },
    }
  );
}
```

## Select Transform

The `select` option transforms query data without affecting what is stored in cache.

```typescript
interface ApiUser {
  id: string;
  first_name: string;
  last_name: string;
  email_address: string;
  created_at: string;
}

interface User {
  id: string;
  fullName: string;
  email: string;
  createdAt: Date;
}

function useUser(userId: string) {
  return useQuery<ApiUser, Error, User>(
    ['user', userId],
    () => fetchUser(userId),
    {
      select: (apiUser): User => ({
        id: apiUser.id,
        fullName: `${apiUser.first_name} ${apiUser.last_name}`,
        email: apiUser.email_address,
        createdAt: new Date(apiUser.created_at),
      }),
    }
  );
}

// Selecting a subset to reduce re-renders
function useUserName(userId: string) {
  return useQuery<ApiUser, Error, string>(
    ['user', userId],
    () => fetchUser(userId),
    {
      select: (user) => `${user.first_name} ${user.last_name}`,
    }
  );
}

// Using a stable selector reference for referential equality
const selectActiveUsers = (users: ApiUser[]) =>
  users.filter((u) => u.status === 'active');

function useActiveUsers() {
  return useQuery<ApiUser[], Error, ApiUser[]>(
    ['users'],
    fetchAllUsers,
    { select: selectActiveUsers }
  );
}
```

## Retry Configuration

```typescript
// Per-query retry
useQuery(['fragile-endpoint'], fetchFragileData, {
  retry: 5,
  retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 60000),
});

// Conditional retry based on error type
useQuery(['data'], fetchData, {
  retry: (failureCount, error: any) => {
    // Don't retry 4xx errors (client errors)
    if (error.status >= 400 && error.status < 500) return false;
    // Retry server errors up to 3 times
    return failureCount < 3;
  },
});

// No retry
useQuery(['quick-check'], checkSomething, { retry: false });
```

## Query Status States

React Query v3 has four status states and two fetching flags.

### Status Values

| Status | `isLoading` | `isFetching` | `isIdle` | `isSuccess` | `isError` | Description |
|---|---|---|---|---|---|---|
| `idle` | false | false | true | false | false | Query is disabled, has not started |
| `loading` | true | true | false | false | false | First load, no cached data |
| `error` | false | false | false | false | true | Query failed |
| `success` | false | false | false | true | false | Query has data |

### Key Distinctions in v3

```typescript
const { status, isLoading, isFetching, isIdle } = useQuery(
  ['data'],
  fetchData,
  { enabled: someCondition }
);

// isLoading: true ONLY on first load with no cached data
// v3 does NOT have `isPending`

// isFetching: true whenever a request is in flight, including background refetches
// Use isFetching for showing a subtle loading indicator during refetches

// isIdle: true when query is disabled and has never fetched
// v5 removed the 'idle' status entirely

// Typical rendering pattern
if (isIdle) return <div>Query is disabled</div>;
if (isLoading) return <Spinner />;
if (isError) return <ErrorMessage error={error} />;
// At this point, data is guaranteed to be defined
return <DataDisplay data={data} />;
```

### Background Refetch Indicator

```typescript
function DataView() {
  const { data, isLoading, isFetching } = useQuery(['data'], fetchData);

  return (
    <div>
      {isLoading ? (
        <FullPageSpinner />
      ) : (
        <>
          {isFetching && <TopBarProgressIndicator />}
          <DataTable data={data!} />
        </>
      )}
    </div>
  );
}
```

---

## Displaced Patterns from SKILL.md

### QueryClient Setup

```typescript
import { QueryClient, QueryClientProvider } from 'react-query';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 0,
      cacheTime: 5 * 60 * 1000,
      retry: 3,
      retryDelay: (attempt) => Math.min(1000 * 2 ** attempt, 30000),
      refetchOnWindowFocus: true,
      refetchOnReconnect: true,
      refetchOnMount: true,
      useErrorBoundary: false,
    },
    mutations: { retry: false },
  },
});

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <Router />
    </QueryClientProvider>
  );
}
```

### Pagination with keepPreviousData

```typescript
function usePaginatedTodos(page: number) {
  return useQuery<PaginatedResponse<Todo>, Error>(
    ['todos', 'list', { page }],
    () => fetchTodos({ page, limit: 20 }),
    { keepPreviousData: true, staleTime: 5 * 60 * 1000 }
  );
}

function TodoList() {
  const [page, setPage] = useState(1);
  const { data, isLoading, isPreviousData } = usePaginatedTodos(page);

  return (
    <div>
      <ul style={{ opacity: isPreviousData ? 0.5 : 1 }}>
        {data?.items.map(todo => <li key={todo.id}>{todo.title}</li>)}
      </ul>
      <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}>Previous</button>
      <button onClick={() => setPage(p => p + 1)} disabled={isPreviousData || page === data?.totalPages}>Next</button>
    </div>
  );
}
```

### useInfiniteQuery

```typescript
import { useInfiniteQuery } from 'react-query';

function useInfiniteTodos() {
  return useInfiniteQuery<CursorPaginatedResponse<Todo>, Error>(
    ['todos', 'infinite'],
    ({ pageParam = undefined }) => fetchTodos({ cursor: pageParam, limit: 20 }),
    { getNextPageParam: (lastPage) => lastPage.nextCursor ?? undefined }
  );
}

// Usage: data.pages.map(page => page.items.map(todo => ...))
// fetchNextPage(), hasNextPage, isFetchingNextPage
```

### Error Handling Patterns

```typescript
// Per-query
useQuery(['user', userId], fetchUser, {
  onError: (error) => reportToSentry(error),
  retry: (count, error) => error.status !== 404 && count < 3,
  useErrorBoundary: (error) => error.status >= 500,
});

// Global
const queryClient = new QueryClient({
  defaultOptions: {
    queries: { onError: (err) => toast.error(err.message) },
    mutations: { onError: (err) => toast.error(err.message) },
  },
});
```

### All useQuery Return Values

```typescript
result.isLoading;     // first load, no cached data
result.isFetching;    // any fetch in progress
result.isError;       // error state
result.isSuccess;     // has data
result.isIdle;        // disabled, not started
result.data;          // TData | undefined
result.error;         // TError | null
result.status;        // 'idle' | 'loading' | 'error' | 'success'
result.refetch();     // manual refetch
result.isPreviousData; // showing stale data with keepPreviousData
```
