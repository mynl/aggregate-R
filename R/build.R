# Building, and the client-side cache, ported from the Excel add-in's
# `functions.ts` (`buildOnce`, `readFrom`, `remember`). The decisions and where
# R departs are in dev/plan-r-client.md, "Client-side cache". Per server, the
# state holds:
#
# - `memo`: (program, log2, bs) -> handle or number, so the same request posts
#   once per R session. The public server rate-limits builds.
# - `built`: kind.name -> the id it last built to. A build of a name that
#   returns a new id is a redefinition, and clears the memo (ruling 7).
# - `log`: the recipes built, oldest first, de-duplicated, capped at
#   `log_limit`. A lost declaration is replayed from it (ruling 8).

# How many recipes the build log keeps, oldest dropped first, as the add-in's
# recipe table does.
log_limit <- 500

# How many lost declarations one call may replay before it gives up.
replay_limit <- 10

#' Build a DecL program
#'
#' Sends a program to the server and returns a handle to the object it
#' builds. Every other function accepts the handle, or the program itself in
#' its place.
#'
#' @param decl The program, as one string or as a character vector whose
#'   non-empty elements join with newlines (so `readLines()` of a `.agg` file
#'   works).
#' @param log2 log2 of the number of buckets in the grid. `NULL` lets the
#'   server choose.
#' @param bs The bucket size. `NULL` lets the server choose.
#' @return An `agg_handle`, or a plain number when the program evaluates to
#'   one, such as `"(2+2)"`.
#' @details
#' **The memo.** The same program on the same grid is posted once per R
#' session and server; calling again returns the handle without a request.
#' Building a name again with a different result (a redefinition such as a
#' new `agg A`) clears the memo, since any memoized program might refer to it.
#'
#' **Your own declarations.** A program can refer to names an earlier build in
#' this R session declared: `agg A ...` then `port P agg.A agg.Capstone.Gross`.
#' The server keeps those names for the session, and loses them on a restart
#' or after eight idle hours. The client keeps the programs it has built and,
#' when the server reports a name missing, builds it again and retries.
#'
#' **Handles persist.** A handle carries its program and server, so one saved
#' with `saveRDS()` works in a later R session, and an object the server has
#' evicted is rebuilt from its recipe on the next read. A handle whose program
#' refers to your own declarations can only be rebuilt in an R session that
#' has built those declarations.
#' @examplesIf interactive()
#' a <- agg_build("agg A 10 claims sev lognorm 10 cv 1 poisson")
#' a
#' agg_build("(2+2)")
#' @export
agg_build <- function(decl, log2 = NULL, bs = NULL) {
  check_number(log2, "log2")
  check_number(bs, "bs")
  build_once(join_program(decl), log2, bs, current_server())
}

# A program from a string or a character vector, non-empty elements joined
# with newlines as the add-in joins a range: a newline continues a statement.
join_program <- function(decl) {
  if (!is.character(decl)) abort_refusal("the program must be character DecL")
  parts <- decl[!is.na(decl) & nzchar(trimws(decl))]
  if (!length(parts)) abort_refusal(messages$empty_program)
  paste(parts, collapse = "\n")
}

check_number <- function(value, name) {
  if (!is.null(value) && !(is.numeric(value) && length(value) == 1 && !is.na(value))) {
    abort_refusal(paste(name, "must be one number, or NULL for the server's choice"))
  }
}

memo_key <- function(program, log2, bs) {
  as.character(jsonlite::toJSON(
    list(program, if (is.null(log2)) 0 else log2, if (is.null(bs)) 0 else bs),
    auto_unbox = TRUE, digits = NA
  ))
}

# Build a program once per R session: the memo, else a build.
build_once <- function(program, log2, bs, server) {
  state <- server_state(server)
  key <- memo_key(program, log2, bs)
  known <- state$memo[[key]]
  if (!is.null(known)) return(known)
  made <- build_recipe(program, log2, bs, server)
  # After build_recipe(), which may have cleared the memo on a redefinition.
  state$memo[[key]] <- made
  made
}

# POST a program and return a handle (recorded) or the number it means.
build_recipe <- function(program, log2, bs, server, budget = replay_budget()) {
  made <- post_build(program, log2, bs, server, budget)
  if (identical(made$kind, "value")) return(made$value)
  handle <- new_handle(made, program, log2, bs, server)
  record_build(server_state(server), handle)
  handle
}

replay_budget <- function() {
  budget <- new.env(parent = emptyenv())
  budget$left <- replay_limit
  budget
}

#' POST a build, replaying declarations the server has lost
#'
#' @details
#' A 422 `recipe_not_found` names the `kind` and `name` the session's recipe
#' base no longer holds: the server restarted, or the session idled out. The
#' newest logged program that built that name is built again, and the request
#' retried; a retry may report a further name, which is replayed in turn. One
#' `budget` is shared down the recursion, since a replayed program can itself
#' need a replay, so a call makes at most `replay_limit` replays however the
#' names chain.
#'
#' A name the log does not hold (a typo, or a declaration made in another R
#' session) is refused with the server's own message.
#' @return The parsed body of the successful build.
#' @noRd
post_build <- function(program, log2, bs, server, budget = replay_budget()) {
  state <- server_state(server)
  body <- Filter(Negate(is.null), list(decl = program, log2 = log2, bs = bs))
  repeat {
    reply <- reply_of(agg_send("POST", "/v1/objects", body, server = server))
    lost <- lost_declaration(reply)
    if (is.null(lost) || budget$left <= 0) break
    recipe <- logged_recipe(state, lost$kind, lost$name)
    if (is.null(recipe)) break
    budget$left <- budget$left - 1
    build_recipe(recipe$decl, recipe$log2, recipe$bs, server, budget)
  }
  stop_for_reply(reply)
  reply$body
}

# The `detail` of a 422 recipe_not_found, or NULL.
lost_declaration <- function(reply) {
  if (reply$status != 422) return(NULL)
  detail <- detail_of(reply$body)
  if (!is.list(detail) || !identical(detail$error, "recipe_not_found") ||
      !is_text(detail$name)) {
    return(NULL)
  }
  detail
}

# The newest logged recipe that built `kind.name`, or NULL.
logged_recipe <- function(state, kind, name) {
  for (recipe in rev(state$log)) {
    if (identical(recipe$name, name) && (is.null(kind) || identical(recipe$kind, kind))) {
      return(recipe)
    }
  }
  NULL
}

# File a build: a redefinition clears the memo, and the recipe moves to the
# newest end of the log.
record_build <- function(state, handle) {
  name <- paste0(handle$kind, ".", handle$name)
  previous <- state$built[[name]]
  if (!is.null(previous) && !identical(previous, handle$id)) clear_memo(state)
  state$built[[name]] <- handle$id
  entry <- c(list(kind = handle$kind, name = handle$name), handle$recipe)
  request <- c("decl", "log2", "bs")
  same <- vapply(state$log, function(r) identical(r[request], entry[request]),
                 logical(1))
  state$log <- c(state$log[!same], list(entry))
  if (length(state$log) > log_limit) {
    state$log <- state$log[seq.int(length(state$log) - log_limit + 1, length(state$log))]
  }
}

clear_memo <- function(state) {
  state$memo <- list()
}

# Whether a 404 says the object is not in the server's cache.
is_missing_object <- function(body) {
  detail <- detail_of(body)
  is_text(detail) && grepl("^object [0-9a-f]{16} not in cache$", detail)
}

#' GET a route on the object a handle names, rebuilding it once if lost
#'
#' A port of the add-in's `readFrom`. A 404 saying the object is not in cache
#' means it was evicted or the server restarted, so the handle's recipe is
#' posted again. The same id coming back means the same object, and the GET is
#' retried once. A different id means the program now builds something else:
#' the server's library or version changed, or a name the program uses was
#' redefined in this session. The memo is cleared and the call refused, rather
#' than silently swapping the object under the handle.
#'
#' @param x An `agg_handle` or a program.
#' @param path The route, with `%s` where the object id goes.
#' @param query A named list of query parameters.
#' @return The httr2 response, whose status is below 400.
#' @noRd
read_object <- function(x, path, query = NULL) {
  handle <- as_handle(x)
  state <- server_state(handle$server)
  get <- function() {
    agg_send("GET", sprintf(path, handle$id), query = query, server = handle$server)
  }
  resp <- get()
  if (httr2::resp_status(resp) == 404 && is_missing_object(reply_of(resp)$body)) {
    recipe <- handle$recipe
    rebuilt <- build_recipe(recipe$decl, recipe$log2, recipe$bs, handle$server)
    if (!inherits(rebuilt, "agg_handle") || !identical(rebuilt$id, handle$id)) {
      clear_memo(state)
      abort_refusal(messages$changed)
    }
    resp <- get()
  }
  if (httr2::resp_status(resp) >= 400) stop_for_reply(reply_of(resp))
  resp
}

# The JSON body of a successful response.
json_of <- function(resp, simplify = FALSE) {
  reply_of(resp, simplify)$body
}
