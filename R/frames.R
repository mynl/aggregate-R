#' The frames an object has
#'
#' @param x An `agg_handle` from [agg_build()], or a DecL program.
#' @return A data frame with one row per frame: `name`, to pass to
#'   [agg_frame()], and its `rows` and `columns`.
#' @examplesIf interactive()
#' agg_frames("agg A 10 claims sev lognorm 10 cv 1 poisson")
#' @export
agg_frames <- function(x) {
  items <- json_of(read_object(x, "/v1/objects/%s/frames"))$frames
  data.frame(
    name = vapply(items, function(f) as.character(f$name), ""),
    rows = vapply(items, function(f) as.integer(f$rows), 0L),
    columns = vapply(items, function(f) as.integer(f$columns), 0L)
  )
}

#' A whole frame
#'
#' Downloads one of an object's frames, such as its density, in full.
#'
#' @param x An `agg_handle` from [agg_build()], or a DecL program.
#' @param which The frame, such as `"density_df"`; [agg_frames()] lists them.
#' @return A `data.frame`, every row and column of the server's frame.
#' @details
#' When the server offers Parquet (`agg_meta()$frame_formats`), the frame
#' arrives as Parquet and is read with `nanoparquet`: exact to the bit, and
#' far faster than CSV (0.06 s against 5.5 s for a 65,536 by 33 density from
#' a local server). Otherwise, or if the server answers that it cannot write
#' Parquet, it is read from CSV, which rounds through text and can differ in
#' the last bit. Either way a value the server does not have (it writes `NaN`
#' as a gap) arrives as `NA`, and infinities arrive as `Inf`.
#'
#' At the public server's largest grid, log2 18, a portfolio's density frame
#' is about 90 MB in R.
#' @examplesIf interactive()
#' density <- agg_frame("agg A 10 claims sev lognorm 10 cv 1 poisson")
#' head(density)
#' @export
agg_frame <- function(x, which = "density_df") {
  if (!is_text(which)) abort_refusal("which must be one frame name; agg_frames() lists them")
  handle <- as_handle(x)
  path <- paste0("/v1/objects/%s/frame/", url_part(which))
  if ("parquet" %in% unlist(server_meta(handle$server)$frame_formats)) {
    resp <- tryCatch(
      read_object(handle, paste0(path, ".parquet")),
      # 501: this server has no Parquet writer after all; CSV still works.
      aggregateR_transient = function(e) if (isTRUE(e$status == 501)) NULL else stop(e)
    )
    if (!is.null(resp)) return(parquet_frame(resp))
  }
  csv_frame(read_object(handle, paste0(path, ".csv")))
}

parquet_frame <- function(resp) {
  file <- tempfile(fileext = ".parquet")
  on.exit(unlink(file))
  writeBin(httr2::resp_body_raw(resp), file)
  # read_parquet() returns a tbl; plain data frames are the package's promise.
  as.data.frame(nanoparquet::read_parquet(file))
}

csv_frame <- function(resp) {
  utils::read.csv(text = httr2::resp_body_string(resp), check.names = FALSE)
}

# The server's facts, fetched once per R session and kept.
server_meta <- function(server) {
  state <- server_state(server)
  if (is.null(state$meta)) {
    state$meta <- agg_request("GET", "/v1/meta", server = server, simplify = TRUE)
  }
  state$meta
}
