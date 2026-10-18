# The handle: an S3 list of class `agg_handle` naming one built object.
#
# It plays the part of the Excel add-in's workbook recipe table. The add-in
# keeps id -> (program, log2, bs) in the workbook because a cell holds only
# text; an R handle is an object, so it carries its own recipe and its own
# server, and it persists the way a workbook does: a handle saved with
# saveRDS() still works in a later R session.

new_handle <- function(made, program, log2, bs, server) {
  structure(
    list(
      id = made$id,
      kind = made$kind,
      name = if (is.null(made$name)) "" else made$name,
      # The request as made, NULL meaning the server's default, so a rebuild
      # asks for exactly what was asked for before.
      recipe = list(decl = program, log2 = log2, bs = bs),
      server = server,
      # What the server resolved and reported.
      log2 = made$log2,
      bs = made$bs,
      mean = made$mean,
      cv = made$cv,
      validation = made$validation,
      warnings = as.character(unlist(made$warnings))
    ),
    class = "agg_handle"
  )
}

#' @export
format.agg_handle <- function(x, ...) {
  number <- function(value, digits) {
    if (is.null(value)) "NA" else format(signif(value, digits))
  }
  lines <- c(
    sprintf("<agg_handle> %s.%s #%s", x$kind, x$name, x$id),
    sprintf("  server      %s", x$server),
    sprintf("  grid        log2 %s, bs %s", number(x$log2, 6), number(x$bs, 6)),
    sprintf("  mean, cv    %s, %s", number(x$mean, 6), number(x$cv, 3))
  )
  if (!is.null(x$validation)) {
    lines <- c(lines, sprintf("  validation  %s", x$validation))
  }
  if (length(x$warnings)) {
    lines <- c(lines, sprintf("  warning     %s", x$warnings))
  }
  lines
}

#' @export
print.agg_handle <- function(x, ...) {
  cat(format(x), sep = "\n")
  invisible(x)
}

#' The handle an argument names: as given, or built from the program it holds
#'
#' Every function that takes `x` accepts a handle or a DecL program, as the
#' add-in's functions accept a handle or a program in a cell. A program is
#' built on the server's default grid through `agg_build()`, so its memo
#' applies: passing the same program to several functions posts it once.
#'
#' @param x An `agg_handle`, or a character DecL program.
#' @return An `agg_handle`.
#' @noRd
as_handle <- function(x) {
  if (inherits(x, "agg_handle")) return(x)
  if (!is.character(x)) abort_refusal(messages$not_a_handle)
  made <- build_once(join_program(x), NULL, NULL, current_server())
  if (!inherits(made, "agg_handle")) abort_refusal(messages$program_is_value)
  made
}
