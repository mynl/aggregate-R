#' Server facts
#'
#' What the current server runs and allows.
#'
#' @return A list. Among its fields:
#'   - `version` and `aggregate_version`: the server's and the library's
#'     versions. A local server and the public one can run different library
#'     versions, so the same program can differ between them.
#'   - `log2_cap` and `log2_default`: the largest grid the server builds, and
#'     the one it picks when a program does not say.
#'   - `build_timeout_s`: how long a build may run.
#'   - `cache_max`: how many built objects the server keeps. A handle whose
#'     object was evicted is rebuilt from its recipe on the next read.
#'   - `frame_formats`: the formats whole frames are served in.
#' @examplesIf interactive()
#' agg_meta()$version
#' @export
agg_meta <- function() {
  server <- current_server()
  meta <- agg_request("GET", "/v1/meta", server = server, simplify = TRUE)
  state <- server_state(server)
  state$meta <- meta
  meta
}
