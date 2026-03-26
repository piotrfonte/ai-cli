---
name: revenuecat
description: RevenueCat v2 REST API patterns for subscription metrics, customer data, offerings, entitlements, and documentation search including MRR, churn, and active subscriber analytics.
user-invocable: true
---

# RevenueCat

Query RevenueCat metrics, customer data, and search documentation.

## Quick Start

```bash
# Set your v2 secret API key
export RC_API_KEY=sk_...

# List projects (always start here to get project ID)
{baseDir}/scripts/rc-api.sh /projects

# Get overview metrics for a project
{baseDir}/scripts/rc-api.sh /projects/{projectId}/metrics/overview
```

## API Access Rules

- DO always call `GET /projects` first to get the project ID — it's required for all other calls
- DO load only the reference file relevant to the current task — not all of them
- DO use `{baseDir}/scripts/rc-api.sh <endpoint>` for GET requests
- DO use `{baseDir}/scripts/rc-api.sh -m POST -d '{"key":"value"}' <endpoint>` for mutations
- DO NOT hardcode project IDs — fetch them dynamically
- DO NOT load all reference files at once — lazy-load on demand

## Local API Reference

Start with `{baseDir}/references/api-v2.md` for auth, pagination, and common patterns. Then load the domain file you need:

| Domain             | File                               | Covers                                                                                                   |
| ------------------ | ---------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Customers          | `references/customers.md`          | CRUD, attributes, aliases, entitlements, subscriptions, purchases, invoices, virtual currencies, actions |
| Subscriptions      | `references/subscriptions.md`      | List, get, transactions, cancel, refund, management URL                                                  |
| Products           | `references/products.md`           | CRUD, create in store, test prices                                                                       |
| Offerings          | `references/offerings.md`          | Offerings, packages, package products                                                                    |
| Entitlements       | `references/entitlements.md`       | CRUD, attach/detach products                                                                             |
| Purchases          | `references/purchases.md`          | List, get, refund, entitlements                                                                          |
| Projects           | `references/projects.md`           | Projects, apps, API keys, StoreKit config                                                                |
| Metrics            | `references/metrics.md`            | Overview metrics, charts, chart options                                                                  |
| Paywalls           | `references/paywalls.md`           | Paywall creation                                                                                         |
| Integrations       | `references/integrations.md`       | Integrations CRUD                                                                                        |
| Virtual Currencies | `references/virtual-currencies.md` | Virtual currencies CRUD                                                                                  |
| Error Handling     | `references/error-handling.md`     | Error codes and handling                                                                                 |
| Rate Limits        | `references/rate-limits.md`        | Rate limit headers and backoff                                                                           |

## Common Queries

```bash
# Get a specific customer
{baseDir}/scripts/rc-api.sh /projects/{projectId}/customers/{appUserId}

# List subscriptions for a customer
{baseDir}/scripts/rc-api.sh /projects/{projectId}/customers/{appUserId}/subscriptions

# Get MRR and active subscribers chart
{baseDir}/scripts/rc-api.sh /projects/{projectId}/charts/mrr

# List all offerings
{baseDir}/scripts/rc-api.sh /projects/{projectId}/offerings
```

## Remote Documentation Search

The RevenueCat documentation is available at https://www.revenuecat.com/docs.

- Use https://www.revenuecat.com/docs/llms.txt and `/sitemap.xml` as a guide to available content
- Append `.md` to any documentation URL to get the markdown version

## References

- `references/api-v2.md` — auth, pagination, common patterns (load first)
- `references/metrics.md` — MRR, churn, active subscribers, charts
- `references/customers.md` — customer lookup, entitlements, purchase history
- `references/subscriptions.md` — subscription management, cancellation, refunds
- `scripts/rc-api.sh` — API wrapper script
