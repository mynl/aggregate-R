test_that("the server comes from the option, then the environment, then the default", {
  withr::local_options(aggregateR.server = NULL)
  withr::local_envvar(AGGREGATER_SERVER = "")
  expect_equal(agg_server(), "https://agg.mynl.com")
  withr::local_envvar(AGGREGATER_SERVER = "http://127.0.0.1:9000/")
  expect_equal(agg_server(), "http://127.0.0.1:9000")
  expect_equal(agg_server("http://127.0.0.1:8000"), "http://127.0.0.1:9000")
  expect_equal(agg_server(), "http://127.0.0.1:8000")
  agg_server(NULL)
  expect_equal(agg_server(), "http://127.0.0.1:9000")
})

test_that("setting the server returns the previous one invisibly", {
  withr::local_options(aggregateR.server = "http://one.test")
  expect_invisible(agg_server("http://two.test"))
  expect_equal(agg_server(), "http://two.test")
})

test_that("a server must be one http address", {
  withr::local_options(aggregateR.server = NULL)
  expect_error(agg_server("agg.mynl.com"), class = "aggregateR_refusal")
  expect_error(agg_server(c("http://a.test", "http://b.test")),
               class = "aggregateR_refusal")
})
