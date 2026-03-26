# Entity Adapter Patterns

## createEntityAdapter Basics

createEntityAdapter generates a set of prebuilt reducers and selectors for normalized state management.

### EntityState Shape

```typescript
interface EntityState<T> {
  ids: string[] | number[];  // Ordered array of all entity IDs
  entities: Record<string | number, T>;  // Lookup table by ID
}
```

### Creating an Adapter

```typescript
import { createEntityAdapter } from '@reduxjs/toolkit';

interface User {
  id: string;
  name: string;
  email: string;
  role: 'admin' | 'user';
}

// Basic adapter (uses entity.id by default)
const usersAdapter = createEntityAdapter<User>();

// With custom sort order
const usersAdapter = createEntityAdapter<User>({
  sortComparer: (a, b) => a.name.localeCompare(b.name),
});
```

### Custom selectId

When the entity's ID field is not named `id`:

```typescript
interface Comment {
  commentId: number;
  postId: string;
  text: string;
  author: string;
}

const commentsAdapter = createEntityAdapter<Comment>({
  selectId: (comment) => comment.commentId,
  sortComparer: (a, b) => a.commentId - b.commentId,
});
```

---

## Using with createSlice

### Complete Slice Example

```typescript
import { createEntityAdapter, createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import type { PayloadAction } from '@reduxjs/toolkit';
import type { RootState } from '../store';

interface Article {
  id: string;
  title: string;
  content: string;
  authorId: string;
  published: boolean;
  createdAt: string;
  updatedAt: string;
}

const articlesAdapter = createEntityAdapter<Article>({
  sortComparer: (a, b) => b.createdAt.localeCompare(a.createdAt),
});

export const fetchArticles = createAsyncThunk<Article[]>(
  'articles/fetchAll',
  async () => {
    const response = await fetch('/api/articles');
    return (await response.json()) as Article[];
  }
);

export const deleteArticle = createAsyncThunk<string, string>(
  'articles/delete',
  async (articleId) => {
    await fetch(`/api/articles/${articleId}`, { method: 'DELETE' });
    return articleId;
  }
);

const articlesSlice = createSlice({
  name: 'articles',
  initialState: articlesAdapter.getInitialState({
    status: 'idle' as 'idle' | 'loading' | 'succeeded' | 'failed',
    error: null as string | null,
    selectedId: null as string | null,
  }),
  reducers: {
    // Pass adapter methods directly as reducers
    articleAdded: articlesAdapter.addOne,
    articleRemoved: articlesAdapter.removeOne,
    articlesCleared: articlesAdapter.removeAll,

    // Custom reducer using adapter methods internally
    articlePublished(state, action: PayloadAction<string>) {
      articlesAdapter.updateOne(state, {
        id: action.payload,
        changes: {
          published: true,
          updatedAt: new Date().toISOString(),
        },
      });
    },

    articleSelected(state, action: PayloadAction<string | null>) {
      state.selectedId = action.payload;
    },
  },
  extraReducers: (builder) => {
    builder
      .addCase(fetchArticles.pending, (state) => {
        state.status = 'loading';
        state.error = null;
      })
      .addCase(fetchArticles.fulfilled, (state, action) => {
        state.status = 'succeeded';
        articlesAdapter.setAll(state, action.payload);
      })
      .addCase(fetchArticles.rejected, (state, action) => {
        state.status = 'failed';
        state.error = action.error.message ?? null;
      })
      .addCase(deleteArticle.fulfilled, (state, action) => {
        articlesAdapter.removeOne(state, action.payload);
      });
  },
});

export const {
  articleAdded,
  articleRemoved,
  articlesCleared,
  articlePublished,
  articleSelected,
} = articlesSlice.actions;

export default articlesSlice.reducer;
```

---

## CRUD Operations

### Single Entity Operations

```typescript
// Add one entity -- skips if ID already exists
articlesAdapter.addOne(state, article);

// Set one entity -- replaces if ID already exists, adds if not
articlesAdapter.setOne(state, article);

// Upsert one entity -- merges changes if exists, adds if not
articlesAdapter.upsertOne(state, article);

// Update one entity -- applies partial changes to existing entity
articlesAdapter.updateOne(state, {
  id: 'article-1',
  changes: { title: 'Updated Title' },
});

// Remove one entity
articlesAdapter.removeOne(state, 'article-1');
```

### Multiple Entity Operations

```typescript
// Add many -- skips IDs that already exist
articlesAdapter.addMany(state, articles);

// Set many -- replaces existing, adds new
articlesAdapter.setMany(state, articles);

// Upsert many -- merges existing, adds new
articlesAdapter.upsertMany(state, articles);

// Update many -- applies partial changes
articlesAdapter.updateMany(state, [
  { id: 'article-1', changes: { published: true } },
  { id: 'article-2', changes: { published: true } },
]);

// Remove many by IDs
articlesAdapter.removeMany(state, ['article-1', 'article-2']);
```

### Bulk Operations

```typescript
// Replace ALL entities
articlesAdapter.setAll(state, newArticles);

// Remove ALL entities
articlesAdapter.removeAll(state);
```

### Behavior Summary

| Method    | Existing ID        | New ID |
|-----------|--------------------|--------|
| addOne    | Skip (no change)   | Add    |
| setOne    | Replace entirely   | Add    |
| upsertOne | Merge changes      | Add    |
| updateOne | Apply changes      | Skip   |

---

## Generated Selectors

### Creating Selectors

```typescript
// Selectors scoped to a specific slice of state
export const {
  selectAll: selectAllArticles,
  selectById: selectArticleById,
  selectIds: selectArticleIds,
  selectEntities: selectArticleEntities,
  selectTotal: selectTotalArticles,
} = articlesAdapter.getSelectors<RootState>((state) => state.articles);
```

### Selector Descriptions

| Selector         | Returns                                        |
|------------------|------------------------------------------------|
| `selectAll`      | Array of all entities in sorted order           |
| `selectById`     | Single entity by ID, or undefined               |
| `selectIds`      | Array of all entity IDs                         |
| `selectEntities` | Entity lookup table (Record<string, Entity>)    |
| `selectTotal`    | Total number of entities                        |

### Usage in Components

```typescript
import { useAppSelector } from '../store/hooks';
import {
  selectAllArticles,
  selectArticleById,
  selectTotalArticles,
} from '../store/slices/articlesSlice';

function ArticleList() {
  const articles = useAppSelector(selectAllArticles);
  const totalCount = useAppSelector(selectTotalArticles);

  return (
    <div>
      <h2>Articles ({totalCount})</h2>
      {articles.map((article) => (
        <ArticleCard key={article.id} article={article} />
      ))}
    </div>
  );
}

function ArticleDetail({ articleId }: { articleId: string }) {
  const article = useAppSelector((state) =>
    selectArticleById(state, articleId)
  );

  if (!article) {
    return <div>Article not found</div>;
  }

  return (
    <div>
      <h1>{article.title}</h1>
      <p>{article.content}</p>
    </div>
  );
}
```

---

## Derived Selectors from Adapter

### Composing with createSelector

```typescript
import { createSelector } from '@reduxjs/toolkit';

// Select published articles only
export const selectPublishedArticles = createSelector(
  [selectAllArticles],
  (articles) => articles.filter((a) => a.published)
);

// Select articles by author
export const selectArticlesByAuthor = createSelector(
  [selectAllArticles, (_state: RootState, authorId: string) => authorId],
  (articles, authorId) => articles.filter((a) => a.authorId === authorId)
);

// Select article count by author
export const selectArticleCountByAuthor = createSelector(
  [selectArticlesByAuthor],
  (articles) => articles.length
);

// Select the currently selected article
export const selectCurrentArticle = createSelector(
  [
    selectArticleEntities,
    (state: RootState) => state.articles.selectedId,
  ],
  (entities, selectedId) => (selectedId ? entities[selectedId] : null)
);
```

### Usage with Parameterized Selectors

```typescript
function AuthorArticles({ authorId }: { authorId: string }) {
  const articles = useAppSelector((state) =>
    selectArticlesByAuthor(state, authorId)
  );

  return (
    <ul>
      {articles.map((article) => (
        <li key={article.id}>{article.title}</li>
      ))}
    </ul>
  );
}
```

---

## Additional State Beyond EntityState

### getInitialState with Extra Fields

```typescript
const articlesSlice = createSlice({
  name: 'articles',
  initialState: articlesAdapter.getInitialState({
    // These fields are added alongside ids and entities
    status: 'idle' as 'idle' | 'loading' | 'succeeded' | 'failed',
    error: null as string | null,
    selectedId: null as string | null,
    filters: {
      published: null as boolean | null,
      authorId: null as string | null,
    },
    pagination: {
      page: 1,
      pageSize: 20,
      totalPages: 0,
    },
  }),
  reducers: {
    // Access extra state alongside entity operations
    setFilters(state, action: PayloadAction<{ published?: boolean; authorId?: string }>) {
      if (action.payload.published !== undefined) {
        state.filters.published = action.payload.published;
      }
      if (action.payload.authorId !== undefined) {
        state.filters.authorId = action.payload.authorId;
      }
    },
    setPage(state, action: PayloadAction<number>) {
      state.pagination.page = action.payload;
    },
  },
  // ...
});
```

---

## Multiple Entity Adapters

### Separate Adapters for Different Entity Types

```typescript
// Each entity type gets its own adapter and slice
const usersAdapter = createEntityAdapter<User>({
  sortComparer: (a, b) => a.name.localeCompare(b.name),
});

const postsAdapter = createEntityAdapter<Post>({
  sortComparer: (a, b) => b.createdAt.localeCompare(a.createdAt),
});

const commentsAdapter = createEntityAdapter<Comment>({
  selectId: (comment) => comment.commentId,
});
```

### Nested Entity State

For entities that contain sub-entities (e.g., a post with comments):

```typescript
interface PostWithComments {
  id: string;
  title: string;
  content: string;
}

interface PostsState {
  // Posts managed by adapter
  ids: string[];
  entities: Record<string, PostWithComments>;
  // Comments stored separately, keyed by postId
  commentsByPost: Record<string, Comment[]>;
}

const postsAdapter = createEntityAdapter<PostWithComments>();

const postsSlice = createSlice({
  name: 'posts',
  initialState: postsAdapter.getInitialState({
    commentsByPost: {} as Record<string, Comment[]>,
  }),
  reducers: {
    commentsReceived(
      state,
      action: PayloadAction<{ postId: string; comments: Comment[] }>
    ) {
      state.commentsByPost[action.payload.postId] = action.payload.comments;
    },
    commentAdded(
      state,
      action: PayloadAction<{ postId: string; comment: Comment }>
    ) {
      const { postId, comment } = action.payload;
      if (!state.commentsByPost[postId]) {
        state.commentsByPost[postId] = [];
      }
      state.commentsByPost[postId].push(comment);
    },
  },
});
```

---

## Complete Real-World Example

```typescript
// src/store/slices/productsSlice.ts
import {
  createEntityAdapter,
  createSlice,
  createAsyncThunk,
  createSelector,
} from '@reduxjs/toolkit';
import type { PayloadAction } from '@reduxjs/toolkit';
import type { RootState } from '../store';

interface Product {
  id: string;
  name: string;
  price: number;
  category: string;
  inStock: boolean;
  createdAt: string;
}

const productsAdapter = createEntityAdapter<Product>({
  sortComparer: (a, b) => a.name.localeCompare(b.name),
});

// Thunks
export const fetchProducts = createAsyncThunk<Product[]>(
  'products/fetchAll',
  async () => {
    const response = await fetch('/api/products');
    return (await response.json()) as Product[];
  }
);

export const saveProduct = createAsyncThunk<
  Product,
  Omit<Product, 'id' | 'createdAt'>,
  { rejectValue: string }
>(
  'products/save',
  async (productData, { rejectWithValue }) => {
    try {
      const response = await fetch('/api/products', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(productData),
      });
      if (!response.ok) {
        return rejectWithValue('Failed to save product');
      }
      return (await response.json()) as Product;
    } catch {
      return rejectWithValue('Network error');
    }
  }
);

// Slice
const productsSlice = createSlice({
  name: 'products',
  initialState: productsAdapter.getInitialState({
    status: 'idle' as 'idle' | 'loading' | 'succeeded' | 'failed',
    error: null as string | null,
    categoryFilter: null as string | null,
    inStockOnly: false,
  }),
  reducers: {
    productUpdated: productsAdapter.updateOne,
    productRemoved: productsAdapter.removeOne,
    setCategoryFilter(state, action: PayloadAction<string | null>) {
      state.categoryFilter = action.payload;
    },
    setInStockOnly(state, action: PayloadAction<boolean>) {
      state.inStockOnly = action.payload;
    },
  },
  extraReducers: (builder) => {
    builder
      .addCase(fetchProducts.pending, (state) => {
        state.status = 'loading';
        state.error = null;
      })
      .addCase(fetchProducts.fulfilled, (state, action) => {
        state.status = 'succeeded';
        productsAdapter.setAll(state, action.payload);
      })
      .addCase(fetchProducts.rejected, (state, action) => {
        state.status = 'failed';
        state.error = action.error.message ?? null;
      })
      .addCase(saveProduct.fulfilled, (state, action) => {
        productsAdapter.addOne(state, action.payload);
      });
  },
});

export const {
  productUpdated,
  productRemoved,
  setCategoryFilter,
  setInStockOnly,
} = productsSlice.actions;

// Adapter selectors
export const {
  selectAll: selectAllProducts,
  selectById: selectProductById,
  selectIds: selectProductIds,
  selectTotal: selectTotalProducts,
} = productsAdapter.getSelectors<RootState>((state) => state.products);

// Derived selectors
const selectCategoryFilter = (state: RootState) => state.products.categoryFilter;
const selectInStockOnly = (state: RootState) => state.products.inStockOnly;

export const selectFilteredProducts = createSelector(
  [selectAllProducts, selectCategoryFilter, selectInStockOnly],
  (products, category, inStockOnly) => {
    let filtered = products;
    if (category) {
      filtered = filtered.filter((p) => p.category === category);
    }
    if (inStockOnly) {
      filtered = filtered.filter((p) => p.inStock);
    }
    return filtered;
  }
);

export const selectCategories = createSelector(
  [selectAllProducts],
  (products) => [...new Set(products.map((p) => p.category))].sort()
);

export const selectProductsStatus = (state: RootState) => state.products.status;
export const selectProductsError = (state: RootState) => state.products.error;

export default productsSlice.reducer;
```
