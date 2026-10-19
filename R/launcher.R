# A private local server: aggregate-api run through uv, on 127.0.0.1 only.

# What uv installs when `from` is not given. The floor is the first release
# with every route this client uses, so uv never quietly runs an older one.
default_from <- "aggregate-api[parquet]>=1.26"

# The first run downloads numpy, scipy and the rest, so allow for it.
start_timeout <- 180

#' Run a private local server
#'
#' Starts `aggregate-api` on this machine and points the R session at it, so
#' no program leaves the machine.
#'
#' @param port The port. `NULL` picks a random one between 20000 and 39999.
#' @param from What uv installs, passed to `uvx --from` as it is: a
#'   requirement such as the default, `"aggregate-api[parquet]>=1.26"`, or a
#'   git or local checkout, such as
#'   `"aggregate-api[parquet] @ git+https://github.com/mynl/aggregate_api"`.
#' @return The server's address, invisibly.
#' @details
#' Needs [uv](https://docs.astral.sh/uv/), whose `uvx` runs a Python tool in
#' an environment of its own: nothing is installed into any Python you have.
#' The first start downloads the server and its numerical libraries, which can
#' take a couple of minutes; later starts reuse uv's cache.
#'
#' The server binds `127.0.0.1` only. It runs until [agg_stop()] or the end of
#' the R session, and its output goes to a log file under [tempdir()].
#'
#' A local server builds with whatever release of the `aggregate` library uv
#' installs, which can differ from the public server's, so the same program
#' can differ between the two; [agg_meta()] shows both versions. Like any
#' `aggregate-api`, it keeps an audit record of the programs it builds, here
#' on your own machine under `~/.aggregate/api/`.
#' @examplesIf interactive()
#' agg_start()
#' agg_build("agg A 10 claims sev lognorm 10 cv 1 poisson")
#' agg_stop()
#' @export
agg_start <- function(port = NULL, from = NULL) {
  if (!is.null(the$local)) {
    abort_refusal(paste0("a local server is already running at ", the$local$url,
                         "; agg_stop() stops it"))
  }
  if (is.null(port)) port <- random_port()
  if (!is.numeric(port) || length(port) != 1 || is.na(port) || port != round(port) ||
      port < 1 || port > 65535) {
    abort_refusal("port must be one whole number between 1 and 65535")
  }
  if (!is.null(from) && !is_text(from)) abort_refusal("from must be one uv requirement")
  uvx <- find_uvx()
  if (!nzchar(uvx)) abort_refusal(paste("agg_start() needs uv; install it with:", uv_install_line()))
  url <- paste0("http://127.0.0.1:", format(port, scientific = FALSE))
  log <- tempfile("aggregate-api-", fileext = ".log")
  args <- c("--from", if (is.null(from)) default_from else from, "aggregate-api",
            "--host", "127.0.0.1", "--port", format(port, scientific = FALSE))
  process <- launch(uvx, args, log)
  deadline <- Sys.time() + start_timeout
  repeat {
    if (healthy(url)) break
    if (!process$is_alive()) {
      text <- paste0("the local server stopped before it answered; the end of its log:\n",
                     log_tail(log))
      abort_transient(text)
    }
    if (Sys.time() > deadline) {
      process$kill_tree()
      abort_transient(paste0("the local server did not answer within ", start_timeout,
                             " s; its log is ", log))
    }
    wait(0.5)
  }
  the$local <- list(process = process, url = url, log = log,
                    previous = getOption("aggregateR.server"))
  options(aggregateR.server = url)
  message("aggregate-api is running at ", url, "; agg_stop() stops it")
  invisible(url)
}

#' Stop the local server
#'
#' Stops the server [agg_start()] started and restores the server that was
#' current before it, unless the session has since been pointed elsewhere.
#'
#' @return The stopped server's address, invisibly, or `NULL` when none was
#'   running.
#' @examplesIf interactive()
#' agg_stop()
#' @export
agg_stop <- function() {
  local <- the$local
  if (is.null(local)) {
    message("no local server is running")
    return(invisible(NULL))
  }
  # The whole tree: uvx starts Python as a child, which holds the port.
  local$process$kill_tree()
  the$local <- NULL
  if (identical(getOption("aggregateR.server"), local$url)) {
    options(aggregateR.server = local$previous)
  }
  invisible(local$url)
}

# Functions of their own so tests can stand in for uv and the server.
find_uvx <- function() {
  unname(Sys.which("uvx"))
}

launch <- function(command, args, log) {
  processx::process$new(command, args, stdout = log, stderr = "2>&1",
                        cleanup_tree = TRUE)
}

healthy <- function(url) {
  req <- httr2::request(paste0(url, "/v1/health"))
  req <- httr2::req_timeout(req, 2)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  isTRUE(tryCatch(httr2::resp_status(httr2::req_perform(req)) == 200,
                  error = function(e) FALSE))
}

uv_install_line <- function() {
  if (.Platform$OS.type == "windows") {
    "winget install astral-sh.uv"
  } else {
    "curl -LsSf https://astral.sh/uv/install.sh | sh"
  }
}

log_tail <- function(log, lines = 20) {
  text <- tryCatch(readLines(log, warn = FALSE), error = function(e) character())
  paste(utils::tail(text, lines), collapse = "\n")
}

# A port in 20000 to 39999, drawn without touching the user's random stream.
random_port <- function() {
  bytes <- as.integer(jsonlite::base64url_dec(httr2::secret_make_key()))
  20000L + (bytes[1] * 256L + bytes[2]) %% 20000L
}
