# Navigation Patterns

## Overview

Comprehensive patterns for programmatic navigation, protected routes, active link styling, code splitting, scroll restoration, and search parameter management in React Router v6.

---

## Programmatic Navigation with useNavigate

### Basic Navigation

```typescript
import { useNavigate } from 'react-router-dom';

function Dashboard() {
  const navigate = useNavigate();

  function handleViewUser(userId: string) {
    navigate(`/users/${userId}`);
  }

  function handleGoBack() {
    navigate(-1);
  }

  function handleGoForward() {
    navigate(1);
  }

  return (
    <div>
      <button onClick={() => handleViewUser('123')}>View User</button>
      <button onClick={handleGoBack}>Back</button>
      <button onClick={handleGoForward}>Forward</button>
    </div>
  );
}
```

### Replace History Entry

Use `replace: true` when the user should not be able to go back to the current page (e.g., after login or after deleting a resource).

```typescript
function LoginPage() {
  const navigate = useNavigate();

  async function handleLogin(credentials: Credentials) {
    const result = await authenticateUser(credentials);
    if (result.success) {
      // Replace /login in history so Back button skips it
      navigate('/dashboard', { replace: true });
    }
  }

  return <LoginForm onSubmit={handleLogin} />;
}
```

### Navigate with State

Pass arbitrary data through navigation that is available at the destination via `useLocation().state`.

```typescript
import { useNavigate, useLocation } from 'react-router-dom';

// Sender
function ProductCard({ product }: { product: Product }) {
  const navigate = useNavigate();

  function handleClick() {
    navigate(`/products/${product.id}`, {
      state: {
        fromList: true,
        scrollPosition: window.scrollY,
        filterState: currentFilters,
      },
    });
  }

  return <div onClick={handleClick}>{product.name}</div>;
}

// Receiver
function ProductDetail() {
  const location = useLocation();
  const state = location.state as {
    fromList?: boolean;
    scrollPosition?: number;
    filterState?: FilterState;
  } | null;

  function handleBack() {
    // Custom back logic using state
    if (state?.fromList) {
      navigate('/products', {
        state: { restoreScroll: state.scrollPosition },
      });
    } else {
      navigate(-1);
    }
  }

  return (
    <div>
      {state?.fromList && (
        <button onClick={handleBack}>Back to List</button>
      )}
    </div>
  );
}
```

### Navigate After Async Operation

```typescript
function CreateItemForm() {
  const navigate = useNavigate();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setIsSubmitting(true);
    setError(null);

    try {
      const formData = new FormData(event.currentTarget);
      const item = await createItem(Object.fromEntries(formData));
      navigate(`/items/${item.id}`, { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create item');
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit}>
      <input name="title" required />
      {error && <p className="error">{error}</p>}
      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Creating...' : 'Create'}
      </button>
    </form>
  );
}
```

### Conditional Navigation

```typescript
function Checkout() {
  const navigate = useNavigate();
  const { cart } = useCart();

  useEffect(() => {
    if (cart.items.length === 0) {
      navigate('/shop', { replace: true });
    }
  }, [cart.items.length, navigate]);

  if (cart.items.length === 0) return null;

  return <CheckoutForm cart={cart} />;
}
```

---

## Protected / Auth Routes with Redirect

### Basic Protected Route

```typescript
import { Navigate, Outlet, useLocation } from 'react-router-dom';

interface ProtectedRouteProps {
  isAuthenticated: boolean;
  redirectTo?: string;
}

function ProtectedRoute({
  isAuthenticated,
  redirectTo = '/login',
}: ProtectedRouteProps) {
  const location = useLocation();

  if (!isAuthenticated) {
    // Save the attempted URL for redirect after login
    return <Navigate to={redirectTo} state={{ from: location }} replace />;
  }

  return <Outlet />;
}

// Usage
<Routes>
  <Route path="/login" element={<Login />} />
  <Route element={<ProtectedRoute isAuthenticated={isLoggedIn} />}>
    <Route path="/dashboard" element={<Dashboard />} />
    <Route path="/settings" element={<Settings />} />
  </Route>
</Routes>
```

### Role-Based Access Control

```typescript
import { Navigate, Outlet, useLocation } from 'react-router-dom';

interface RoleGuardProps {
  allowedRoles: string[];
  userRole: string | null;
  isAuthenticated: boolean;
}

function RoleGuard({ allowedRoles, userRole, isAuthenticated }: RoleGuardProps) {
  const location = useLocation();

  if (!isAuthenticated) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  if (!userRole || !allowedRoles.includes(userRole)) {
    return <Navigate to="/unauthorized" replace />;
  }

  return <Outlet />;
}

// Usage
<Routes>
  <Route element={<RoleGuard allowedRoles={['admin']} userRole={user.role} isAuthenticated={!!user} />}>
    <Route path="/admin" element={<AdminPanel />} />
    <Route path="/admin/users" element={<ManageUsers />} />
  </Route>
  <Route element={<RoleGuard allowedRoles={['admin', 'editor']} userRole={user.role} isAuthenticated={!!user} />}>
    <Route path="/editor" element={<ContentEditor />} />
  </Route>
</Routes>
```

### Redirect After Login

```typescript
import { useNavigate, useLocation } from 'react-router-dom';

function LoginPage() {
  const navigate = useNavigate();
  const location = useLocation();

  // Get the page the user was trying to visit
  const from = (location.state as { from?: Location })?.from?.pathname ?? '/';

  async function handleLogin(credentials: Credentials) {
    try {
      await authenticateUser(credentials);
      // Send them back to the page they were trying to visit
      navigate(from, { replace: true });
    } catch (error) {
      setLoginError('Invalid credentials');
    }
  }

  return (
    <div>
      {from !== '/' && <p>You must log in to view {from}</p>}
      <LoginForm onSubmit={handleLogin} />
    </div>
  );
}
```

### Protected Route with Data Router Loader

```typescript
import { redirect } from 'react-router-dom';
import type { LoaderFunctionArgs } from 'react-router-dom';

function requireAuth(request: Request): string {
  const token = getAuthToken();
  if (!token) {
    const url = new URL(request.url);
    throw redirect(`/login?redirectTo=${encodeURIComponent(url.pathname)}`);
  }
  return token;
}

// Use in any loader that requires authentication
export async function dashboardLoader({ request }: LoaderFunctionArgs) {
  const token = requireAuth(request);

  const response = await fetch('/api/dashboard', {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (response.status === 401) {
    clearAuthToken();
    throw redirect('/login');
  }

  return response.json();
}

// Login page reads the redirect target from the URL
function LoginPage() {
  const [searchParams] = useSearchParams();
  const redirectTo = searchParams.get('redirectTo') ?? '/';
  const navigate = useNavigate();

  async function handleLogin(credentials: Credentials) {
    await authenticateUser(credentials);
    navigate(redirectTo, { replace: true });
  }

  return <LoginForm onSubmit={handleLogin} />;
}
```

---

## NavLink Active Styling

### Class-Based Styling

```typescript
import { NavLink } from 'react-router-dom';

function Navigation() {
  return (
    <nav>
      <NavLink
        to="/"
        className={({ isActive, isPending }) =>
          [
            'nav-link',
            isActive ? 'nav-link--active' : '',
            isPending ? 'nav-link--pending' : '',
          ]
            .filter(Boolean)
            .join(' ')
        }
        end // Only match exact path for home
      >
        Home
      </NavLink>

      <NavLink
        to="/dashboard"
        className={({ isActive }) =>
          isActive ? 'nav-link nav-link--active' : 'nav-link'
        }
      >
        Dashboard
      </NavLink>

      <NavLink
        to="/settings"
        className={({ isActive }) =>
          isActive ? 'nav-link nav-link--active' : 'nav-link'
        }
      >
        Settings
      </NavLink>
    </nav>
  );
}
```

### Inline Style-Based

```typescript
import { NavLink } from 'react-router-dom';

const activeStyle: React.CSSProperties = {
  fontWeight: 700,
  color: '#1976d2',
  borderBottom: '2px solid #1976d2',
};

const defaultStyle: React.CSSProperties = {
  fontWeight: 400,
  color: '#666',
  borderBottom: '2px solid transparent',
};

function Navigation() {
  return (
    <nav>
      <NavLink
        to="/dashboard"
        style={({ isActive }) => (isActive ? activeStyle : defaultStyle)}
      >
        Dashboard
      </NavLink>
    </nav>
  );
}
```

### NavLink with Children Render Prop

```typescript
import { NavLink } from 'react-router-dom';

function Sidebar() {
  return (
    <nav>
      <NavLink to="/dashboard">
        {({ isActive, isPending }) => (
          <div className={`sidebar-item ${isActive ? 'active' : ''}`}>
            <DashboardIcon color={isActive ? 'primary' : 'inherit'} />
            <span>{isPending ? 'Loading...' : 'Dashboard'}</span>
          </div>
        )}
      </NavLink>
    </nav>
  );
}
```

### Reusable NavLink Component

```typescript
import { NavLink, type NavLinkProps } from 'react-router-dom';

interface AppNavLinkProps extends Omit<NavLinkProps, 'className'> {
  icon?: React.ReactNode;
  label: string;
}

function AppNavLink({ icon, label, ...props }: AppNavLinkProps) {
  return (
    <NavLink
      className={({ isActive }) =>
        `app-nav-link ${isActive ? 'app-nav-link--active' : ''}`
      }
      {...props}
    >
      {icon && <span className="app-nav-link__icon">{icon}</span>}
      <span className="app-nav-link__label">{label}</span>
    </NavLink>
  );
}

// Usage
<AppNavLink to="/dashboard" icon={<DashboardIcon />} label="Dashboard" />
<AppNavLink to="/settings" icon={<SettingsIcon />} label="Settings" />
```

---

## Code Splitting with React.lazy

### Basic Lazy Loading

```typescript
import { lazy, Suspense } from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';

// Each import creates a separate bundle chunk
const Home = lazy(() => import('./pages/Home'));
const Dashboard = lazy(() => import('./pages/Dashboard'));
const Settings = lazy(() => import('./pages/Settings'));
const UserProfile = lazy(() => import('./pages/UserProfile'));

function LoadingFallback() {
  return <div className="loading-spinner">Loading...</div>;
}

function App() {
  return (
    <BrowserRouter>
      <Suspense fallback={<LoadingFallback />}>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/settings" element={<Settings />} />
          <Route path="/users/:userId" element={<UserProfile />} />
        </Routes>
      </Suspense>
    </BrowserRouter>
  );
}
```

### Named Exports with React.lazy

```typescript
// React.lazy requires default exports. For named exports, re-export:
const Dashboard = lazy(() =>
  import('./pages/Dashboard').then((module) => ({
    default: module.Dashboard,
  }))
);
```

### Route-Level Lazy with Data Router (v6.4+)

The `lazy` property on route objects is the preferred approach with data routers. It loads the component, loader, and action together.

```typescript
const router = createBrowserRouter([
  {
    path: '/',
    element: <RootLayout />,
    children: [
      {
        index: true,
        element: <Home />,
      },
      {
        path: 'dashboard',
        lazy: async () => {
          const module = await import('./pages/Dashboard');
          return {
            element: <module.Dashboard />,
            loader: module.dashboardLoader,
            errorElement: <module.DashboardError />,
          };
        },
      },
      {
        path: 'users/:userId',
        lazy: async () => {
          const module = await import('./pages/UserDetail');
          return {
            element: <module.UserDetail />,
            loader: module.userDetailLoader,
            action: module.userDetailAction,
          };
        },
      },
    ],
  },
]);
```

### Preloading Routes on Hover

```typescript
import { Link } from 'react-router-dom';

// Preload function for a lazy module
const preloadDashboard = () => import('./pages/Dashboard');

function Navigation() {
  return (
    <nav>
      <Link to="/">Home</Link>
      <Link
        to="/dashboard"
        onMouseEnter={preloadDashboard}
        onFocus={preloadDashboard}
      >
        Dashboard
      </Link>
    </nav>
  );
}
```

---

## Scroll Restoration

### ScrollRestoration Component (Data Router)

```typescript
import {
  createBrowserRouter,
  RouterProvider,
  ScrollRestoration,
  Outlet,
} from 'react-router-dom';

function RootLayout() {
  return (
    <div>
      <Outlet />
      <ScrollRestoration />
    </div>
  );
}

const router = createBrowserRouter([
  {
    path: '/',
    element: <RootLayout />,
    children: [
      // routes...
    ],
  },
]);
```

### Custom Scroll Restoration Key

```typescript
<ScrollRestoration
  getKey={(location, matches) => {
    // Restore scroll by pathname (default behavior)
    return location.pathname;

    // Or use location key for unique scroll per navigation
    // return location.key;
  }}
/>
```

### Manual Scroll-to-Top (BrowserRouter)

```typescript
import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';

function ScrollToTop() {
  const { pathname } = useLocation();

  useEffect(() => {
    window.scrollTo(0, 0);
  }, [pathname]);

  return null;
}

// Place inside BrowserRouter
<BrowserRouter>
  <ScrollToTop />
  <Routes>
    {/* routes */}
  </Routes>
</BrowserRouter>
```

### Scroll to Hash

```typescript
import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';

function ScrollToHash() {
  const { hash } = useLocation();

  useEffect(() => {
    if (hash) {
      const element = document.querySelector(hash);
      if (element) {
        element.scrollIntoView({ behavior: 'smooth' });
      }
    } else {
      window.scrollTo(0, 0);
    }
  }, [hash]);

  return null;
}
```

---

## Search Params Management

### Basic Search Params

```typescript
import { useSearchParams } from 'react-router-dom';

function SearchPage() {
  const [searchParams, setSearchParams] = useSearchParams();

  const query = searchParams.get('q') ?? '';
  const page = Number(searchParams.get('page')) || 1;
  const sortBy = searchParams.get('sort') ?? 'relevance';
  const category = searchParams.get('category');

  function updateSearch(newQuery: string) {
    setSearchParams((prev) => {
      if (newQuery) {
        prev.set('q', newQuery);
      } else {
        prev.delete('q');
      }
      prev.set('page', '1'); // Reset page on new search
      return prev;
    });
  }

  function updatePage(newPage: number) {
    setSearchParams((prev) => {
      prev.set('page', String(newPage));
      return prev;
    });
  }

  function updateSort(newSort: string) {
    setSearchParams((prev) => {
      prev.set('sort', newSort);
      prev.set('page', '1');
      return prev;
    });
  }

  function clearFilters() {
    setSearchParams({});
  }

  return (
    <div>
      <input
        value={query}
        onChange={(e) => updateSearch(e.target.value)}
        placeholder="Search..."
      />
      <select value={sortBy} onChange={(e) => updateSort(e.target.value)}>
        <option value="relevance">Relevance</option>
        <option value="date">Date</option>
        <option value="price">Price</option>
      </select>
      <button onClick={clearFilters}>Clear All</button>
    </div>
  );
}
```

### Multi-Value Search Params

```typescript
function FilterPanel() {
  const [searchParams, setSearchParams] = useSearchParams();

  // Get all values for a multi-value param
  const selectedTags = searchParams.getAll('tag');

  function toggleTag(tag: string) {
    setSearchParams((prev) => {
      const current = prev.getAll('tag');
      if (current.includes(tag)) {
        // Remove tag
        prev.delete('tag');
        current
          .filter((t) => t !== tag)
          .forEach((t) => prev.append('tag', t));
      } else {
        // Add tag
        prev.append('tag', tag);
      }
      return prev;
    });
  }

  return (
    <div>
      {availableTags.map((tag) => (
        <button
          key={tag}
          onClick={() => toggleTag(tag)}
          className={selectedTags.includes(tag) ? 'active' : ''}
        >
          {tag}
        </button>
      ))}
    </div>
  );
}
```

### Syncing Search Params with State

```typescript
import { useSearchParams } from 'react-router-dom';
import { useMemo } from 'react';

interface Filters {
  query: string;
  page: number;
  sortBy: string;
  category: string | null;
  minPrice: number | null;
  maxPrice: number | null;
}

function useFilters(): [Filters, (updates: Partial<Filters>) => void] {
  const [searchParams, setSearchParams] = useSearchParams();

  const filters: Filters = useMemo(
    () => ({
      query: searchParams.get('q') ?? '',
      page: Number(searchParams.get('page')) || 1,
      sortBy: searchParams.get('sort') ?? 'relevance',
      category: searchParams.get('category'),
      minPrice: searchParams.has('minPrice')
        ? Number(searchParams.get('minPrice'))
        : null,
      maxPrice: searchParams.has('maxPrice')
        ? Number(searchParams.get('maxPrice'))
        : null,
    }),
    [searchParams]
  );

  function updateFilters(updates: Partial<Filters>) {
    setSearchParams((prev) => {
      for (const [key, value] of Object.entries(updates)) {
        const paramKey =
          key === 'query' ? 'q' : key === 'sortBy' ? 'sort' : key;

        if (value === null || value === '' || value === undefined) {
          prev.delete(paramKey);
        } else {
          prev.set(paramKey, String(value));
        }
      }

      // Reset page when filters change (unless page itself is being updated)
      if (!('page' in updates)) {
        prev.set('page', '1');
      }

      return prev;
    });
  }

  return [filters, updateFilters];
}

// Usage
function ProductsPage() {
  const [filters, updateFilters] = useFilters();

  return (
    <div>
      <SearchBar
        value={filters.query}
        onChange={(q) => updateFilters({ query: q })}
      />
      <CategoryFilter
        value={filters.category}
        onChange={(cat) => updateFilters({ category: cat })}
      />
      <SortSelect
        value={filters.sortBy}
        onChange={(sort) => updateFilters({ sortBy: sort })}
      />
      <Pagination
        page={filters.page}
        onChange={(page) => updateFilters({ page })}
      />
    </div>
  );
}
```

---
