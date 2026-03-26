# Redux Toolkit v1 Patterns Skill

State management with Redux Toolkit v1 including configureStore, createSlice, createAsyncThunk, typed hooks, and entity adapter.

## When to Use

- Setting up a Redux store with configureStore
- Creating slices with createSlice
- Writing async logic with createAsyncThunk
- Defining typed hooks (useAppDispatch, useAppSelector)
- Managing normalized state with createEntityAdapter
- Writing memoized selectors with createSelector

## Version Constraints

- `.withTypes()` NOT available — use casting pattern
- RTK Query (`createApi`) NOT in v1.x
- `extraReducers`: builder callback ONLY
- Middleware: `.concat()`/`.prepend()`, NOT spread

## Resources

- `resources/store-setup.md` — configureStore, middleware, devTools
- `resources/async-patterns.md` — createAsyncThunk lifecycle, error handling
- `resources/entity-adapter.md` — normalized state, CRUD operations
