# aggregateR 1.0.0 (2026-10-18)

## Added

- The package: `DESCRIPTION` (BSD-3), the RStudio project, and testthat tests that need no server.
- `agg_server()` gets or sets the server: the `aggregateR.server` option, then `AGGREGATER_SERVER`, then the public `https://agg.mynl.com`. The first request to the public server each R session says that programs are sent there.
- `agg_meta()` returns the server's facts: versions, grid caps, cache size and frame formats.
- Requests carry a per-server session id and retry a 429 up to three times, honoring `Retry-After` up to 60 s.
- Failures raise `aggregateR_refusal` or `aggregateR_transient`, both inheriting `aggregateR_error`, with the Excel add-in's readable text.
