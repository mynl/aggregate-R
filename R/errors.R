# Errors are classed base R conditions, so callers can tryCatch() on the class
# without the package taking a dependency for it. Both classes inherit
# `aggregateR_error`:
#
# - `aggregateR_refusal`: the program or an argument is wrong. Retrying the
#   same call will fail the same way.
# - `aggregateR_transient`: rate limited after the retries, a build timeout,
#   the server unreachable, or a server fault. A later retry may succeed.
#
# The split is the Excel add-in's (`core.ts:isProgramRefusal`): a 4xx other
# than 429 is about the request, everything else is about the moment.

messages <- list(
  unreachable = "server unreachable",
  timeout = "build timed out; lower log2 or simplify the program",
  rate_limited = "rate limited; try again in a minute",
  empty_program = "the program is empty",
  not_a_handle = "expected an agg_handle from agg_build(), or a DecL program",
  program_is_value = paste(
    "this program is a number, not an object; pass a handle from agg_build()",
    "or a program that declares an agg, port, sev or distortion"
  ),
  changed = paste(
    "the program now builds a different object: the server changed, or a name",
    "it uses was redefined in this session; rebuild it with agg_build()"
  )
)

agg_abort <- function(message, class, ...) {
  stop(structure(
    class = c(class, "aggregateR_error", "error", "condition"),
    list(message = message, call = NULL, ...)
  ))
}

abort_refusal <- function(message, ...) {
  agg_abort(message, "aggregateR_refusal", ...)
}

abort_transient <- function(message, ...) {
  agg_abort(message, "aggregateR_transient", ...)
}

# Whether an HTTP status means the request itself was refused.
is_refusal_status <- function(status) {
  status >= 400 && status < 500 && status != 429
}

# The `detail` of a FastAPI error body, or the body itself.
detail_of <- function(body) {
  if (is.list(body) && !is.null(names(body)) && "detail" %in% names(body)) {
    return(body$detail)
  }
  body
}

is_text <- function(x) {
  is.character(x) && length(x) == 1 && !is.na(x) && nzchar(x)
}

#' Readable text for a failed request
#'
#' A port of the Excel add-in's `core.ts:errorMessage`, so a refusal reads the
#' same in R as in a worksheet cell.
#'
#' @param status The HTTP status.
#' @param body The response body, parsed from JSON without simplification, or
#'   the raw text when it was not JSON (a proxy's error page).
#' @return One string.
#' @details
#' - A parse error (an `ErrorReport`) reads `line L, col C: message`.
#' - A structured refusal (`recipe_not_found`, `session_reference`) reads its
#'   own `message`.
#' - A plain string `detail` is shown as it is.
#' - FastAPI's validation errors (a list of `{loc, msg}`) show the first.
#' @noRd
error_message <- function(status, body) {
  if (status == 504) return(messages$timeout)
  if (status == 429) return(messages$rate_limited)
  detail <- detail_of(body)
  if (is.list(detail) && is.null(names(detail)) && length(detail) > 0) {
    first <- detail[[1]]
    if (is.list(first) && is_text(first$msg)) {
      where <- paste(unlist(first$loc), collapse = ".")
      return(if (nzchar(where)) paste0(where, ": ", first$msg) else first$msg)
    }
  }
  if (is.list(detail) && !is.null(names(detail))) {
    if (is.numeric(detail$line) && is.numeric(detail$column) &&
        is.character(detail$message)) {
      return(sprintf("line %d, col %d: %s",
                     as.integer(detail$line), as.integer(detail$column),
                     detail$message))
    }
    if (is_text(detail$message)) return(detail$message)
  }
  if (is_text(detail)) return(detail)
  paste("server answered HTTP", status)
}

# Raise the classed error a failed reply calls for; return the reply otherwise.
stop_for_reply <- function(reply) {
  if (reply$status < 400) return(invisible(reply))
  text <- error_message(reply$status, reply$body)
  if (is_refusal_status(reply$status)) {
    abort_refusal(text, status = reply$status, body = reply$body)
  }
  abort_transient(text, status = reply$status, body = reply$body)
}
