#' The example library
#'
#' Lists the programs in the server's example library, the `.agg` file of
#' named portfolios, aggregates and severities that programs can refer to as
#' `agg.Name` or `port.Name`.
#'
#' @param database A database stem from the server's listing. `NULL`, the
#'   default, is the library builds resolve against.
#' @return A data frame, one row per entry in file order: `name`, to pass to
#'   [agg_program()], and `kind`.
#' @details The listing is fetched once per R session, server and database.
#' @examplesIf interactive()
#' head(agg_library())
#' @export
agg_library <- function(database = NULL) {
  items <- library_items(database, current_server())
  data.frame(
    name = vapply(items, function(i) i$name, ""),
    kind = vapply(items, function(i) i$kind, "")
  )
}

#' One library entry's program
#'
#' @param name An entry, such as `"Capstone.Gross"`; [agg_library()] lists
#'   them.
#' @param database A database stem, or `NULL` for the default library.
#' @return The entry's DecL program as one string, newlines kept, as its file
#'   spells it: ready to edit, or to pass to [agg_build()].
#' @examplesIf interactive()
#' cat(agg_program("BasicBook"))
#' agg_build(agg_program("Capstone.Gross"))
#' @export
agg_program <- function(name, database = NULL) {
  if (!is_text(name)) abort_refusal("name must be one library entry; agg_library() lists them")
  for (item in library_items(database, current_server())) {
    if (identical(item$name, name)) return(item$decl)
  }
  abort_refusal(paste0("no library entry named ", name, "; agg_library() lists them"))
}

# The library's entries for one database, fetched once per R session and
# server, as the add-in fetches once per runtime. About 150 KB for the
# default library, so one fetch serves every later call.
library_items <- function(database, server) {
  if (!is.null(database) && !is_text(database)) {
    abort_refusal("database must be one database stem, or NULL for the default library")
  }
  state <- server_state(server)
  key <- paste0("database:", if (is.null(database)) "" else database)
  items <- state$libraries[[key]]
  if (is.null(items)) {
    query <- if (!is.null(database)) list(database = database)
    body <- agg_request("GET", "/v1/examples", query = query, server = server)
    items <- lapply(body$items, function(i) {
      list(name = as.character(i$name), kind = as.character(i$kind),
           decl = as.character(i$decl))
    })
    state$libraries[[key]] <- items
  }
  items
}
