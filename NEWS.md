# aggregateR 1.2.0 (2026-10-18)

## Added

- `agg_exhibits(x)` lists an object's exhibits: name, title and perspectives.
- `agg_exhibit(x, name, perspective)` returns an `agg_exhibit`, always a list: `title`, `captions` and `tables`, the last two named by the server's block keys (`summary_df`, `reins_stats_df`). Its print shows each block's caption and table.
- Exhibit tables hold data only: row labels as character with spanned labels repeated, values as the server's raw numbers (`NA` where it has none), header levels joined into column names. They match the Excel add-in's spill cell for cell on its fixtures.
- `agg_q(x, p, basis)` returns exact quantiles for `p` in [0, 1], named like `quantile()`'s.
- Every function that takes `x` accepts a handle or a DecL program.

# aggregateR 1.1.0 (2026-10-18)

## Added

- `agg_build(decl, log2, bs)` builds a program and returns an `agg_handle`, or the number a value program such as `(2+2)` means. A character vector joins into one program, so `readLines()` of a `.agg` file works.
- The handle carries its recipe and server, prints its grid, moments and validation, and survives `saveRDS()` into a later R session.
- A build memo: the same program on the same grid posts once per R session and server. Building a name to a new id (a redefinition) clears it.
- A read through a handle whose object the server evicted rebuilds it and retries. If the rebuild gives a different id, the call is refused and asks for `agg_build()`.
- A program naming the session's own declarations (`port P agg.A ...`) survives a server restart: the client replays the missing declaration from its build log and retries.

# aggregateR 1.0.0 (2026-10-18)

## Added

- The package: `DESCRIPTION` (BSD-3), the RStudio project, and testthat tests that need no server.
- `agg_server()` gets or sets the server: the `aggregateR.server` option, then `AGGREGATER_SERVER`, then the public `https://agg.mynl.com`. The first request to the public server each R session says that programs are sent there.
- `agg_meta()` returns the server's facts: versions, grid caps, cache size and frame formats.
- Requests carry a per-server session id and retry a 429 up to three times, honoring `Retry-After` up to 60 s.
- Failures raise `aggregateR_refusal` or `aggregateR_transient`, both inheriting `aggregateR_error`, with the Excel add-in's readable text.
