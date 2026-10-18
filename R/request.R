# HTTP to aggregate-api. Two layers, as in the Excel add-in's `request()`:
#
# - `agg_send()` performs one request, retrying a 429, and returns the
#   response whatever its status. Only a failure to reach the server raises.
# - `agg_request()` reads the reply and raises the classed error a failed one
#   calls for. Most routes need nothing more.
#
# Recovery (rebuilding an evicted object, replaying a lost declaration) sits
# above these, where the handle and the build log are in reach.

# How many times a 429 is retried before the call gives up, as in the add-in.
rate_limit_retries <- 3

# How long one request may take, in seconds. The server caps a build at its
# own `build_timeout_s` (10 s on the public server); the slack is for a whole
# frame at log2 18 on a slow line.
request_timeout <- 300

#' Mint a session id
#'
#' The server keys a private recipe base on the session id: the names this R
#' session declares (`agg A ...`) resolve in later programs (`port P agg.A
#' ...`) under the same id. Anyone holding the id can read those programs back,
#' so it carries 128 random bits from OpenSSL, through httr2, rather than from
#' R's generator: that leaves the user's `.Random.seed` alone, and two sessions
#' that both called `set.seed(1)` still get different ids.
#'
#' @param now The time stamped into the id.
#' @return `r-<ISO 8601 UTC>-<32 hex>`, which matches the server's
#'   `^[A-Za-z0-9:.\-_]{8,200}$`.
#' @noRd
mint_session_id <- function(now = Sys.time()) {
  stamp <- format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  paste0("r-", stamp, "-", random_hex())
}

# 32 hex characters of cryptographic randomness.
random_hex <- function() {
  bytes <- jsonlite::base64url_dec(httr2::secret_make_key())
  paste(as.character(bytes), collapse = "")
}

#' Seconds to wait before retrying a 429
#'
#' A port of `core.ts:retryAfterSeconds`. `Retry-After` may be a count of
#' seconds or an HTTP date; anything unreadable waits `fallback`. The result
#' is clamped to between 1 and 60 seconds, so a misconfigured proxy cannot
#' park a call for an hour.
#'
#' @param header The `Retry-After` header, or `NULL`.
#' @param now The current time.
#' @param fallback Seconds to wait when the header is missing or unreadable.
#' @return Whole seconds.
#' @noRd
retry_after_seconds <- function(header, now = Sys.time(), fallback = 10) {
  seconds <- fallback
  if (is_text(header)) {
    count <- suppressWarnings(as.numeric(header))
    if (is.finite(count)) {
      seconds <- count
    } else {
      when <- parse_http_date(header)
      if (!is.na(when)) seconds <- as.numeric(difftime(when, now, units = "secs"))
    }
  }
  min(60, max(1, ceiling(seconds)))
}

# An HTTP date, "Sun, 18 Oct 2026 12:00:30 GMT", as a POSIXct; NA otherwise.
# Parsed by hand because strptime's %b reads month names in the user's locale,
# and HTTP dates are English everywhere.
parse_http_date <- function(text) {
  parts <- regmatches(text, regexec(
    "^[A-Za-z]{3}, ([0-9]{2}) ([A-Za-z]{3}) ([0-9]{4}) ([0-9:]{8}) GMT$", text
  ))[[1]]
  month <- match(parts[3], month.abb)
  if (length(parts) != 5 || is.na(month)) return(NA)
  as.POSIXct(sprintf("%s-%02d-%s %s", parts[4], month, parts[2], parts[5]),
             tz = "UTC")
}

# Sleep between retries. A function of its own so tests can mock it away.
wait <- function(seconds) {
  Sys.sleep(seconds)
}

# Perform one request against `server`, retrying a 429; return the response.
agg_send <- function(method, path, body = NULL, query = NULL,
                     server = current_server()) {
  state <- server_state(server)
  tell_public(server)
  req <- httr2::request(paste0(server, path))
  req <- httr2::req_method(req, method)
  if (length(query)) req <- do.call(httr2::req_url_query, c(list(req), query))
  req <- httr2::req_headers(req, `X-Aggregate-Session` = state$session)
  req <- httr2::req_user_agent(
    req, paste0("aggregateR/", utils::packageVersion("aggregateR"))
  )
  if (!is.null(body)) req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  req <- httr2::req_timeout(req, request_timeout)
  for (attempt in 0:rate_limit_retries) {
    resp <- tryCatch(
      httr2::req_perform(req),
      httr2_failure = function(e) {
        abort_transient(paste0(messages$unreachable, ": ", server), parent = e)
      }
    )
    if (httr2::resp_status(resp) != 429 || attempt == rate_limit_retries) break
    wait(retry_after_seconds(httr2::resp_header(resp, "Retry-After")))
  }
  resp
}

# A response's status and body. A JSON body is parsed: without simplification
# for an error, which `error_message()` reads, and as `simplify` asks for a
# success. Anything else stays text.
reply_of <- function(resp, simplify = FALSE) {
  status <- httr2::resp_status(resp)
  text <- if (httr2::resp_has_body(resp)) httr2::resp_body_string(resp) else ""
  body <- NULL
  if (nzchar(text)) {
    simplify <- simplify && status < 400
    body <- tryCatch(
      jsonlite::fromJSON(text, simplifyVector = simplify,
                         simplifyDataFrame = FALSE, simplifyMatrix = FALSE),
      error = function(e) text
    )
  }
  list(status = status, body = body)
}

#' One request to the server
#'
#' Sends the session header and the package's user agent, retries a 429 up to
#' three times honoring `Retry-After`, and turns a failure into a classed
#' error carrying readable text.
#'
#' @param method `"GET"`, `"POST"` or `"DELETE"`.
#' @param path The path under the server, starting `/v1/`.
#' @param body A list sent as JSON, or `NULL`.
#' @param query A named list of query parameters.
#' @param server The server's address.
#' @param simplify Whether to simplify JSON arrays to vectors.
#' @return The parsed body.
#' @noRd
agg_request <- function(method, path, body = NULL, query = NULL,
                        server = current_server(), simplify = FALSE) {
  reply <- reply_of(agg_send(method, path, body, query, server), simplify)
  stop_for_reply(reply)
  reply$body
}
