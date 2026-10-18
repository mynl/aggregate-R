# The launcher with uv and the server stood in for: `launch()` returns a fake
# process and `healthy()` answers as told, so these tests need neither.

fake_process <- function(alive = TRUE) {
  process <- new.env()
  process$killed <- FALSE
  process$is_alive <- function() alive && !process$killed
  process$kill_tree <- function() process$killed <- TRUE
  process
}

local_launcher <- function(env = parent.frame()) {
  saved <- the$local
  the$local <- NULL
  withr::defer(the$local <- saved, envir = env)
  withr::local_options(aggregateR.server = "http://before.test", .local_envir = env)
}

test_that("agg_start() runs uvx on 127.0.0.1 and points the session at it", {
  local_launcher()
  process <- fake_process()
  seen <- NULL
  local_mocked_bindings(
    find_uvx = function() "uvx",
    launch = function(command, args, log) {
      seen <<- args
      process
    },
    healthy = function(url) TRUE
  )
  expect_message(url <- agg_start(port = 23456, from = "aggregate-api @ file:///checkout"),
                 "running at http://127.0.0.1:23456")
  expect_equal(url, "http://127.0.0.1:23456")
  expect_equal(seen, c("--from", "aggregate-api @ file:///checkout", "aggregate-api",
                       "--host", "127.0.0.1", "--port", "23456"))
  expect_equal(agg_server(), "http://127.0.0.1:23456")
  expect_equal(agg_stop(), "http://127.0.0.1:23456")
  expect_true(process$killed)
  expect_equal(agg_server(), "http://before.test")
})

test_that("without from, uv is asked for the release floor", {
  local_launcher()
  seen <- NULL
  local_mocked_bindings(
    find_uvx = function() "uvx",
    launch = function(command, args, log) {
      seen <<- args
      fake_process()
    },
    healthy = function(url) TRUE
  )
  suppressMessages(agg_start(port = 23456))
  expect_equal(seen[2], "aggregate-api[parquet]>=1.26")
  agg_stop()
})

test_that("without uv, agg_start() gives the install line", {
  local_launcher()
  local_mocked_bindings(find_uvx = function() "")
  expect_error(agg_start(), uv_install_line(), fixed = TRUE, class = "aggregateR_refusal")
})

test_that("a server that stops early reports its log, and asks for from when none was given", {
  local_launcher()
  local_mocked_bindings(
    find_uvx = function() "uvx",
    launch = function(command, args, log) {
      writeLines(c("Resolving dependencies", "No solution found when resolving tool dependencies"), log)
      fake_process(alive = FALSE)
    },
    healthy = function(url) FALSE
  )
  expect_error(agg_start(port = 23456), "No solution found", class = "aggregateR_transient")
  expect_error(agg_start(port = 23456), "pass `from`", fixed = TRUE)
  err <- tryCatch(agg_start(port = 23456, from = "aggregate-api"), error = function(e) e)
  expect_false(grepl("pass `from`", conditionMessage(err), fixed = TRUE))
  expect_null(the$local)
  expect_equal(agg_server(), "http://before.test")
})

test_that("a second agg_start() is refused while one runs", {
  local_launcher()
  local_mocked_bindings(find_uvx = function() "uvx", launch = function(...) fake_process(),
                        healthy = function(url) TRUE)
  suppressMessages(agg_start(port = 23456))
  expect_error(agg_start(), "already running at http://127.0.0.1:23456",
               class = "aggregateR_refusal")
  agg_stop()
})

test_that("agg_stop() leaves alone a server chosen since agg_start()", {
  local_launcher()
  local_mocked_bindings(find_uvx = function() "uvx", launch = function(...) fake_process(),
                        healthy = function(url) TRUE)
  suppressMessages(agg_start(port = 23456))
  agg_server("http://other.test")
  agg_stop()
  expect_equal(agg_server(), "http://other.test")
})

test_that("agg_stop() with nothing running says so", {
  local_launcher()
  expect_message(expect_null(agg_stop()), "no local server is running")
})

test_that("ports are checked, and drawn from 20000 to 39999", {
  local_launcher()
  expect_error(agg_start(port = 70000), "between 1 and 65535", class = "aggregateR_refusal")
  expect_error(agg_start(port = "8000"), class = "aggregateR_refusal")
  ports <- replicate(200, random_port())
  expect_true(all(ports >= 20000 & ports <= 39999))
  expect_gt(length(unique(ports)), 150)
})
