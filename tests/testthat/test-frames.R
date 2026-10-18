dice <- "agg Dice dfreq [1:2] dsev [1:6]"

file_reply <- function(name, type, status = 200) {
  path <- test_path("fixtures", name)
  httr2::response(status_code = status, headers = list(`Content-Type` = type),
                  body = readBin(path, "raw", file.size(path)))
}

meta_with <- function(formats) {
  meta <- fixture("meta")
  meta$frame_formats <- as.list(formats)
  json_reply(meta)
}

urls <- function(log) vapply(log$requests, function(r) r$url, "")

test_that("agg_frames() lists name, rows and columns", {
  local_server()
  local_replies(json_reply(fixture("build-agg-a")), json_reply(fixture("frames-dice")))
  df <- agg_frames(dice)
  expect_equal(names(df), c("name", "rows", "columns"))
  expect_equal(df[1, ], data.frame(name = "summary", rows = 3L, columns = 8L))
  expect_true("density_df" %in% df$name)
})

test_that("a server with Parquet sends the frame as Parquet, read to a plain data frame", {
  local_server()
  log <- local_replies(json_reply(fixture("build-agg-a")), meta_with(c("csv", "json", "parquet")),
                       file_reply("frame-dice.parquet", "application/vnd.apache.parquet"))
  df <- agg_frame(dice)
  expect_identical(class(df), "data.frame")
  expect_equal(nrow(df), 16)
  expect_true(all(c("loss", "p_total", "F", "S") %in% names(df)))
  expect_match(urls(log)[3], "/frame/density_df\\.parquet$")
})

test_that("Parquet and CSV agree on every value, infinities and gaps included", {
  pq <- as.data.frame(nanoparquet::read_parquet(test_path("fixtures", "frame-dice.parquet")))
  csv <- utils::read.csv(test_path("fixtures", "frame-dice.csv"), check.names = FALSE)
  expect_equal(names(pq), names(csv))
  for (col in names(pq)) {
    expect_identical(is.na(csv[[col]]), is.na(pq[[col]]))
    expect_identical(is.infinite(csv[[col]]), is.infinite(pq[[col]]))
    finite <- is.finite(pq[[col]])
    expect_equal(csv[[col]][finite], pq[[col]][finite], tolerance = 1e-15)
  }
  expect_true(any(pq$log_p == -Inf))
})

test_that("a server without Parquet is read from CSV", {
  local_server()
  log <- local_replies(json_reply(fixture("build-agg-a")), meta_with(c("csv", "json")),
                       file_reply("frame-dice.csv", "text/csv"))
  df <- agg_frame(dice)
  expect_equal(nrow(df), 16)
  expect_match(urls(log)[3], "/frame/density_df\\.csv$")
  expect_false(any(grepl("parquet", urls(log))))
})

test_that("a 501 from the Parquet route falls back to CSV", {
  local_server()
  log <- local_replies(json_reply(fixture("build-agg-a")), meta_with("parquet"),
                       json_reply(list(detail = "parquet needs pyarrow"), 501),
                       file_reply("frame-dice.csv", "text/csv"))
  expect_equal(nrow(agg_frame(dice)), 16)
  expect_length(log$requests, 4)
})

test_that("the server's facts are fetched once per R session", {
  local_server()
  csv <- file_reply("frame-dice.csv", "text/csv")
  log <- local_replies(json_reply(fixture("build-agg-a")), meta_with("csv"), csv, csv)
  agg_frame(dice)
  agg_frame(dice, "density_df")
  expect_equal(sum(grepl("/v1/meta$", urls(log))), 1)
})

test_that("an unknown frame is the server's refusal", {
  local_server()
  local_replies(json_reply(fixture("build-agg-a")), meta_with("csv"),
                json_reply(list(detail = "no frame 'nope'; frames: density_df, ..."), 404))
  expect_error(agg_frame(dice, "nope"), "no frame 'nope'", class = "aggregateR_refusal")
})
