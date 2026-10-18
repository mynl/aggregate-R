test_that("a session id has the documented shape", {
  id <- mint_session_id(as.POSIXct("2026-10-18 12:34:56", tz = "UTC"))
  expect_match(id, "^r-2026-10-18T12:34:56Z-[0-9a-f]{32}$")
  # The server's pattern, ^[A-Za-z0-9:.\-_]{8,200}$, with the hyphen last:
  # R's default regex engine reads `\-_` in a bracket as a range.
  expect_match(id, "^[A-Za-z0-9:._-]{8,200}$")
})

test_that("session ids differ and leave the user's random stream alone", {
  withr::local_seed(1)
  before <- get(".Random.seed", envir = globalenv())
  ids <- replicate(5, mint_session_id())
  expect_identical(get(".Random.seed", envir = globalenv()), before)
  expect_length(unique(ids), 5)
})

test_that("Retry-After is read as seconds or a date, and clamped", {
  now <- as.POSIXct("2026-10-18 12:00:00", tz = "UTC")
  expect_equal(retry_after_seconds("5", now), 5)
  expect_equal(retry_after_seconds(NULL, now), 10)
  expect_equal(retry_after_seconds("soon", now), 10)
  expect_equal(retry_after_seconds("0", now), 1)
  expect_equal(retry_after_seconds("3600", now), 60)
  expect_equal(retry_after_seconds("Sun, 18 Oct 2026 12:00:30 GMT", now), 30)
})

test_that("agg_meta() sends the session header and user agent, and keeps the facts", {
  local_server()
  log <- local_replies(json_reply(list(
    version = "1.26.0", aggregate_version = "1.5.2",
    frame_formats = list("csv", "parquet")
  )))
  meta <- agg_meta()
  expect_equal(meta$version, "1.26.0")
  expect_equal(meta$frame_formats, c("csv", "parquet"))
  expect_length(log$requests, 1)
  req <- log$requests[[1]]
  expect_equal(req$url, "http://mock.test/v1/meta")
  expect_match(req$headers[["X-Aggregate-Session"]], "^r-")
  expect_match(req$options$useragent, "^aggregateR/")
  expect_identical(server_state("http://mock.test")$meta, meta)
})

test_that("each server has its own session id, kept for the R session", {
  local_server()
  a <- server_state("http://one.test")$session
  expect_identical(server_state("http://one.test")$session, a)
  expect_false(identical(server_state("http://two.test")$session, a))
})

test_that("a 429 is retried after its Retry-After", {
  local_server()
  waits <- c()
  local_mocked_bindings(wait = function(seconds) waits <<- c(waits, seconds))
  log <- local_replies(
    json_reply(list(detail = "slow down"), 429, list(`Retry-After` = "2")),
    json_reply(list(version = "1.26.0"))
  )
  expect_equal(agg_meta()$version, "1.26.0")
  expect_length(log$requests, 2)
  expect_equal(waits, 2)
})

test_that("a 429 after three retries is a transient error", {
  local_server()
  local_mocked_bindings(wait = function(seconds) NULL)
  limited <- json_reply(list(detail = "slow down"), 429)
  log <- local_replies(limited, limited, limited, limited)
  expect_error(agg_meta(), "rate limited", class = "aggregateR_transient")
  expect_length(log$requests, 4)
})

test_that("a 4xx is a refusal and a 5xx is transient", {
  local_server()
  local_replies(
    json_reply(list(detail = "nope"), 404),
    json_reply(list(detail = "boom"), 500)
  )
  expect_error(agg_meta(), "nope", class = "aggregateR_refusal")
  expect_error(agg_meta(), "boom", class = "aggregateR_transient")
})

test_that("an unreachable server is a transient error naming it", {
  local_server("http://127.0.0.1:9")
  expect_error(agg_meta(), "server unreachable: http://127.0.0.1:9",
               fixed = TRUE, class = "aggregateR_transient")
})

test_that("the first request to the public server says where programs go, once", {
  local_server("https://agg.mynl.com")
  local_replies(json_reply(list(version = "1")), json_reply(list(version = "1")))
  expect_message(agg_meta(), "programs are sent to https://agg.mynl.com")
  expect_no_message(agg_meta())
})

test_that("a local server draws no message", {
  local_server("http://127.0.0.1:8000")
  local_replies(json_reply(list(version = "1")))
  expect_no_message(agg_meta())
})
