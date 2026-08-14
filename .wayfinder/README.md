# Wayfinder tracker (local markdown)

No issue tracker is configured for this repo, so wayfinder maps live here as files.

## Layout

```
.wayfinder/<map-slug>/
  MAP.md              # the map — labels: [wayfinder:map]
  tickets/NN-slug.md  # child issues of that map
```

## Wayfinding operations

- **Map**: `MAP.md`, front-matter `labels: [wayfinder:map]`.
- **Child ticket**: a file under `tickets/`. Front-matter carries `id`, `title`,
  `labels` (one `wayfinder:<type>`), `status` (`open` | `closed`), `assignee`,
  `blocked_by` (list of ticket ids).
- **Claim**: set `assignee` before any work. An open ticket with an empty
  `assignee` is unclaimed.
- **Blocking**: `blocked_by: [W1, W4]`. A ticket is unblocked when every id in
  that list has `status: closed`.
- **Frontier query**: open + unblocked + unassigned.

  ```bash
  grep -l "status: open" .wayfinder/*/tickets/*.md
  ```

- **Resolve**: append a `## Resolution` section to the ticket, set
  `status: closed`, then add one line to the map's *Decisions so far*.
