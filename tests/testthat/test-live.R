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

test_that("live: a port names this session's own declaration", {
  local_live_server()
  agg_build(live_agg)
  p <- agg_build("port LiveP agg.LiveA agg.Capstone.Gross")
  expect_equal(p$kind, "port")
})
