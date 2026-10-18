test_that("one block is still a list, named by its block key", {
  ex <- exhibit_from(fixture("summary-basicbook"))
  expect_s3_class(ex, "agg_exhibit")
  expect_equal(ex$title, "Summary: BasicBook")
  expect_named(ex$tables, "summary_df")
  expect_named(ex$captions, "summary_df")
  expect_match(ex$captions[["summary_df"]], "^Headline moments")
})

test_that("a table holds data only: stubs as text, values as raw numbers", {
  df <- exhibit_from(fixture("summary-basicbook"))$tables$summary_df
  expect_s3_class(df, "data.frame")
  expect_equal(names(df), c("X", "Mean", "SD", "CV", "Skew", "P01", "Median", "P99"))
  expect_equal(df$X, c("Freq", "Sev", "Agg"))
  expect_true(all(vapply(df[-1], is.numeric, NA)))
  expect_equal(df$Mean[1], 250)
  # The display text "6.3%" is dropped for the raw ratio.
  expect_equal(df$CV[1], df$SD[1] / df$Mean[1], tolerance = 1e-4)
  # A null raw value (frequency percentiles) is NA, not a dash.
  expect_true(is.na(df$P01[1]))
})

test_that("several blocks keep their own names, captions and tables", {
  ex <- exhibit_from(fixture("reins-aggregatestoploss"))
  expect_named(ex$tables, c("reins_stats_df", "reins_summary_df"))
  expect_equal(names(ex$captions), names(ex$tables))
  expect_true(all(nzchar(ex$captions)))
})

test_that("header levels join with a space into the column names", {
  df <- exhibit_from(fixture("reins-aggregatestoploss"))$tables$reins_stats_df
  expect_equal(names(df), c("component", "measure", "occ Gross", "agg layer.1",
                            "agg Ceded", "agg Net"))
  expect_equal(nrow(df), 26)
})

test_that("a rowspan stub label is repeated into the rows it covers", {
  payload <- fixture("stats-basicbook")
  block <- payload$blocks[[1]]
  first <- block$body[[1]]$cells[[1]]
  expect_gt(first$rowspan, 1)
  df <- exhibit_from(payload)$tables[[1]]
  expect_equal(ncol(df), length(block$columns))
  expect_equal(df[[1]][seq_len(first$rowspan)], rep(first$text, first$rowspan))
  expect_false(identical(df[[1]][first$rowspan + 1], first$text))
  # The second stub level is still its own label on every row.
  expect_equal(df[[2]][2], block$body[[2]]$cells[[1]])
})

test_that("three stub levels carry their spans independently", {
  df <- exhibit_from(fixture("reins-aggregatestoploss"))$tables$reins_summary_df
  expect_equal(names(df)[1:3], c("stage", "view", "component"))
  expect_equal(df$stage, rep("agg", 3))
  expect_equal(df$view, c("subject", "ceded", "net"))
  expect_true(all(vapply(df[-(1:3)], is.numeric, NA)))
})

test_that("an unknown table layout version warns", {
  payload <- fixture("summary-basicbook")
  payload$blocks[[1]]$ir_version <- 2
  expect_warning(exhibit_from(payload), "layout version 2")
})

test_that("missing block keys fall back to block1, block2", {
  payload <- fixture("reins-aggregatestoploss")
  payload$meta$blocks <- NULL
  expect_named(exhibit_from(payload)$tables, c("block1", "block2"))
})

test_that("the print shows the title, each block's name, caption and table", {
  out <- capture.output(print(exhibit_from(fixture("summary-basicbook"))))
  expect_equal(out[1], "<agg_exhibit> Summary: BasicBook ")
  expect_true("summary_df" %in% out)
  expect_true(any(grepl("^  Headline moments", out)))
  expect_true(any(grepl("Freq", out)))
})

test_that("agg_exhibit() asks for the exhibit and perspective on the handle's object", {
  local_server()
  log <- local_replies(json_reply(fixture("build-agg-a")),
                       json_reply(fixture("summary-basicbook")))
  ex <- agg_exhibit("agg A 10 claims sev lognorm 10 cv 1 poisson", "summary")
  expect_named(ex$tables, "summary_df")
  expect_match(log$requests[[2]]$url,
               "^http://mock.test/v1/objects/[0-9a-f]{16}/exhibit/summary\\?perspective=raw$")
})

test_that("agg_exhibits() lists name, title and perspectives", {
  local_server()
  local_replies(json_reply(fixture("build-agg-a")), json_reply(fixture("exhibits-basicbook")))
  df <- agg_exhibits("agg A 10 claims sev lognorm 10 cv 1 poisson")
  expect_equal(names(df), c("name", "title", "perspectives"))
  expect_equal(df$name[1:3], c("summary", "tail", "stats"))
  expect_equal(df$perspectives[1], "raw, insurer")
})

test_that("agg_q() returns exact quantiles named like quantile()'s", {
  local_server()
  log <- local_replies(json_reply(fixture("build-agg-a")),
                       json_reply(fixture("quantiles-basicbook")))
  q <- agg_q("agg A 10 claims sev lognorm 10 cv 1 poisson", c(0, 0.5, 1))
  expect_equal(unname(q), c(9854, 24449, 47774))
  expect_equal(names(q), names(stats::quantile(1, c(0, 0.5, 1))))
  query <- httr2::url_parse(log$requests[[2]]$url)$query
  expect_equal(query, list(p = "0,0.5,1", snap = "false", basis = "aggregate"))
})

test_that("a p outside [0, 1] is refused without a request", {
  local_server()
  log <- local_replies()
  a <- new_handle(fixture("build-agg-a"), "agg A", NULL, NULL, "http://mock.test")
  expect_error(agg_q(a, 1.5), "between 0 and 1 inclusive; got 1.5",
               class = "aggregateR_refusal")
  expect_error(agg_q(a, c(0.5, NA)), class = "aggregateR_refusal")
  expect_error(agg_q(a, numeric()), class = "aggregateR_refusal")
  expect_error(agg_q(a, "0.5"), class = "aggregateR_refusal")
  expect_length(log$requests, 0)
})

test_that("probabilities are sent as text that reads back exactly", {
  expect_equal(exact_text(c(0.5, 0.99)), c("0.5", "0.99"))
  third <- exact_text(1 / 3)
  expect_identical(as.numeric(third), 1 / 3)
})
