test_that("agg_library() lists name and kind in file order", {
  local_server()
  log <- local_replies(json_reply(fixture("examples-few")))
  df <- agg_library()
  expect_equal(names(df), c("name", "kind"))
  expect_equal(df$name, c("BasicBook", "DiceOneDie", "DiceOneDie.Sev", "DiceTwoDice",
                          "DiceThreeEvenDice"))
  expect_equal(log$requests[[1]]$url, "http://mock.test/v1/examples")
})

test_that("agg_program() returns the entry's program as its file spells it", {
  local_server()
  local_replies(json_reply(fixture("examples-few")))
  program <- agg_program("BasicBook")
  expect_true(startsWith(program, "agg BasicBook\n"))
})

test_that("the listing is fetched once per server and database", {
  local_server()
  log <- local_replies(json_reply(fixture("examples-few")),
                       json_reply(fixture("examples-few")))
  agg_program("BasicBook")
  agg_program("DiceTwoDice")
  agg_library()
  expect_length(log$requests, 1)
  agg_library("decl-testers")
  expect_length(log$requests, 2)
  expect_equal(log$requests[[2]]$url, "http://mock.test/v1/examples?database=decl-testers")
})

test_that("an unknown name says so and points at agg_library()", {
  local_server()
  local_replies(json_reply(fixture("examples-few")))
  for (miss in c("basicbook", "DiceOneDie.", "Nope")) {
    expect_error(agg_program(miss),
                 paste0("no library entry named ", miss, "; agg_library() lists them"),
                 fixed = TRUE, class = "aggregateR_refusal")
  }
})

test_that("an unknown database is the server's refusal, and is not kept", {
  local_server()
  log <- local_replies(json_reply(list(detail = "no database 'nope'"), 422),
                       json_reply(fixture("examples-few")))
  expect_error(agg_library("nope"), "no database 'nope'", class = "aggregateR_refusal")
  expect_equal(nrow(agg_library("nope")), 5)
})

test_that("bad arguments are refused without a request", {
  local_server()
  log <- local_replies()
  expect_error(agg_program(NA), class = "aggregateR_refusal")
  expect_error(agg_library(c("a", "b")), class = "aggregateR_refusal")
  expect_length(log$requests, 0)
})
