# aggregateR

`aggregateR` puts the [`aggregate`](https://github.com/mynl/aggregate) actuarial library in R. You write a program in DecL, the library's language for compound loss distributions, build it on an [`aggregate-api`](https://github.com/mynl/aggregate_api) server, and read back exhibits, quantiles and whole frames as data frames. R never hosts Python: the package talks HTTP to the server, through the same API the aggregate Excel add-in uses.

## Install

```r
pak::pak("mynl/aggregate-R")
```

The package is pure R and needs R 4.1 or later. On Windows it needs no Rtools.

## Choose a server

**Your programs are your data.** By default the package talks to the public server, `https://agg.mynl.com`, which builds every program you send it and keeps an audit record of each. For real work, run `aggregate-api` on your own machine and point the package at it.

```r
library(aggregateR)
agg_server()                          # the current server
agg_server("http://127.0.0.1:8000")   # a local server, for the rest of this R session
```

To make the choice stick, set `AGGREGATER_SERVER` in `.Renviron`.

## Server facts

```r
meta <- agg_meta()
meta$version            # the server's version
meta$aggregate_version  # the library's version
meta$log2_cap           # the largest grid the server builds
```

## Build

`agg_build()` sends a DecL program to the server and returns a handle:

```r
a <- agg_build("agg A 10 claims sev lognorm 10 cv 1 poisson")
a
#> <agg_handle> agg.A #b4f2301771f7c82d
#>   server      http://127.0.0.1:8000
#>   grid        log2 16, bs 0.03125
#>   mean, cv    100, 0.447
#>   validation  not unreasonable
agg_build("(2+2)")   # a program that evaluates to a number returns it
#> [1] 4
```

- **The same program on the same grid is sent once per R session.** Building it again returns the handle without a request.
- **A program can name your earlier declarations:** `agg_build("port P agg.A agg.Capstone.Gross")`. If the server restarts and forgets `A`, the client builds `A` again and retries.
- **Handles persist.** A handle carries its program and server, so one saved with `saveRDS()` works in a later R session. If the server has dropped the object, the next read rebuilds it.

## Exhibits and quantiles

Every function below takes a handle, or a program in its place: a program is built first, on the server's default grid, and the memo means passing the same program again costs no build.

```r
agg_exhibits(a)                  # name, title, perspectives
ex <- agg_exhibit(a, "summary")
ex$title                         # "Summary: A"
ex$captions                      # one caption per block, named by block key
ex$tables$summary_df             # a data.frame: row labels as text, values as raw numbers
ex                               # prints the title, then each block's caption and table
agg_q(a, c(0.5, 0.99, 0.995))    # exact grid quantiles, named "50%", "99%", "99.5%"
```

`agg_exhibit()` always returns a list, whether the exhibit has one block or several. The tables hold data only: the server's display formatting is dropped, a label spanning rows is repeated down each row, and header levels join into column names such as `occ Gross`.

## Whole frames

```r
agg_frames(a)                    # name, rows, columns of every frame the object has
density <- agg_frame(a)          # density_df, every row and column, as a data.frame
```

When the server offers Parquet, frames arrive as Parquet, bit-exact and fast: 65,536 rows by 33 columns read in 0.06 s from a local server, against 5.5 s through CSV. Otherwise they arrive as CSV.

## Errors

Every error the package raises inherits `aggregateR_error`, so `tryCatch()` can select by class:

- `aggregateR_refusal`: the program or an argument is wrong. A parse error reads `line L, col C: message`.
- `aggregateR_transient`: the server was unreachable, timed out, faulted, or kept rate limiting after three retries. A later retry may succeed.
