#' The exhibits an object can show
#'
#' @param x An `agg_handle` from [agg_build()], or a DecL program, which is
#'   built first on the server's default grid.
#' @return A data frame with one row per exhibit: `name`, to pass to
#'   [agg_exhibit()], `title`, and `perspectives`, the views it offers,
#'   comma separated.
#' @examplesIf interactive()
#' agg_exhibits("agg A 10 claims sev lognorm 10 cv 1 poisson")
#' @export
agg_exhibits <- function(x) {
  body <- json_of(read_object(x, "/v1/objects/%s/exhibits"))
  items <- body$exhibits
  data.frame(
    name = vapply(items, function(e) as.character(e$name), ""),
    title = vapply(items, function(e) as.character(e$title), ""),
    perspectives = vapply(items, function(e) paste(unlist(e$perspectives), collapse = ", "), "")
  )
}

#' One exhibit: its text and its tables, kept apart
#'
#' @param x An `agg_handle` from [agg_build()], or a DecL program.
#' @param name The exhibit, such as `"summary"`; [agg_exhibits()] lists them.
#' @param perspective `"raw"` (the default) or another view the exhibit
#'   offers, such as `"insurer"`.
#' @return An `agg_exhibit`: a list with
#'   - `title`: the exhibit's title, such as `"Summary: BasicBook"`;
#'   - `captions`: a named character vector, one caption per block;
#'   - `tables`: a named list of data frames, one per block, with the same
#'     names as `captions`;
#'   - `name` and `perspective`, as asked for.
#'
#'   It is always a list, whether the exhibit has one block or several.
#'   Printing it shows the title, then each block's name, caption and table.
#' @details
#' The names are the server's block keys, such as `summary_df` or
#' `reins_stats_df`: short and stable, never the captions.
#'
#' Each table holds data only:
#' - **Row labels** (the stub) are character columns. A label spanning several
#'   rows is repeated down every row it covers, so each row says what it is.
#' - **Values** are the server's raw numbers, never its display text: numeric
#'   for number columns, logical for flags, `NA` where the server has no value
#'   (a percentile that does not apply, or a non-finite value).
#' - **Column names** join the header levels with a space (`occ Gross`,
#'   `agg Ceded`), and are kept as they are, so use backticks or `[[` to
#'   select them.
#' @examplesIf interactive()
#' ex <- agg_exhibit("agg A 10 claims sev lognorm 10 cv 1 poisson", "summary")
#' ex$tables$summary_df
#' @export
agg_exhibit <- function(x, name, perspective = "raw") {
  if (!is_text(name)) abort_refusal("name must be one exhibit name; agg_exhibits() lists them")
  if (!is_text(perspective)) abort_refusal("perspective must be one name, such as \"raw\"")
  path <- paste0("/v1/objects/%s/exhibit/", url_part(name))
  exhibit_from(json_of(read_object(x, path, query = list(perspective = perspective))))
}

# A name made safe for one path segment.
url_part <- function(text) {
  utils::URLencode(text, reserved = TRUE)
}

#' An exhibit envelope as an `agg_exhibit`
#'
#' @param payload The body of `GET /v1/objects/{id}/exhibit/{name}`, parsed
#'   without simplification.
#' @noRd
exhibit_from <- function(payload) {
  blocks <- payload$blocks
  keys <- as.character(unlist(payload$meta$blocks))
  if (length(keys) != length(blocks) || anyDuplicated(keys) || !all(nzchar(keys))) {
    keys <- paste0("block", seq_along(blocks))
  }
  versions <- vapply(blocks, function(b) {
    if (is.null(b$ir_version)) NA_real_ else as.numeric(b$ir_version)
  }, 0)
  unknown <- unique(versions[!is.na(versions) & versions != 1])
  if (length(unknown)) {
    warning(sprintf(
      "exhibit %s uses table layout version %s; this client reads version 1, so check its tables",
      payload$name, paste(unknown, collapse = ", ")
    ), call. = FALSE)
  }
  captions <- vapply(blocks, function(b) if (is_text(b$caption)) b$caption else "", "")
  tables <- lapply(blocks, block_table)
  structure(
    list(
      name = payload$name,
      title = if (is.null(payload$title)) "" else payload$title,
      perspective = payload$perspective,
      captions = stats::setNames(captions, keys),
      tables = stats::setNames(tables, keys)
    ),
    class = "agg_exhibit"
  )
}

#' One block of an exhibit as a data frame
#'
#' A port of the add-in's `core.ts:blockRows`, keeping data only. A stub cell
#' with a `rowspan` covers the same column in the rows below it, which then
#' arrive one cell short, so its label is carried down into each of them.
#'
#' @param block One element of the envelope's `blocks`.
#' @return A data frame: stub columns character, value columns typed by the
#'   column's `dtype` from the raw values.
#' @noRd
block_table <- function(block) {
  columns <- block$columns
  width <- length(columns)
  stubs <- if (is.null(block$n_stub_levels)) 0 else block$n_stub_levels
  rows <- lapply(block$body, function(row) row$cells)
  cells <- matrix(list(NULL), nrow = length(rows), ncol = width)
  carry_text <- character(width)
  carry_left <- integer(width)
  for (i in seq_along(rows)) {
    row <- rows[[i]]
    nxt <- 1
    for (col in seq_len(width)) {
      if (col <= stubs && carry_left[col] > 0) {
        cells[[i, col]] <- carry_text[col]
        carry_left[col] <- carry_left[col] - 1
        next
      }
      if (nxt > length(row)) next
      cell <- row[[nxt]]
      nxt <- nxt + 1
      if (col <= stubs) {
        span <- if (is.list(cell) && is.numeric(cell$rowspan)) cell$rowspan else 1
        text <- stub_text(cell)
        carry_text[col] <- text
        carry_left[col] <- max(0, span - 1)
        cells[[i, col]] <- text
      } else if (!is.null(cell)) {
        cells[[i, col]] <- cell
      }
    }
  }
  out <- lapply(seq_len(width), function(col) {
    column_values(cells[, col], columns[[col]], is_stub = col <= stubs)
  })
  names(out) <- vapply(columns, column_name, "")
  list2DF(out, nrow = length(rows))
}

stub_text <- function(cell) {
  if (is.list(cell)) cell <- cell$text
  if (is.null(cell)) "" else as.character(cell)
}

# A column's name: its non-empty header levels joined by a space.
column_name <- function(column) {
  levels <- as.character(unlist(column$name))
  paste(levels[nzchar(levels)], collapse = " ")
}

# One column's values from its cells. Raw values are typed by the column's
# dtype; a column the server sent without raw values keeps its text.
column_values <- function(cells, column, is_stub) {
  if (is_stub) {
    return(vapply(cells, function(c) if (is.null(c)) NA_character_ else c, ""))
  }
  pick <- function(field) {
    lapply(cells, function(c) {
      value <- if (is.list(c)) c[[field]] else c
      if (is.null(value)) NA else value
    })
  }
  if (!isTRUE(column$raw)) {
    return(vapply(pick("text"), function(v) as.character(v), ""))
  }
  raw <- pick("raw")
  dtype <- if (is.null(column$dtype)) "" else column$dtype
  if (dtype %in% c("float", "int")) {
    # A big int arrives as a string; as.numeric() reads it.
    return(vapply(raw, function(v) as.numeric(v), 0))
  }
  if (dtype == "bool") return(vapply(raw, function(v) as.logical(v), NA))
  vapply(raw, function(v) as.character(v), "")
}

#' @export
print.agg_exhibit <- function(x, ...) {
  cat("<agg_exhibit>", x$title, "\n")
  for (key in names(x$tables)) {
    cat("\n", key, "\n", sep = "")
    caption <- x$captions[[key]]
    if (nzchar(caption)) cat(strwrap(caption, indent = 2, exdent = 2), sep = "\n")
    cat("\n")
    print(x$tables[[key]], row.names = FALSE)
  }
  invisible(x)
}

#' Quantiles of an object's loss
#'
#' @param x An `agg_handle` from [agg_build()], or a DecL program.
#' @param p Probabilities, each between 0 and 1 inclusive: `q(0)` and `q(1)`
#'   are the ends of the support.
#' @param basis `"aggregate"` (the default) for the annual total loss, or
#'   `"occurrence"` for a single claim.
#' @return A numeric vector of exact grid quantiles, named like
#'   [stats::quantile()]'s (`"99%"`).
#' @examplesIf interactive()
#' agg_q("agg A 10 claims sev lognorm 10 cv 1 poisson", c(0.5, 0.99, 0.995))
#' @export
agg_q <- function(x, p, basis = "aggregate") {
  if (!is.numeric(p) || !length(p) || anyNA(p) || any(p < 0 | p > 1)) {
    bad <- if (is.numeric(p) && length(p)) p[is.na(p) | p < 0 | p > 1][1] else "none"
    abort_refusal(paste("every p must lie between 0 and 1 inclusive; got", format(bad)))
  }
  if (!is_text(basis)) abort_refusal("basis must be \"aggregate\" or \"occurrence\"")
  query <- list(p = paste(exact_text(p), collapse = ","), snap = "false", basis = basis)
  body <- json_of(read_object(x, "/v1/objects/%s/quantiles", query = query))
  q <- vapply(body$quantiles, function(row) if (is.null(row$q)) NA_real_ else row$q, 0)
  stats::setNames(q, paste0(formatC(100 * p, format = "fg", width = 1, digits = 7), "%"))
}

# Numbers as text that reads back as the same double: the short form where it
# round-trips, all 17 digits where it does not.
exact_text <- function(x) {
  text <- as.character(x)
  lossy <- as.numeric(text) != x
  text[lossy] <- sprintf("%.17g", x[lossy])
  text
}
