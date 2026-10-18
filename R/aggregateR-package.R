#' @keywords internal
#' @details
#' `aggregateR` puts the `aggregate` actuarial library in R by talking over
#' HTTP to `aggregate-api`. R never hosts Python: the package is a thin client
#' and the API is its contract.
#'
#' **Where your programs go.** By default the client talks to the public
#' server, `https://agg.mynl.com`, and every program it builds is sent there.
#' For real data, [agg_start()] runs a private server on your own machine, or
#' [agg_server()] points at one you run yourself.
"_PACKAGE"

# Package state for this R session. `servers` holds one environment per server
# URL, created on first use by `server_state()`, so the session id, caches and
# build log of one server never leak into another's.
the <- new.env(parent = emptyenv())
the$servers <- new.env(parent = emptyenv())
the$told_public <- FALSE
# The server agg_start() runs, while it runs.
the$local <- NULL
