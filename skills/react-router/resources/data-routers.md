# Data Routers (React Router v6.4+)

## Overview

The data router API (`createBrowserRouter`) unlocks powerful data loading and mutation primitives that are colocated with your route definitions. This enables loaders for fetching data before a route renders, actions for handling form submissions, and error elements for granular error handling.

---

## createBrowserRouter Full Setup

```typescript
import {
  createBrowserRouter,
  RouterProvider,
  Outlet,
  Link,
} from 'react-router-dom';

// Layout
function RootLayout() {
  return (
    <div>
      <header>
        <nav>
          <Link to="/">Home</Link>
          <Link to="/users">Users</Link>
          <Link to="/settings">Settings</Link>
        </nav>
      </header>
      <main>
        <Outlet />
      </main>
    </div>
  );
}

// Router definition
const router = createBrowserRouter([
  {
    path: '/',
    element: <RootLayout />,
    errorElement: <RootErrorBoundary />,
    children: [
      {
        index: true,
        element: <Home />,
      },
      {
        path: 'users',
        element: <UsersLayout />,
        children: [
          {
            index: true,
            element: <UsersList />,
            loader: usersListLoader,
          },
          {
            path: ':userId',
            element: <UserDetail />,
            loader: userDetailLoader,
            action: userDetailAction,
            errorElement: <UserErrorBoundary />,
          },
          {
            path: 'new',
            element: <CreateUser />,
            action: createUserAction,
          },
        ],
      },
      {
        path: 'settings',
        lazy: async () => {
          const { Settings, settingsLoader } = await import('./pages/Settings');
          return { element: <Settings />, loader: settingsLoader };
        },
      },
    ],
  },
  {
    path: '/login',
    element: <Login />,
    action: loginAction,
  },
]);

// App entry
function App() {
  return <RouterProvider router={router} />;
}
```

---

## Loader Functions

Loaders run before a route component renders. They receive the route params and the request object.

### Basic Loader

```typescript
import type { LoaderFunctionArgs } from 'react-router-dom';

interface User {
  id: string;
  name: string;
  email: string;
  role: 'admin' | 'user';
}

export async function usersListLoader(): Promise<User[]> {
  const response = await fetch('/api/users');
  if (!response.ok) {
    throw new Response('Failed to load users', { status: response.status });
  }
  return response.json();
}
```

### Loader with Params

```typescript
export async function userDetailLoader({
  params,
}: LoaderFunctionArgs): Promise<User> {
  const { userId } = params;
  if (!userId) {
    throw new Response('User ID is required', { status: 400 });
  }

  const response = await fetch(`/api/users/${userId}`);
  if (!response.ok) {
    throw new Response('User not found', { status: 404 });
  }
  return response.json();
}
```

### Loader with Request (Search Params)

```typescript
export async function searchLoader({
  request,
}: LoaderFunctionArgs): Promise<SearchResults> {
  const url = new URL(request.url);
  const query = url.searchParams.get('q') ?? '';
  const page = Number(url.searchParams.get('page')) || 1;
  const limit = Number(url.searchParams.get('limit')) || 20;

  const response = await fetch(
    `/api/search?q=${encodeURIComponent(query)}&page=${page}&limit=${limit}`
  );
  if (!response.ok) {
    throw new Response('Search failed', { status: response.status });
  }
  return response.json();
}
```

### Loader with Authentication Check

```typescript
import { redirect } from 'react-router-dom';

export async function protectedLoader({ request }: LoaderFunctionArgs) {
  const token = getAuthToken();
  if (!token) {
    const url = new URL(request.url);
    return redirect(`/login?redirectTo=${url.pathname}`);
  }

  const response = await fetch('/api/dashboard', {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (response.status === 401) {
    clearAuthToken();
    return redirect('/login');
  }

  if (!response.ok) {
    throw new Response('Failed to load dashboard', {
      status: response.status,
    });
  }

  return response.json();
}
```

---

## useLoaderData

Access data returned by the route's loader function.

```typescript
import { useLoaderData } from 'react-router-dom';

interface UserListData {
  users: User[];
  totalCount: number;
  page: number;
}

function UsersList() {
  const { users, totalCount, page } = useLoaderData() as UserListData;

  return (
    <div>
      <h1>Users ({totalCount})</h1>
      <ul>
        {users.map((user) => (
          <li key={user.id}>
            <Link to={user.id}>{user.name}</Link>
          </li>
        ))}
      </ul>
      <Pagination page={page} total={totalCount} />
    </div>
  );
}
```

### useRouteLoaderData

Access loader data from a parent route by its route ID.

```typescript
const router = createBrowserRouter([
  {
    id: 'root',
    path: '/',
    element: <RootLayout />,
    loader: rootLoader,
    children: [
      {
        path: 'dashboard',
        element: <Dashboard />,
      },
    ],
  },
]);

// In Dashboard component, access root loader data
import { useRouteLoaderData } from 'react-router-dom';

function Dashboard() {
  const rootData = useRouteLoaderData('root') as RootLoaderData;
  return <div>Welcome, {rootData.user.name}</div>;
}
```

---

## Action Functions

Actions handle non-GET form submissions (POST, PUT, DELETE, PATCH).

### Basic Action

```typescript
import type { ActionFunctionArgs } from 'react-router-dom';
import { redirect } from 'react-router-dom';

export async function createUserAction({
  request,
}: ActionFunctionArgs): Promise<Response | ActionErrors> {
  const formData = await request.formData();
  const name = formData.get('name') as string;
  const email = formData.get('email') as string;

  // Validate
  const errors: Record<string, string> = {};
  if (!name || name.length < 2) {
    errors.name = 'Name must be at least 2 characters';
  }
  if (!email || !email.includes('@')) {
    errors.email = 'Valid email is required';
  }

  if (Object.keys(errors).length > 0) {
    return errors;
  }

  // Submit
  const response = await fetch('/api/users', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, email }),
  });

  if (!response.ok) {
    throw new Response('Failed to create user', { status: response.status });
  }

  const user = await response.json();
  return redirect(`/users/${user.id}`);
}
```

### Delete Action

```typescript
export async function deleteUserAction({
  params,
  request,
}: ActionFunctionArgs) {
  if (request.method !== 'DELETE') {
    throw new Response('Method not allowed', { status: 405 });
  }

  const response = await fetch(`/api/users/${params.userId}`, {
    method: 'DELETE',
  });

  if (!response.ok) {
    throw new Response('Failed to delete user', { status: response.status });
  }

  return redirect('/users');
}
```

### Update Action

```typescript
export async function updateUserAction({
  params,
  request,
}: ActionFunctionArgs) {
  const formData = await request.formData();
  const updates = Object.fromEntries(formData);

  const response = await fetch(`/api/users/${params.userId}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(updates),
  });

  if (!response.ok) {
    throw new Response('Failed to update user', { status: response.status });
  }

  return response.json();
}
```

---

## useActionData

Access data returned by the route's action function (typically validation errors).

```typescript
import { Form, useActionData, useNavigation } from 'react-router-dom';

interface FormErrors {
  name?: string;
  email?: string;
}

function CreateUser() {
  const errors = useActionData() as FormErrors | undefined;
  const navigation = useNavigation();
  const isSubmitting = navigation.state === 'submitting';

  return (
    <Form method="post">
      <div>
        <label htmlFor="name">Name</label>
        <input id="name" name="name" required />
        {errors?.name && <p className="error">{errors.name}</p>}
      </div>

      <div>
        <label htmlFor="email">Email</label>
        <input id="email" name="email" type="email" required />
        {errors?.email && <p className="error">{errors.email}</p>}
      </div>

      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Creating...' : 'Create User'}
      </button>
    </Form>
  );
}
```

---

## Form Component

The `Form` component from React Router submits data to route actions instead of making browser requests.

```typescript
import { Form } from 'react-router-dom';

// POST form (creates)
<Form method="post">
  <input name="title" />
  <button type="submit">Create</button>
</Form>

// DELETE form (deletes)
<Form method="delete" action={`/users/${userId}`}>
  <button type="submit">Delete User</button>
</Form>

// GET form (search - triggers loader, not action)
<Form method="get" action="/search">
  <input name="q" />
  <button type="submit">Search</button>
</Form>
```

---

## useFetcher

`useFetcher` lets you interact with loaders and actions without triggering navigation. Ideal for inline edits, toggles, and background submissions.

### Inline Update

```typescript
import { useFetcher } from 'react-router-dom';

function TodoItem({ todo }: { todo: Todo }) {
  const fetcher = useFetcher();

  // Optimistic UI: use fetcher data if available
  const isComplete =
    fetcher.formData
      ? fetcher.formData.get('completed') === 'true'
      : todo.completed;

  return (
    <fetcher.Form method="post" action={`/todos/${todo.id}`}>
      <input
        type="hidden"
        name="completed"
        value={String(!isComplete)}
      />
      <button type="submit">
        {isComplete ? 'Mark Incomplete' : 'Mark Complete'}
      </button>
      <span>{todo.title}</span>
    </fetcher.Form>
  );
}
```

### Loading Data Without Navigation

```typescript
import { useFetcher } from 'react-router-dom';
import { useEffect } from 'react';

function UserAutocomplete() {
  const fetcher = useFetcher<User[]>();

  function handleInputChange(event: React.ChangeEvent<HTMLInputElement>) {
    fetcher.load(`/api/users/search?q=${event.target.value}`);
  }

  return (
    <div>
      <input onChange={handleInputChange} placeholder="Search users..." />
      {fetcher.state === 'loading' && <span>Loading...</span>}
      {fetcher.data && (
        <ul>
          {fetcher.data.map((user) => (
            <li key={user.id}>{user.name}</li>
          ))}
        </ul>
      )}
    </div>
  );
}
```

---

## Error Element

Route-level error boundaries catch errors thrown in loaders, actions, or during rendering.

### Global Error Boundary

```typescript
import { useRouteError, isRouteErrorResponse, Link } from 'react-router-dom';

function RootErrorBoundary() {
  const error = useRouteError();

  if (isRouteErrorResponse(error)) {
    if (error.status === 404) {
      return (
        <div>
          <h1>Page Not Found</h1>
          <p>The page you are looking for does not exist.</p>
          <Link to="/">Go Home</Link>
        </div>
      );
    }

    if (error.status === 401) {
      return (
        <div>
          <h1>Unauthorized</h1>
          <p>You must be logged in to view this page.</p>
          <Link to="/login">Log In</Link>
        </div>
      );
    }

    return (
      <div>
        <h1>{error.status} Error</h1>
        <p>{error.statusText}</p>
      </div>
    );
  }

  return (
    <div>
      <h1>Something went wrong</h1>
      <p>{error instanceof Error ? error.message : 'An unexpected error occurred'}</p>
      <Link to="/">Go Home</Link>
    </div>
  );
}
```

### Route-Specific Error Boundary

```typescript
const router = createBrowserRouter([
  {
    path: '/',
    element: <RootLayout />,
    errorElement: <RootErrorBoundary />,
    children: [
      {
        path: 'users/:userId',
        element: <UserDetail />,
        loader: userDetailLoader,
        // This error boundary only handles errors in this route
        errorElement: <UserNotFound />,
      },
    ],
  },
]);

function UserNotFound() {
  const error = useRouteError();

  return (
    <div>
      <h2>User Not Found</h2>
      <p>We could not find the user you are looking for.</p>
      <Link to="/users">Back to Users</Link>
    </div>
  );
}
```

---

## defer + Suspense (Streaming Data)

`defer` allows you to return promises from loaders that resolve after the route renders, showing fallback UI while data loads.

### Deferred Loader

```typescript
import { defer } from 'react-router-dom';
import type { LoaderFunctionArgs } from 'react-router-dom';

interface UserPageData {
  user: User;
  posts: Promise<Post[]>;
  comments: Promise<Comment[]>;
}

export async function userPageLoader({
  params,
}: LoaderFunctionArgs) {
  // Critical data: awaited before render
  const userResponse = await fetch(`/api/users/${params.userId}`);
  if (!userResponse.ok) {
    throw new Response('User not found', { status: 404 });
  }
  const user = await userResponse.json();

  // Non-critical data: streamed in after render
  const postsPromise = fetch(`/api/users/${params.userId}/posts`).then(
    (r) => r.json()
  );
  const commentsPromise = fetch(`/api/users/${params.userId}/comments`).then(
    (r) => r.json()
  );

  return defer({
    user,
    posts: postsPromise,
    comments: commentsPromise,
  });
}
```

### Consuming Deferred Data with Await

```typescript
import { useLoaderData, Await } from 'react-router-dom';
import { Suspense } from 'react';

function UserPage() {
  const { user, posts, comments } = useLoaderData() as {
    user: User;
    posts: Promise<Post[]>;
    comments: Promise<Comment[]>;
  };

  return (
    <div>
      {/* Critical data renders immediately */}
      <h1>{user.name}</h1>
      <p>{user.email}</p>

      {/* Non-critical data streams in */}
      <section>
        <h2>Posts</h2>
        <Suspense fallback={<PostsSkeleton />}>
          <Await resolve={posts} errorElement={<p>Failed to load posts</p>}>
            {(resolvedPosts: Post[]) => (
              <ul>
                {resolvedPosts.map((post) => (
                  <li key={post.id}>{post.title}</li>
                ))}
              </ul>
            )}
          </Await>
        </Suspense>
      </section>

      <section>
        <h2>Comments</h2>
        <Suspense fallback={<CommentsSkeleton />}>
          <Await
            resolve={comments}
            errorElement={<p>Failed to load comments</p>}
          >
            {(resolvedComments: Comment[]) => (
              <ul>
                {resolvedComments.map((comment) => (
                  <li key={comment.id}>{comment.body}</li>
                ))}
              </ul>
            )}
          </Await>
        </Suspense>
      </section>
    </div>
  );
}
```

---

## useNavigation (Global Loading State)

Track the state of route transitions for showing loading indicators.

```typescript
import { useNavigation, Outlet } from 'react-router-dom';

function RootLayout() {
  const navigation = useNavigation();

  const isLoading = navigation.state === 'loading';
  const isSubmitting = navigation.state === 'submitting';

  return (
    <div>
      {isLoading && <LoadingBar />}
      <div style={{ opacity: isLoading ? 0.5 : 1 }}>
        <Outlet />
      </div>
      {isSubmitting && <SubmittingOverlay />}
    </div>
  );
}
```

---

## useRevalidator

Manually trigger revalidation of all route loaders.

```typescript
import { useRevalidator } from 'react-router-dom';

function RefreshButton() {
  const revalidator = useRevalidator();

  return (
    <button
      onClick={() => revalidator.revalidate()}
      disabled={revalidator.state === 'loading'}
    >
      {revalidator.state === 'loading' ? 'Refreshing...' : 'Refresh Data'}
    </button>
  );
}
```

---

---

## Displaced Patterns from SKILL.md

### BrowserRouter (Legacy) Setup

```typescript
import { BrowserRouter, Routes, Route } from 'react-router-dom';

<BrowserRouter>
  <Routes>
    <Route path="/" element={<App />}>
      <Route index element={<Home />} />
      <Route path="about" element={<About />} />
      <Route path="*" element={<NotFound />} />
    </Route>
  </Routes>
</BrowserRouter>
```

### Layout with Outlet

```typescript
import { Outlet, Link } from 'react-router-dom';

function DashboardLayout() {
  return (
    <div>
      <nav>
        <Link to="/dashboard">Overview</Link>
        <Link to="/dashboard/analytics">Analytics</Link>
      </nav>
      <main><Outlet /></main>
    </div>
  );
}
```

### Outlet Context (Typed)

```typescript
import { Outlet, useOutletContext } from 'react-router-dom';

interface DashboardContext { user: User; permissions: string[] }

function DashboardLayout() {
  return <Outlet context={{ user, permissions } satisfies DashboardContext} />;
}

function Analytics() {
  const { user } = useOutletContext<DashboardContext>();
}
```

### Error Element

```typescript
import { useRouteError, isRouteErrorResponse } from 'react-router-dom';

function ErrorBoundary() {
  const error = useRouteError();
  if (isRouteErrorResponse(error)) {
    return <div><h1>{error.status}</h1><p>{error.statusText}</p></div>;
  }
  return <div><h1>Error</h1><p>{error instanceof Error ? error.message : 'Unknown'}</p></div>;
}
```

### Action with Validation

```typescript
async function createUserAction({ request }: ActionFunctionArgs): Promise<ActionErrors | Response> {
  const formData = await request.formData();
  const name = formData.get('name') as string;
  const email = formData.get('email') as string;
  const errors: ActionErrors = {};
  if (!name) errors.name = 'Required';
  if (!email) errors.email = 'Required';
  if (Object.keys(errors).length > 0) return errors;
  await fetch('/api/users', { method: 'POST', body: JSON.stringify({ name, email }) });
  return redirect('/users');
}

function CreateUser() {
  const errors = useActionData() as ActionErrors | undefined;
  return (
    <Form method="post">
      <input name="name" />{errors?.name && <span>{errors.name}</span>}
      <input name="email" />{errors?.email && <span>{errors.email}</span>}
      <button type="submit">Create</button>
    </Form>
  );
}
```

### Navigate with State

```typescript
navigate('/checkout', { state: { from: '/cart', itemCount: 3 } });

// Receiving
const location = useLocation();
const { from, itemCount } = location.state ?? {};
```

### Track Location Changes

```typescript
function AnalyticsTracker() {
  const location = useLocation();
  useEffect(() => {
    trackPageView(location.pathname + location.search);
  }, [location]);
  return null;
}
```

### Loading Indicator

```typescript
import { useNavigation } from 'react-router-dom';

function RootLayout() {
  const navigation = useNavigation();
  return (
    <div>
      {navigation.state === 'loading' && <LoadingBar />}
      <Outlet />
    </div>
  );
}
```
