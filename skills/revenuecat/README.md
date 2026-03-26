# RevenueCat Skill

Query RevenueCat subscription metrics, customer data, and search documentation via the v2 REST API.

## Requirements

- `RC_API_KEY` environment variable set to a v2 secret API key
- `curl` available in PATH

## When to Use

- Querying subscription analytics (MRR, churn, active subscribers)
- Looking up customer subscription status or purchase history
- Managing offerings, entitlements, or products
- Searching RevenueCat documentation
- Debugging subscription or entitlement issues

## Resources

- `references/api-v2.md` — auth, pagination, common patterns (load first)
- `references/metrics.md` — MRR, churn, active subscribers, charts
- `references/customers.md` — customer lookup, entitlements, purchase history
- `references/subscriptions.md` — subscription management, cancellation, refunds
- `references/products.md` — product CRUD, store products, test prices
- `references/offerings.md` — offerings, packages, package products
- `references/entitlements.md` — entitlement CRUD, attach/detach products
- `references/purchases.md` — purchase list, refunds, entitlements
- `references/projects.md` — projects, apps, API keys
- `references/paywalls.md` — paywall creation
- `references/integrations.md` — integrations CRUD
- `references/virtual-currencies.md` — virtual currencies
- `references/error-handling.md` — error codes and handling
- `references/rate-limits.md` — rate limit headers and backoff
- `scripts/rc-api.sh` — curl wrapper for the API
