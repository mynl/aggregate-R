# Helpers for tests that need no server. HTTP is mocked with httr2's own
# local_mocked_responses(), so the tests add no dependency.

# A clean package state, with `server` as the current server, for one test.
local_server <- function(server = "http://mock.test", env = parent.frame()) {
  saved_servers <- the$servers
  saved_told <- the$told_public
  the$servers <- new.env(parent = emptyenv())
  the$told_public <- FALSE
  withr::local_options(aggregateR.server = server, .local_envir = env)
  withr::defer({
    the$servers <- saved_servers
    the$told_public <- saved_told
  }, envir = env)
  invisible(server)
}

# A JSON response.
json_reply <- function(body, status = 200, headers = list()) {
  httr2::response(
    status_code = status,
    headers = c(list(`Content-Type` = "application/json"), headers),
    body = charToRaw(enc2utf8(jsonlite::toJSON(body, auto_unbox = TRUE,
                                               null = "null", digits = NA)))
  )
}

# Answer the test's requests with `...`, in order, and record each request.
# A request beyond the last reply fails the test, so a flow that sends more
# requests than it should is caught.
local_replies <- function(..., env = parent.frame()) {
  queue <- list(...)
  log <- new.env(parent = emptyenv())
  log$requests <- list()
  httr2::local_mocked_responses(function(req) {
    log$requests[[length(log$requests) + 1]] <- req
    if (!length(queue)) stop("unexpected request: ", req$method, " ", req$url)
    reply <- queue[[1]]
    queue <<- queue[-1]
    if (is.function(reply)) reply(req) else reply
  }, env = env)
  log
}

# A synthetic fixture under tests/testthat/fixtures, parsed as the client
# parses a reply.
fixture <- function(name) {
  jsonlite::fromJSON(test_path("fixtures", paste0(name, ".json")),
                     simplifyVector = FALSE)
}
