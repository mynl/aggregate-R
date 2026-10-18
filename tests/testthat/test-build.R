agg_a <- "agg A 10 claims sev lognorm 10 cv 1 poisson"
port_p <- "port P agg.A agg.Capstone.Gross"

posted <- function(log) {
  vapply(log$requests, function(r) {
    if (identical(r$method, "POST")) r$body$data$decl else paste("GET", r$url)
  }, "")
}

test_that("agg_build() returns a handle carrying its recipe and server", {
  local_server()
  local_replies(json_reply(fixture("build-agg-a")))
  a <- agg_build(agg_a)
  expect_s3_class(a, "agg_handle")
  expect_equal(c(a$kind, a$name), c("agg", "A"))
  expect_match(a$id, "^[0-9a-f]{16}$")
  expect_equal(a$recipe, list(decl = agg_a, log2 = NULL, bs = NULL))
  expect_equal(a$server, "http://mock.test")
  expect_equal(a$log2, 16)
})

test_that("a build sends the program and only the grid asked for", {
  local_server()
  log <- local_replies(json_reply(fixture("build-agg-a")),
                       json_reply(fixture("build-agg-a")))
  agg_build(agg_a)
  agg_build(agg_a, log2 = 10)
  expect_equal(names(log$requests[[1]]$body$data), "decl")
  expect_equal(log$requests[[2]]$body$data[c("decl", "log2")],
               list(decl = agg_a, log2 = 10))
})

test_that("the same program twice makes one POST", {
  local_server()
  log <- local_replies(json_reply(fixture("build-agg-a")))
  expect_identical(agg_build(agg_a), agg_build(agg_a))
  expect_length(log$requests, 1)
})

test_that("a character vector joins into one program", {
  local_server()
  log <- local_replies(json_reply(fixture("build-agg-a")))
  agg_build(c("agg A 10 claims", "", "sev lognorm 10 cv 1 poisson", NA))
  expect_equal(log$requests[[1]]$body$data$decl,
               "agg A 10 claims\nsev lognorm 10 cv 1 poisson")
})

test_that("a value program returns its number, and is refused in place of a handle", {
  local_server()
  log <- local_replies(json_reply(fixture("build-value")))
  expect_equal(agg_build("(2+2)"), 4)
  expect_error(as_handle("(2+2)"), "is a number", class = "aggregateR_refusal")
  expect_length(log$requests, 1)
})

test_that("a parse error is a refusal reading line and column", {
  local_server()
  local_replies(json_reply(fixture("refusal-parse"), 422))
  expect_error(agg_build("agg A 10 claims sev lognorm 10 cv 1 poison"),
               "line 1, col 37: Unexpected 'poison'.", fixed = TRUE,
               class = "aggregateR_refusal")
})

test_that("bad arguments are refused without a request", {
  local_server()
  log <- local_replies()
  expect_error(agg_build(c("", "  ")), "empty", class = "aggregateR_refusal")
  expect_error(agg_build(agg_a, log2 = "16"), "log2 must be one number",
               class = "aggregateR_refusal")
  expect_error(agg_build(agg_a, bs = c(1, 2)), "bs must be one number",
               class = "aggregateR_refusal")
  expect_error(as_handle(42), "expected an agg_handle", class = "aggregateR_refusal")
  expect_length(log$requests, 0)
})

test_that("a 429 on a build is retried", {
  local_server()
  local_mocked_bindings(wait = function(seconds) NULL)
  log <- local_replies(json_reply(list(detail = "slow down"), 429),
                       json_reply(fixture("build-agg-a")))
  expect_s3_class(agg_build(agg_a), "agg_handle")
  expect_length(log$requests, 2)
})

test_that("a lost object is rebuilt under the same id, then the read retried", {
  local_server()
  log <- local_replies(
    json_reply(fixture("build-agg-a")),
    json_reply(fixture("missing-object"), 404),
    json_reply(fixture("build-agg-a")),
    json_reply(list(ok = TRUE))
  )
  a <- agg_build(agg_a)
  expect_equal(httr2::resp_status(read_object(a, "/v1/objects/%s")), 200)
  expect_equal(posted(log), c(agg_a, paste0("GET http://mock.test/v1/objects/", a$id),
                              agg_a, paste0("GET http://mock.test/v1/objects/", a$id)))
})

test_that("a rebuild to a different id clears the memo and refuses", {
  local_server()
  moved <- fixture("build-agg-a")
  moved$id <- "ffffffffffffffff"
  log <- local_replies(
    json_reply(fixture("build-agg-a")),
    json_reply(fixture("missing-object"), 404),
    json_reply(moved),
    json_reply(moved)
  )
  a <- agg_build(agg_a)
  expect_error(read_object(a, "/v1/objects/%s"), "builds a different object",
               class = "aggregateR_refusal")
  expect_length(log$requests, 3)
  expect_length(server_state("http://mock.test")$memo, 0)
  expect_equal(agg_build(agg_a)$id, "ffffffffffffffff")
  expect_length(log$requests, 4)
})

test_that("a lost declaration is replayed, then the build retried", {
  local_server()
  log <- local_replies(
    json_reply(fixture("build-agg-a")),
    json_reply(fixture("refusal-recipe-not-found"), 422),
    json_reply(fixture("build-agg-a")),
    json_reply(fixture("build-port-p"))
  )
  agg_build(agg_a)
  expect_equal(agg_build(port_p)$kind, "port")
  expect_equal(posted(log), c(agg_a, port_p, agg_a, port_p))
})

test_that("after a restart, a read rebuilds the object and replays what it names", {
  local_server()
  log <- local_replies(
    json_reply(fixture("build-agg-a")),
    json_reply(fixture("build-port-p")),
    json_reply(fixture("missing-object"), 404),
    json_reply(fixture("refusal-recipe-not-found"), 422),
    json_reply(fixture("build-agg-a")),
    json_reply(fixture("build-port-p")),
    json_reply(list(ok = TRUE))
  )
  agg_build(agg_a)
  p <- agg_build(port_p)
  expect_equal(httr2::resp_status(read_object(p, "/v1/objects/%s")), 200)
  get_p <- paste0("GET http://mock.test/v1/objects/", p$id)
  expect_equal(posted(log), c(agg_a, port_p, get_p, port_p, agg_a, port_p, get_p))
})

test_that("a name the log does not hold is refused with the server's message", {
  local_server()
  log <- local_replies(json_reply(fixture("refusal-recipe-not-found"), 422))
  expect_error(agg_build(port_p), "no recipe named 'A' of kind 'agg'",
               class = "aggregateR_refusal")
  expect_length(log$requests, 1)
})

test_that("replays stop at the limit", {
  local_server()
  lost <- json_reply(fixture("refusal-recipe-not-found"), 422)
  log <- do.call(local_replies, c(list(json_reply(fixture("build-agg-a"))),
                                  rep(list(lost), 11)))
  agg_build(agg_a)
  expect_error(agg_build(port_p), "no recipe named", class = "aggregateR_refusal")
  # The program itself, then one POST per replay.
  expect_length(log$requests, 1 + 1 + replay_limit)
})

test_that("a redefinition clears the memo, so a program naming it builds again", {
  local_server()
  a2 <- fixture("build-agg-a")
  a2$id <- "aaaaaaaaaaaaaaaa"
  p2 <- fixture("build-port-p")
  p2$id <- "bbbbbbbbbbbbbbbb"
  log <- local_replies(json_reply(fixture("build-agg-a")), json_reply(fixture("build-port-p")),
                       json_reply(a2), json_reply(p2))
  agg_build(agg_a)
  first <- agg_build(port_p)
  agg_build("agg A 20 claims sev lognorm 10 cv 1 poisson")
  second <- agg_build(port_p)
  expect_length(log$requests, 4)
  expect_equal(second$id, "bbbbbbbbbbbbbbbb")
  expect_false(identical(first$id, second$id))
})

test_that("building a name to the same id keeps the memo", {
  local_server()
  log <- local_replies(json_reply(fixture("build-agg-a")), json_reply(fixture("build-port-p")),
                       json_reply(fixture("build-agg-a")))
  agg_build(agg_a)
  agg_build(port_p)
  agg_build(paste(agg_a, " "))
  agg_build(port_p)
  expect_length(log$requests, 3)
})

test_that("the log keeps each recipe once, newest last, and at most 500", {
  state <- new.env()
  state$memo <- list()
  state$built <- list()
  state$log <- list()
  handle <- function(decl) {
    new_handle(list(id = "0000000000000001", kind = "agg", name = "A"),
               decl, NULL, NULL, "http://mock.test")
  }
  record_build(state, handle("one"))
  record_build(state, handle("two"))
  record_build(state, handle("one"))
  expect_equal(vapply(state$log, `[[`, "", "decl"), c("two", "one"))
  for (i in 1:510) record_build(state, handle(paste("program", i)))
  expect_length(state$log, log_limit)
  expect_equal(state$log[[log_limit]]$decl, "program 510")
})

test_that("a handle prints its name, id, server, grid and moments", {
  local_server()
  local_replies(json_reply(fixture("build-agg-a")))
  expect_snapshot(print(agg_build(agg_a)))
})

test_that("a handle saved with saveRDS() reads in a later R session", {
  local_server()
  local_replies(json_reply(fixture("build-agg-a")))
  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(agg_build(agg_a), path)
  # A later session: no state, and a different current server.
  local_server("http://elsewhere.test")
  log <- local_replies(json_reply(fixture("missing-object"), 404),
                       json_reply(fixture("build-agg-a")), json_reply(list(ok = TRUE)))
  a <- readRDS(path)
  expect_equal(httr2::resp_status(read_object(a, "/v1/objects/%s")), 200)
  urls <- vapply(log$requests, function(r) r$url, "")
  expect_true(all(startsWith(urls, "http://mock.test/")))
})
