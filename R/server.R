public_server <- "https://agg.mynl.com"

#' Get or set the server
#'
#' Every request goes to one `aggregate-api` server. `agg_server()` reports
#' which, and `agg_server(url)` changes it for the rest of the R session.
#'
#' @param url The server's address, such as `"http://127.0.0.1:8000"`. `NULL`
#'   clears the setting, so the environment variable or the default applies
#'   again.
#' @return With no argument, the current server's address. With `url`, the
#'   previous address, invisibly, so it can be restored later.
#' @details
#' The server is the first of:
#'
#' 1. the R option `aggregateR.server`, which `agg_server(url)` sets;
#' 2. the environment variable `AGGREGATER_SERVER`, for `.Renviron`;
#' 3. the public server, `https://agg.mynl.com`.
#'
#' **Your programs are your data.** Everything sent to the public server has
#' left your machine: it builds each program you send and keeps an audit
#' record of it. For real work, run a server on your own machine and point
#' `agg_server()` at it.
#'
#' A handle remembers the server that built it, so changing the server later
#' does not redirect reads through an existing handle.
#' @examples
#' agg_server()
#' agg_server("http://127.0.0.1:8000")
#' agg_server()
#' agg_server(NULL)
#' @export
agg_server <- function(url) {
  if (missing(url)) return(current_server())
  old <- current_server()
  options(aggregateR.server = if (is.null(url)) NULL else normalize_server(url))
  invisible(old)
}

current_server <- function() {
  url <- getOption("aggregateR.server")
  if (!is_text(url)) url <- Sys.getenv("AGGREGATER_SERVER")
  if (!is_text(url)) url <- public_server
  normalize_server(url)
}

normalize_server <- function(url) {
  if (!is_text(url) || !grepl("^https?://", url)) {
    abort_refusal("the server must be one http:// or https:// address")
  }
  sub("/+$", "", url)
}

# This R session's state for one server, created on first use.
server_state <- function(server) {
  state <- the$servers[[server]]
  if (is.null(state)) {
    state <- new.env(parent = emptyenv())
    state$session <- mint_session_id()
    state$meta <- NULL
    # The client-side cache; see build.R.
    state$memo <- list()
    state$built <- list()
    state$log <- list()
    assign(server, state, envir = the$servers)
  }
  state
}

# Say once per R session that programs are going to the public server.
tell_public <- function(server) {
  if (identical(server, public_server) && !the$told_public) {
    the$told_public <- TRUE
    message("programs are sent to ", public_server,
            "; agg_server() selects a private server.")
  }
}
