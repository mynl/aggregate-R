test_that("a parse error reads line, column and message", {
  body <- list(detail = list(line = 1, column = 37, got = "poison",
                             message = "Unexpected 'poison'."))
  expect_equal(error_message(422, body), "line 1, col 37: Unexpected 'poison'.")
})

test_that("a structured refusal reads its own message", {
  body <- list(detail = list(error = "recipe_not_found", kind = "agg",
                             name = "Nope",
                             message = "no recipe named 'Nope' of kind 'agg'"))
  expect_equal(error_message(422, body), "no recipe named 'Nope' of kind 'agg'")
})

test_that("a plain string detail is shown as it is", {
  body <- list(detail = "object 4f40714271198d8f not in cache")
  expect_equal(error_message(404, body), "object 4f40714271198d8f not in cache")
})

test_that("FastAPI validation errors show the first, with its location", {
  body <- list(detail = list(
    list(loc = list("body", "log2"), msg = "Input should be greater than or equal to 4"),
    list(loc = list("body", "bs"), msg = "second")
  ))
  expect_equal(error_message(422, body),
               "body.log2: Input should be greater than or equal to 4")
})

test_that("a timeout and a rate limit read the add-in's words", {
  expect_equal(error_message(504, list(detail = "build timeout")),
               "build timed out; lower log2 or simplify the program")
  expect_equal(error_message(429, NULL), "rate limited; try again in a minute")
})

test_that("a reply with nothing readable names the status", {
  expect_equal(error_message(502, NULL), "server answered HTTP 502")
  expect_equal(error_message(500, list(detail = list())), "server answered HTTP 500")
})

test_that("a 4xx is a refusal, and a 429 or a 5xx is transient", {
  refused <- list(status = 422, body = list(detail = "bad p"))
  expect_error(stop_for_reply(refused), class = "aggregateR_refusal")
  expect_error(stop_for_reply(refused), class = "aggregateR_error")
  expect_error(stop_for_reply(list(status = 429, body = NULL)),
               class = "aggregateR_transient")
  expect_error(stop_for_reply(list(status = 503, body = NULL)),
               class = "aggregateR_transient")
  expect_invisible(stop_for_reply(list(status = 200, body = list())))
})

test_that("an error carries the status and body", {
  err <- tryCatch(stop_for_reply(list(status = 422, body = list(detail = "bad p"))),
                  aggregateR_refusal = function(e) e)
  expect_equal(err$status, 422)
  expect_equal(err$body$detail, "bad p")
  expect_equal(conditionMessage(err), "bad p")
})
