# Live tests against a running local aggregate-api. Opt in by naming it:
#
#   AGGREGATER_LIVE_SERVER=http://127.0.0.1:19480
#
# Skipped otherwise and on CRAN. They never touch the public server.

local_live_server <- function(env = parent.frame()) {
  skip_on_cran()
  server <- Sys.getenv("AGGREGATER_LIVE_SERVER")
  skip_if(!nzchar(server), "AGGREGATER_LIVE_SERVER is not set")
  skip_if(!grepl("^http://(127\\.0\\.0\\.1|localhost)[:/]", server),
          "live tests run against a local server only")
  local_server(server, env = env)
}

live_agg <- "agg LiveA 12 claims sev lognorm 10 cv 1 poisson"

test_that("live: a build returns a handle, and building again sends nothing", {
  local_live_server()
  a <- agg_build(live_agg)
  expect_s3_class(a, "agg_handle")
  expect_equal(a$name, "LiveA")
  httr2::local_mocked_responses(function(req) stop("no request expected"))
  expect_identical(agg_build(live_agg), a)
})

test_that("live: a deleted object is rebuilt under the same id on the next read", {
  server <- local_live_server()
  a <- agg_build(live_agg)
  agg_request("DELETE", paste0("/v1/objects/", a$id), server = server)
  manifest <- json_of(read_object(a, "/v1/objects/%s"))
  expect_equal(manifest$id, a$id)
})

test_that("live: every exhibit reads as a list of data-only tables", {
  local_live_server()
  agg_build(live_agg)
  objects <- list(agg_build(live_agg),
                  agg_build("port LiveP agg.LiveA agg.Capstone.Gross"),
                  agg_build("AggregateStopLoss"))
  for (x in objects) {
    for (name in agg_exhibits(x)$name) {
      ex <- agg_exhibit(x, name)
      expect_s3_class(ex, "agg_exhibit")
      expect_true(nzchar(ex$title))
      expect_equal(names(ex$captions), names(ex$tables))
      for (df in ex$tables) expect_s3_class(df, "data.frame")
    }
  }
})

test_that("live: agg_q() gives the support ends and the median", {
  local_live_server()
  q <- agg_q(agg_build(live_agg), c(0, 0.5, 1))
  expect_named(q, c("0%", "50%", "100%"))
  expect_true(q[[1]] <= q[[2]] && q[[2]] <= q[[3]])
})

test_that("live: a port names this session's own declaration", {
  local_live_server()
  agg_build(live_agg)
  p <- agg_build("port LiveP agg.LiveA agg.Capstone.Gross")
  expect_equal(p$kind, "port")
})
