# React Query v3 Skill

Server state management with React Query v3 (`react-query` ^3.0-3.39). Do NOT use `@tanstack/react-query` v4/v5 APIs.

## When to Use

- Fetching data with useQuery
- Mutations with useMutation
- Cache invalidation and optimistic updates
- Pagination or infinite scroll
- Dependent/conditional queries

## Version Constraints

- Import from `react-query`, NOT `@tanstack/react-query`
- Use `cacheTime`, NOT `gcTime`
- Use `isLoading`, NOT `isPending`
- Use `useErrorBoundary`, NOT `throwOnError`
- Use `keepPreviousData: true`, NOT `placeholderData`

## Resources

- `resources/query-patterns.md` — query patterns, pagination, infinite scroll, polling
- `resources/mutation-patterns.md` — mutation patterns, optimistic updates, cache manipulation
