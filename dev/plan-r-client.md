# Plan: `aggregateR`, an R client for aggregate-api

Status: second draft, 2026-10-18, with the author's rulings folded in (see "Author rulings").
Six steps with one version bump each, 1.0.0 to 1.5.0.

## Goal

Make the `aggregate` actuarial library usable from R. An R user writes DecL, builds objects,
reads exhibits, quantiles and full frames as `data.frame`s, and can keep everything on their own
machine. Actuaries use R heavily. reticulate, which embeds Python in R, promises this but brings
environment and type-conversion pain, so this package talks to the existing HTTP API instead.

## Where things stand

**This repo** (`V:\dev\aggregate-R`, to be published as `github.com/mynl/aggregate-R`) holds
`CLAUDE.md` and `.gitignore` and nothing else. The package name is `aggregateR`, since R
package names cannot contain a hyphen; it is not taken on CRAN. Read `CLAUDE.md` first: it
fixes the stack, the test-fixture location and the use of `NEWS.md`.

**R on DOOB:**

- R 4.6.1 and RStudio are installed, with devtools 2.5.2, httr2 1.3.0, jsonlite 2.0.0,
  nanoparquet 0.5.2, processx 3.9.0, testthat 3.3.2, roxygen2 8.1.1 and usethis 3.2.2.
- Find `Rscript.exe` through the registry, as `CLAUDE.md` says; it is not on `PATH`.
- Rtools is not needed, since the package has no compiled code.

**nanoparquet is verified against the server** (2026-10-18). The test object was a two-unit
portfolio built on the public server at log2 16.

- **Reading:** its `density_df` (65,536 × 33) arrives as Parquet with ZSTD and BYTE_STREAM_SPLIT
  on every column. That is a 5.2 MB, 0.9 s fetch, and nanoparquet reads it in 13 ms.
- **Against CSV:** the CSV route takes 9.8 s to fetch and parse the same frame. Values agree to
  2.2e-16, CSV's text rounding.
- **Two details for `[frames]`:**
  - Parquet keeps non-finite values, and CSV does not.
  - `read_parquet()` returns a `tbl`, so it needs `as.data.frame()`.

The check script was a scratch file; `[frames]` turns it into a live test.

**The server** is `aggregate-api`, in the sibling repo `../aggregate-api` (FastAPI, Python).
Facts this plan relies on, checked on 2026-10-18:

- **The public server,** `https://agg.mynl.com`, runs 1.26.0. From its `/v1/meta`: `log2_cap`
  18, `log2_default` 16, `build_timeout_s` 10, `cache_max` **50** objects, and `frame_formats`
  `["csv", "json", "parquet"]`. With a 50-object cache, eviction is routine rather than rare.
- **PyPI has only `aggregate_api` 1.0.0.** That release predates the Parquet route (1.18.0),
  the `/frames` listing (1.24.0) and the `parquet` extra. The author will publish a new release
  **after this client works**, because the R work may still force API changes. Until then the
  launcher runs from a local checkout or from git (see `[launcher]`).
- **Object ids** have been a hash of the parsed program since 1.14.0. The same program on the
  same grid therefore always gets the same id, in any session, and re-posting a program the
  server still holds is a cheap cache hit.
- **Sessions:**
  - A client mints an id and sends it in the `X-Aggregate-Session` header.
  - A build registers the names it declares (`agg A ...`) in that session's private recipe
    base, so a later `port P agg.A ...` in the same session resolves `A`.
  - The registry is an LRU (500 sessions) with an 8-hour TTL, held in memory. After an eviction
    or a restart, a reference to an own declaration fails with a 422 whose `detail.error` is
    `recipe_not_found`.
- **The reference client** is the Excel add-in, `../aggregate-api/excel/src/functions/core.ts`
  and `functions.ts`. It already solves handles, rebuilding an evicted object, a program in
  place of a handle, flattening exhibits and readable refusals. Port its decisions; don't
  re-derive them.

**Routes the client uses.** All are under `/v1`, and the full list is at `/openapi.json`.

| route | returns |
|---|---|
| `GET /health` | `{ok, version, aggregate_version}` |
| `GET /meta` | versions, `log2_cap`, `log2_default`, `cache_max`, `frame_formats` |
| `POST /objects` body `{decl, log2?, bs?}` | a build: `{id, kind, name, cached, bs, log2, mean, cv, validation, warnings, note, ...}`; or `{kind: "value", value, decl}` when the program evaluates to a number |
| `GET /objects/{id}/exhibits` | `{exhibits: [{name, title, perspectives}]}` |
| `GET /objects/{id}/exhibit/{name}?perspective=raw` | an envelope, `{name, blocks: [{caption, columns, head, body: [{cells}], n_stub_levels}]}` |
| `GET /objects/{id}/quantiles?p=0.99,0.995&snap=false` | `{quantiles: [{p, q, snapped}]}`; `p` in [0, 1] |
| `GET /objects/{id}/frames` | `{frames: [{name, rows, columns}]}` |
| `GET /objects/{id}/frame/{which}.parquet` | the whole frame; zstd with byte stream split on float columns; 501 without pyarrow |
| `GET /objects/{id}/frame/{which}.csv` | the same frame as CSV |
| `GET /examples[?database=stem]` | `{items: [{name, kind, decl, ...}]}`, the library in file order |

Errors the client must read:

- **404 `{"detail": "object <id> not in cache"}`:** evicted. Rebuild and retry.
- **422 with `detail` `{line, column, message, ...}`:** a parse error.
- **422 with `detail` `{error: "recipe_not_found" | ..., message}`:** a structured refusal.
- **429 with `Retry-After`:** rate limited; the Caddy front end limits builds.
- **504:** build timeout.
- **501:** Parquet unavailable.
- **FastAPI validation errors:** a list of `{loc, msg}`.

`core.ts:errorMessage` gives the readable text for each case; port it.

**API changes.** If a step needs something the API lacks, or finds a route that answers badly
for R, stop that step and say so. The change becomes a plan in `aggregate-api` and lands there
first, and the step's execution-log entry records it. This repo never works around the API. A
change found this way is why the PyPI release waits.

## Options considered

From a discussion in the aggregate-api sessions, 2026-10-16 and 17:

1. **A thin R client over the HTTP API. Chosen.**
2. **The same client plus a local launcher. Chosen,** as the last step. It is the answer for
   real data.
3. **No package,** just `httr2` and `read.csv()` against the routes. Good as a README
   illustration, too clumsy as the product.
4. **reticulate.** Rejected for the reasons above.

Also rejected:

- **A client generated from `openapi.json`.** It is clunky, and exhibits are open JSON that a
  generator types poorly.
- **An R reimplementation, or a plumber server.** Pointless duplication.

## Design

### Exported functions

Every function that takes `x` accepts either an `agg_handle` or a character DecL program. A
program is built first, on the default grid, through `agg_build()`.

| function | does | route |
|---|---|---|
| `agg_server(url)` | get or set the server for this R session; returns the previous value invisibly | none |
| `agg_meta()` | server facts as a list | `/meta` |
| `agg_build(decl, log2 = NULL, bs = NULL)` | build; returns an `agg_handle`, or a plain number for a value program | `POST /objects` |
| `agg_exhibits(x)` | data frame: `name`, `title`, `perspectives` | `/exhibits` |
| `agg_exhibit(x, name, perspective = "raw")` | an `agg_exhibit`: the text and a list of tables, kept apart (see below) | `/exhibit/{name}` |
| `agg_q(x, p, basis = "aggregate")` | numeric vector of exact quantiles, named like `quantile()`'s (`"99%"`) | `/quantiles` |
| `agg_frames(x)` | data frame: `name`, `rows`, `columns` | `/frames` |
| `agg_frame(x, which = "density_df")` | the whole frame as a `data.frame` | `.parquet`, else `.csv` |
| `agg_library(database = NULL)` | data frame: `name`, `kind`, in file order | `/examples` |
| `agg_program(name, database = NULL)` | that entry's DecL as one string | `/examples` |
| `agg_start(port = NULL, from = NULL)` / `agg_stop()` | run or stop a local server | none |

**Server choice.** The server is resolved in this order:

1. `agg_server(url)`, which sets the R option `aggregateR.server`.
2. The environment variable `AGGREGATER_SERVER`, for `.Renviron`.
3. `https://agg.mynl.com`.

The first request of each session to the public server prints a one-line message: "programs
are sent to https://agg.mynl.com; agg_start() runs a private local server."

### The handle

The handle is an S3 list of class `agg_handle` with these fields:

- `id`, `kind`, `name`
- the recipe as requested: `decl`, `log2`, `bs`, where `NULL` means server default
- `server`
- the resolved grid and headline statistics from the build response: `log2`, `bs`, `mean`,
  `cv`, `validation`, `warnings`

A print method shows it as:

```
<agg_handle> agg.A #4f40714271198d8f
  server      https://agg.mynl.com
  grid        log2 16, bs 0.0625
  mean, cv    100, 0.316
```

The handle carries its own recipe. It plays the part of the add-in's workbook recipe table, and
like a workbook it persists: a handle saved with `saveRDS()` still works in a later R session.

### Client-side cache: the Excel add-in's approach, ported

The add-in (`functions.ts`: `buildOnce`, `readFrom`, `remember`) keeps four pieces of
client-side state. R ports each one, and departs only where Excel's reason doesn't apply.

| add-in | R |
|---|---|
| **Build memo:** (program, log2, bs) → handle or value, per runtime, so cells sharing a program post once | **Ported.** A memo per server in the package environment, keyed the same way, consulted by `agg_build()` and by every function given a program. `agg_q("agg B ...")` then `agg_exhibit("agg B ...")` is one POST, which matters because the public server rate-limits builds. |
| **Recipe table:** id → (program, log2, bs), the newest 500, saved in the workbook | **Ported onto the handle** (above). No separate table is needed, because an R handle is an object, not text in a cell. |
| **Rebuild on eviction:** a 404 "not in cache" re-posts the recipe. The same id retries the read once; a different id means the server's library or version changed, so it clears the memo and fails, asking for a recalculation. | **Ported as is.** A different id clears the memo and raises an `aggregateR_refusal` saying the server changed and the handle must be rebuilt with `agg_build()`. Silently swapping the id could change what `agg.X` means under the user. |
| **Library listing:** fetched once per runtime per database | **Ported.** Cached per server and database for the session. `/meta` is cached the same way, for `frame_formats`. |
| In-flight sharing of a build | **Not ported.** It exists for parallel recalculation, and R calls are sequential. |
| Memoized refusals: the same program draws the same refusal until edited | **Not ported.** It exists to stop recalculation storms. An R call is explicit, and a refusal such as `recipe_not_found` can clear on retry. |

**One addition the add-in doesn't need: a session build log.** The add-in sends
`library_references_only` and refuses a program that names the user's own declarations, since a
cell cannot see which other cell built them. R can track that, so it allows
`agg A ...` then `port P agg.A ...`, which resolves through the session's recipe base on the
server. That base dies with a restart or an eight-hour idle. The client therefore keeps the
ordered, de-duplicated recipes it has built, capped at 500 with the oldest dropped first. On a
422 `recipe_not_found` it replays the newest recipe that built the missing name and retries
(ruling 8). Because a program may now name the session's own declarations, a redefinition
clears the build memo (ruling 7).

### Requests and sessions

One internal function, `agg_request(method, path, body = NULL, handle = NULL)`, does the
following:

- Uses the handle's server when a handle is given, otherwise the current one.
- Sends `X-Aggregate-Session`, plus a user agent `aggregateR/<version>`.
- Retries a 429 up to three times, honoring `Retry-After` but capped at 60 s, as the add-in
  does (httr2's `req_retry()`).
- Applies the recovery rules above: rebuild on a 404, replay on `recipe_not_found`.
- Otherwise turns a 4xx or 5xx into an R error carrying the `core.ts:errorMessage` text.

The session id is minted once per server per R session as `r-<ISO-8601 UTC>-<32 hex>`. It must
match the server's `^[A-Za-z0-9:.\-_]{8,200}$`.

**Errors** are classed base-R conditions. That adds no dependency, and callers can `tryCatch`
on the class:

- `aggregateR_refusal`: the program or an argument is wrong. A parse error reads
  `line L, col C: message`.
- `aggregateR_transient`: rate limited after retries, a timeout, unreachable, or a 5xx.

Both inherit `aggregateR_error`.

### Exhibits: the text and the tables, kept apart

The envelope from `/exhibit/{name}` has this shape (see
`../aggregate-api/excel/test/fixtures/summary-basicbook.json` and
`reins-aggregatestoploss.json`):

- **The whole exhibit:** `name`, `title` ("Summary: BasicBook"), `perspective`, and
  `meta.blocks`, the block keys such as `summary_df` or `reins_stats_df`.
- **Each block:**
  - `caption`, often a paragraph of explanation
  - `columns`: one spec per column, with `name` (a list of header levels), `role` (`"stub"` for
    a row label), and `dtype`
  - `head`, the rendered header rows
  - `body`: rows of `cells`. A stub cell is plain text or `{text, rowspan}`; a value cell is
    `{raw, text}`, where `text` is display formatting.
  - `n_stub_levels` and `ir_version` (1 today)

`agg_exhibit()` **always returns a list** of class `agg_exhibit`, whether the exhibit has one
block or several. The text sits apart from the data:

```r
ex <- agg_exhibit(a, "summary")
ex$title       # "Summary: BasicBook"
ex$captions    # named character vector, one caption per block
ex$tables      # named list of data.frames, same names: list(summary_df = <data.frame>)
ex             # print: the title, then each block's name, wrapped caption and table
```

The names are the block keys from `meta.blocks`, which are short and stable, never the
captions. Each table holds data only:

- **Stub columns** become character columns. A `rowspan` repeats its label down the rows it
  covers; port `core.ts:blockRows` for this.
- **Value columns** take `raw`, numeric for numeric `dtype`s with null as `NA`. The display
  `text` is dropped.
- **Column names** come from `columns[].name`, with non-empty levels joined by a space
  (`occ Gross`, `agg Ceded`), kept as is (`check.names = FALSE`). Use these rather than
  reconstructing names from `head`.

An `ir_version` other than 1 raises a warning naming it, since the layout may have changed.

### Frames

`agg_frame` reads the server's `frame_formats` from `/meta`, cached per server for the session:

- **With `parquet`,** it downloads to a temp file and reads it with `nanoparquet`, converting
  the `tbl` to a plain `data.frame`. This is the path measured above: 0.9 s for 65,536 × 33.
- **Otherwise,** it reads the `.csv` route with `utils::read.csv(check.names = FALSE)`. That
  takes about ten times as long and loses non-finite values; the Parquet path is bit-exact.

At the public cap, log2 18, a 43-column portfolio frame is 11M doubles, about 90 MB in R. That
is fine.

### The launcher

`agg_start(port = NULL, from = NULL)` works as follows:

1. Checks `Sys.which("uvx")`. If uv is missing, it fails with the install line,
   `winget install astral-sh.uv`.
2. Picks a random port in 20000–39999 unless one is given.
3. Runs `uvx --from <from> aggregate-api --host 127.0.0.1 --port <port>` through `processx`,
   with output going to a log file under `tempdir()`.
   - `from` is passed to uv verbatim as a requirement spec. It defaults to
     `"aggregate-api[parquet]>=1.26"`.
   - Until the PyPI release, that floor makes uv fail to resolve, loudly, rather than quietly
     run 1.0.0. `agg_start()` then says to pass `from`.
   - For development, pass a git spec,
     `"aggregate-api[parquet] @ git+https://github.com/mynl/aggregate_api"`, or a local
     checkout as a `file://` spec. The path is supplied at call time and never written into the
     package.
   - A local server runs whatever `aggregate` uv resolves. PyPI has 1.2.0 today, while the
     public server runs 1.5.2. The same program can therefore differ between the two;
     `agg_meta()` shows both versions.
4. Polls `/v1/health` for up to 180 s, since the first run downloads numpy, scipy and the rest.
   If the process exits early, it reports the log's tail.
5. Sets the session's server to the local one, remembering the previous server.

`agg_stop()` kills the process and restores the previous server. The process also dies with
the R session, through processx's `cleanup = TRUE`. The launcher always binds `127.0.0.1`.

### Tests

- **testthat, third edition.** Fixtures are synthetic: library programs and made-up DecL,
  captured once from a local server into `tests/testthat/fixtures/*.json` by
  `dev/capture-fixtures.R`.
- **Pure logic is tested on those fixtures:** block flattening, error messages, session-id
  shape and the handle's print.
- **HTTP flows are tested with httr2's own mocking** (`local_mocked_responses()`), so there is
  no extra dependency. The flows, each asserting the number of requests made:
  - the same program twice makes one POST (the memo)
  - a 404, then a rebuild to the same id, then a retry
  - a 404, then a rebuild to a different id, which clears the memo and refuses
  - `recipe_not_found`, then a replay, then a retry
  - a 429, then a retry
  - a value program
  - Parquet against a server that lacks it
- **Live tests** run only when `AGGREGATER_LIVE_SERVER` is set (for example
  `http://127.0.0.1:19456`). They never touch the public server, and they are skipped on CRAN.
- `devtools::check()` gives 0 errors and 0 warnings at every bump. Notes are explained in the
  commit's NEWS entry or fixed.

## Steps

Each step is one commit with its version bump in `DESCRIPTION`, a `NEWS.md` entry and the README
grown to show the new functions.

### `[scaffold]` 1.0.0: the package exists and talks to a server

- The skeleton, through `usethis`:
  - `DESCRIPTION`: BSD-3 to match `aggregate` and `aggregate-api`; Imports `httr2`, `jsonlite`;
    `Depends: R (>= 4.1)`; `URL` and `BugReports` at `github.com/mynl/aggregate-R`. The
    README's install line is `pak::pak("mynl/aggregate-R")`.
  - `aggregateR.Rproj`
  - `.Rbuildignore`, listing `dev/`, `CLAUDE.md`, `R-for-idiots.md` and `.Rproj.user`
  - `NEWS.md`, `README.md`, `LICENSE` and the testthat setup.
- `agg_server()`, `agg_meta()`, `agg_request()` with the session header and error mapping, and
  the session state.
- **Acceptance:**
  - `devtools::check()` is clean.
  - `agg_meta()` returns versions from a local server and from the public one.
  - A request to an unreachable server gives an `aggregateR_transient` error naming the URL.

### `[build]` 1.1.0: build and handles

- `agg_build()`, the `agg_handle` class and its print method.
- Resolving a handle or a program.
- A value program returns its number from `agg_build()`, and is refused as `x` elsewhere.
- The client-side cache as designed above:
  - the build memo
  - rebuild on 404, including the different-id refusal
  - the session build log and replay on `recipe_not_found`
  - the 429 retry
- **Acceptance:**
  - `a <- agg_build("agg A 10 claims sev lognorm 10 cv 1 poisson")` prints a handle.
  - Calling it again sends no request.
  - After `DELETE /v1/objects/{id}` on a local server, a read through `a` still answers, with
    the same id.
  - `agg A ...` then `port P agg.A agg.Capstone.Gross` builds. After a local server restart, a
    read through P still answers.
  - A handle saved with `saveRDS()` and read back in a fresh R session answers.
  - The mocked flows above pass.

### `[exhibits]` 1.2.0: exhibits and quantiles

- `agg_exhibits()`, `agg_exhibit()` and `agg_q()`.
- **Acceptance:**
  - `agg_exhibit()` returns an `agg_exhibit` list for every exhibit, one block or many.
  - Its `tables` hold only data: stubs as character, values as numbers, no display text.
  - Its `title` and `captions` carry the text, named by the `meta.blocks` keys.
  - On the add-in's two fixtures (`summary-basicbook`, `reins-aggregatestoploss`), the numbers
    match the add-in's spill cell for cell. The reins fixture covers two header levels, three
    stub levels and rowspans.
  - `agg_q(a, c(0, 0.5, 1))` returns the support ends and the median.

### `[frames]` 1.3.0: whole frames

- `agg_frames()` and `agg_frame()`, with Parquet through `nanoparquet` (added to Imports) and
  the CSV fallback.
- **Acceptance:**
  - A live test repeats the 2026-10-18 check against a local server: a portfolio's
    `density_df` read through Parquet matches the CSV route's finite values. That check found
    nanoparquet reads the server's format; if a later server breaks it, YELL rather than
    switching to `arrow`.
  - The elapsed time for a 65,536-row frame is recorded in the NEWS entry.
  - A server reporting no `parquet` falls back to CSV.

### `[library]` 1.4.0: the example library

- `agg_library()` and `agg_program()`, with the listing cached per server and database for the
  session, as the add-in does.
- **Acceptance:**
  - `agg_build(agg_program("Capstone.Gross"))` works.
  - A second `agg_program()` call sends no request.
  - An unknown name says so and points at `agg_library()`.

### `[launcher]` 1.5.0: a private local server

- `agg_start()` and `agg_stop()`, with `processx` added to Imports.
- **Developed and accepted against a local checkout or git,** passed as `from`. The author
  publishes `aggregate_api` to PyPI once this client works, including any API changes the
  earlier steps forced. The no-argument `agg_start()` works from that release on.
- **Acceptance:**
  - On a machine with uv, `agg_start(from = <a checkout spec>)` brings up a server on
    `127.0.0.1` within 180 s cold.
  - The README script runs against it end to end.
  - `agg_stop()` frees the port, and quitting R kills the server.
  - Without `from`, before the release, it fails with a message telling the user to pass
    `from`.

## Out of scope

- **CRAN submission.** It needs its own plan: vignettes that don't hit the network, fixtures
  only in examples, and the CRAN policy on web services.
- Charts, pricing, PnL, reinsurance, sharpen and bounds routes. Add them later, one function
  per need.
- **The library-side `quantile_frame`.** It is a separate plan in `aggregate_REFACTOR`; R picks
  it up as an argument to `agg_frame` once the API exposes it.
- Parallel or async requests.

## Author rulings (2026-10-18)

1. **Package name `aggregateR`; changelog in `NEWS.md`; branch stays `master`.**
2. **The default server is `https://agg.mynl.com`,** with the first-use message.
3. **`agg_exhibit()` always returns a list, and the text is kept apart from the tables.**
   Consistency is king.
4. **The GitHub repo is `aggregate-R`.**
5. **Client-side caching follows the Excel add-in,** ported as in "Client-side cache".
6. **`aggregate_api` goes to PyPI after this client works,** since the R work may still change
   the API.

Two more from the execution review, also 2026-10-18:

7. **[memo-redefinition] A redefinition clears the build memo.** The memo is keyed on the program text, which fixes a program's meaning only when it names library entries alone, as the add-in's do. In R, `agg A` v1, `port P agg.A agg.B`, `agg A` v2, `port P agg.A agg.B` would otherwise serve the first P from the memo, which is the stale-object bug the server fixed in 1.14.0 by keying on parsed specs. The client tracks the id each `kind.name` last built to on a server, and clears that server's memo when a build of that name returns a different id. A rebuild at another grid also changes the id and clears the memo; that costs only extra requests, never a wrong object.
8. **[targeted-replay] `recipe_not_found` replays only the missing name.** The 422 names the `kind` and `name` it lacks. The client replays the newest logged program that built that name, repeats for any further name the retry reports (at most 10 replays), and then retries. Replaying the whole log, up to 500 builds, would outrun the public server's 30 builds a minute.

## Execution log

(Filled in as steps land: version, date, commit, divergences from the plan.)

**Review, 2026-10-18.** Every fact in "Where things stand" checked true against the public server, `../aggregate-api` 1.26.0 and the add-in's fixtures. `aggregate-api[parquet]` installed by uv from the checkout imports cleanly against PyPI's `aggregate` 1.2.0, so `[launcher]` is not blocked. Rulings 7 and 8 came out of the review. Live checks run against a private server from the sibling's venv on `127.0.0.1:19480`; port 19456 is already held by the author's own server.

**`[scaffold]` 1.0.0, 2026-10-18.** Acceptance: `devtools::check()` 0 errors, 0 warnings, 0 notes; `agg_meta()` answers 1.26.0 / 1.5.2 from the local server and from the public one; `http://127.0.0.1:9` raises `aggregateR_transient` "server unreachable: http://127.0.0.1:9". Divergences:

- **`devtools::check()` needs `options(buildtools.check = function(action) TRUE)`.** pkgbuild refuses to start without Rtools even for a pure R package. `CLAUDE.md`'s Commands section now says so.
- **Recovery sits above `agg_request()`, not inside it.** As in the add-in, `agg_send()` performs one request and retries a 429, and `agg_request()` raises the classed error; rebuilding and replay go in `[build]`, where the handle and the build log are in reach.
- **The 429 retry is a loop of the package's own, not httr2's `req_retry()`.** It ports `core.ts:retryAfterSeconds` exactly (seconds or an HTTP date, clamped to 1 to 60 s), and its sleep is a package function that tests mock away. HTTP dates are parsed by hand, since httr2 does not export its parser and `strptime` reads month names in the user's locale.
- **The session id's 32 hex come from OpenSSL through `httr2::secret_make_key()`**, not R's generator. Anyone holding the id can read back the session's programs, and drawing from R's generator would both move the user's `.Random.seed` and give two sessions that called `set.seed(1)` the same id. No new import.
- **The first-use message says "agg_server() selects a private server" until `[launcher]`,** which switches it to the plan's wording naming `agg_start()`. Naming a function that does not exist yet would mislead.
- **`agg_server()` with no argument returns the server visibly;** only setting returns the previous value invisibly. An invisible getter prints nothing at the console.
- **`withr` is in Suggests** for the tests' options and environment variables. It comes with testthat, so nothing new is installed.
- **`LICENSE` carries `ORGANIZATION`** as well as year and holder; R's BSD-3 template requires it, and `R CMD check` notes its absence.

**`[build]` 1.1.0, 2026-10-18.** Acceptance against a local server: the handle prints; a second `agg_build()` sends 0 requests; after `DELETE /v1/objects/{id}` a read through `a` answers with the same id; `agg A` then `port P agg.A agg.Capstone.Gross` builds, and after a server restart a read through P answers in 5 requests (404, P refused for lost A, A replayed, P rebuilt to the same id, the read); saved `a` and `p` handles read in a fresh R session. The mocked flows are in `tests/testthat/test-build.R`; the live ones run with `AGGREGATER_LIVE_SERVER` set. `devtools::check()` clean. Divergences:

- **The handle's requested grid lives in `recipe`**, as `recipe$decl`, `recipe$log2` and `recipe$bs`, because the plan named both the requested and the resolved grid `log2` and `bs`. The resolved values keep the top-level names.
- **The print adds a `validation` line, and a `warning` line per build warning.** A port built at the default grid reads "fails sev mean, agg mean", which a user must see.
- **`agg_build()` accepts a character vector,** joining non-empty elements with newlines as the add-in joins a range, so `readLines()` of a `.agg` file builds.
- **Ruling 8 as built:** the newest logged recipe for the missing `kind.name` is replayed, retried, and repeated for any further missing name; one budget of 10 replays is shared down the recursion, since a replayed program can itself need a replay. A missing name the log does not hold is refused with the server's message.
- **The "changed" refusal reads "the server changed, or a name it uses was redefined in this session",** since with the session's own declarations a different id has both causes.
- **No read function is exported at 1.1.0,** so the acceptance reads used the internal `read_object()` on `GET /v1/objects/{id}`; `[exhibits]` exercises the same path through exported functions.

**`[exhibits]` 1.2.0, 2026-10-18.** Acceptance: R's tables match the add-in's `flattenExhibit` spill cell for cell on the add-in's own fixtures (`summary-basicbook`, both blocks of `reins-aggregatestoploss`, `stats-basicbook`): 499 cells, 0 mismatches, compared by a scratch script running the add-in's `core.ts` under Node. Live: every exhibit of an agg, a port naming the session's own agg, and `AggregateStopLoss` reads as an `agg_exhibit` of data frames; `agg_q(a, c(0, 0.5, 1))` gives the support ends and the median. `devtools::check()` clean. Divergences:

- **Value columns are typed by the IR's `dtype`:** `float` and `int` numeric (a big int arrives as a string and is read as a number), `bool` logical, anything else character. A value column the server sends without raw values (no `raw: true` on its column spec) keeps its display text rather than becoming all `NA`.
- **`agg_exhibit` also carries `name` and `perspective`** beside `title`, `captions` and `tables`.
- **Missing or duplicated `meta.blocks` keys fall back to `block1`, `block2`, ...**
- **`p` goes to the server as text that reads back as the same double:** the short form where it round-trips, 17 digits where it does not.
- **`stats` joins `utils` in Imports** for `setNames()`. Both ship with R, so nothing new is installed.
- **The committed exhibit fixtures are this repo's own,** captured by `dev/capture-fixtures.R` from a local server, rather than copies of the add-in's.

**`[frames]` 1.3.0, 2026-10-18.** Acceptance: the live test repeats the 2026-10-18 check against the local server on a synthetic two-unit portfolio at log2 16: `density_df`, 65,536 by 33, through Parquet matches the CSV route on every finite value (largest relative difference 2.2e-16). Elapsed, warm, local: Parquet 0.06 s, CSV 5.53 s (recorded in NEWS). A server whose `frame_formats` lack `parquet` is read from CSV (mocked). `devtools::check()` clean. Divergences:

- **CSV does not lose non-finite values in R.** The server writes NaN as null in Parquet and as an empty field in CSV, so both arrive as `NA` (872 cells in the portfolio's frame, identical in each); `inf` and `-inf` survive both, since R's CSV reader parses them. The difference that remains is CSV's last-bit rounding. `agg_frame()`'s help says so instead of the plan's claim.
- **A 501 from the Parquet route also falls back to CSV,** not only a `frame_formats` without `parquet`, so a server whose meta and pyarrow disagree still answers.
- **The frame fixtures are a 16-row discrete object** (`agg Dice dfreq [1:2] dsev [1:6]`) in both formats, kept by the `.gitignore` exception for `tests/testthat/fixtures/`.

**`[library]` 1.4.0, 2026-10-18.** Acceptance: live, `agg_build(agg_program("Capstone.Gross"))` returns a handle; mocked, a second `agg_program()` sends no request, and an unknown name reads "no library entry named X; agg_library() lists them". `devtools::check()` clean. Divergences:

- **A refused database is not kept,** where the add-in keeps it so a sheet of cells asks once. An R call is explicit, and a retry after a typo should ask again.
- **The library fixture is the first five entries in file order,** captured from the local server as the add-in's `examples-few.json` was.

**`[launcher]` 1.5.0, 2026-10-18.** Acceptance on this machine:

- With an empty uv cache, `agg_start(from = "aggregate-api[parquet] @ git+https://github.com/mynl/aggregate_api")` answered on `127.0.0.1` in 21.8 s cold. A warm start from the checkout (`@ file:///V:/dev/aggregate-api`) took 6.1 s.
- Every R block of the README ran end to end against the warm server.
- `agg_stop()` left no listener on the port.
- Quitting R with the server running left no listener and no `uvx` process.
- Without `from`, uv's "only aggregate-api[parquet]==1.0.0 is available" came back in 2.1 s, followed by the instruction to pass `from`.
- `devtools::check()` clean.

Divergences:

- **A local server runs PyPI's `aggregate` 1.2.0,** whether installed from git or the checkout, because uv resolves the library from PyPI. The public server runs 1.5.2. The same program can therefore get a different id and different numbers (`agg A ...` was `b4f2301771f7c82d` on 1.5.2 and `fee737f2a29ccb3b` on 1.2.0). The plan foresaw this; publishing `aggregate` closes it.
- **`agg_start()` refuses while its own server runs,** and `agg_stop()` restores the previous server only if the session still points at the local one. A user who has since chosen another server keeps it.
- **The uv install line follows the platform:** `winget` on Windows, uv's install script elsewhere.
- **`agg_start()` waits on `/v1/health` before checking whether the process exited,** so a server that answers and exits in the same instant is still caught on the next pass. The wait between polls is the package's mockable `wait()`.
- **There is no live test that launches uv.** The launcher's unit tests stand in for uv and the server, and the acceptance above was run by hand.
- **The plan stays in `dev/`,** not `dev/done/`. The house rules move a plan only when the author says it is done.
