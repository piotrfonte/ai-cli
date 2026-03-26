---
name: react-router
description: React Router v6 patterns for routing including createBrowserRouter, nested routes, navigation hooks, loaders/actions, and protected routes.
user-invocable: true
---

# React Router v6 Patterns

Covers react-router-dom ^6.2 through 6.26.

## Quick Start — createBrowserRouter

```typescript
import { createBrowserRouter, RouterProvider } from 'react-router-dom';

const router = createBrowserRouter([
  {
    path: '/',
    element: <RootLayout />,
    errorElement: <ErrorBoundary />,
    children: [
      { index: true, element: <Home /> },
      { path: 'users', element: <Users />, loader: usersLoader },
      { path: 'users/:userId', element: <UserDetail />, loader: userDetailLoader },
    ],
  },
]);

function App() {
  return <RouterProvider router={router} />;
}
```

## Route Definition Rules

- DO prefer `createBrowserRouter` (data router, v6.4+) for new projects — enables loaders, actions, error boundaries
- DO use nested routes with `<Outlet />` for shared layouts
- DO add `errorElement` to routes for error handling
- DO add `path="*"` catch-all for 404
- DO use `index: true` for default child routes

## Hooks

### useNavigate

```typescript
const navigate = useNavigate();
navigate('/dashboard', { replace: true }); // redirect
navigate(-1);                               // go back
navigate('/checkout', { state: { from: '/cart' } }); // with state
```

### useParams (typed)

```typescript
const { userId } = useParams<{ userId: string }>();
if (!userId) throw new Response('Not Found', { status: 404 });
```

### useSearchParams

```typescript
const [searchParams, setSearchParams] = useSearchParams();
const page = Number(searchParams.get('page')) || 1;
setSearchParams(prev => { prev.set('page', '2'); return prev; });
```

### useLocation

```typescript
const location = useLocation();
// location.pathname, location.search, location.state
```

## Loaders & Actions (v6.4+)

```typescript
// Loader
async function userLoader({ params }: LoaderFunctionArgs): Promise<User> {
  const res = await fetch(`/api/users/${params.userId}`);
  if (!res.ok) throw new Response('Not found', { status: 404 });
  return res.json();
}

// In component
const user = useLoaderData() as User;

// Action
async function createAction({ request }: ActionFunctionArgs) {
  const formData = await request.formData();
  await api.create(Object.fromEntries(formData));
  return redirect('/list');
}
```

- DO colocate loaders with route components: export both from same file
- DO use `<Form method="post">` with data router actions

## Protected Routes

```typescript
function ProtectedRoute({ isAuthenticated }: { isAuthenticated: boolean }) {
  const location = useLocation();
  if (!isAuthenticated) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }
  return <Outlet />;
}

// Usage
<Route element={<ProtectedRoute isAuthenticated={isAuth} />}>
  <Route path="dashboard" element={<Dashboard />} />
</Route>
```

### Redirect After Login

```typescript
const from = (location.state as { from?: Location })?.from?.pathname ?? '/';
navigate(from, { replace: true });
```

## Lazy Routes

```typescript
// React.lazy
const Dashboard = lazy(() => import('./pages/Dashboard'));
<Suspense fallback={<Spinner />}><Routes>...</Routes></Suspense>

// Data router lazy (v6.4+)
{ path: 'dashboard', lazy: async () => {
  const { Dashboard, loader } = await import('./pages/Dashboard');
  return { element: <Dashboard />, loader };
}}
```

## NavLink

```typescript
<NavLink to="/dashboard" className={({ isActive }) => isActive ? 'active' : ''}>
  Dashboard
</NavLink>
```

## Best Practices

- DO use relative paths in nested routes: `to="settings"` not `to="/dashboard/settings"`
- DO type `useParams` generics and guard against undefined
- DO use `useNavigation().state` to show loading indicators
- DO use `<Navigate to="/new" replace />` for declarative redirects

## References

- `resources/data-routers.md` — full data router API, loaders, actions, streaming
- `resources/navigation-patterns.md` — programmatic nav, code splitting, scroll restoration
