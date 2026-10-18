# Capture the JSON fixtures the unit tests read, from a local aggregate-api.
#
# Run from the repository root, against a server on this machine:
#
#   Rscript dev/capture-fixtures.R http://127.0.0.1:19480
#
# Every program below is made up or a library entry, so the fixtures carry no
# one's data. Re-run after an API change and read the diff: the client parses
# exactly these shapes.

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) || !grepl("^http://127\\.0\\.0\\.1:[0-9]+$", args[1])) {
  stop("pass a local server's address, such as http://127.0.0.1:19480")
}
server <- args[1]
out <- file.path("tests", "testthat", "fixtures")
dir.create(out, recursive = TRUE, showWarnings = FALSE)

# One request in a session of its own, so the session's recipe base starts
# empty; returns the status and the body text.
call <- function(method, path, body = NULL, session = "r-capture-fixtures") {
  req <- httr2::request(paste0(server, path))
  req <- httr2::req_method(req, method)
  req <- httr2::req_headers(req, `X-Aggregate-Session` = session)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  if (!is.null(body)) req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
  resp <- httr2::req_perform(req)
  list(status = httr2::resp_status(resp), text = httr2::resp_body_string(resp))
}

save <- function(name, reply) {
  json <- jsonlite::prettify(reply$text, indent = 1)
  con <- file(file.path(out, paste0(name, ".json")), "wb")
  writeLines(json, con)
  close(con)
  cat(sprintf("%-28s HTTP %d, %s bytes\n", name, reply$status,
              format(nchar(json), big.mark = ",")))
}

session <- paste0("r-capture-", format(Sys.time(), "%Y%m%dT%H%M%S"))
agg_a <- "agg A 10 claims sev lognorm 10 cv 1 poisson"

# [build]
built <- call("POST", "/v1/objects", list(decl = agg_a), session)
save("build-agg-a", built)
save("build-port-p", call("POST", "/v1/objects",
                          list(decl = "port P agg.A agg.Capstone.Gross"), session))
save("build-value", call("POST", "/v1/objects", list(decl = "(2+2)")))
save("refusal-parse", call("POST", "/v1/objects",
                           list(decl = "agg A 10 claims sev lognorm 10 cv 1 poison")))
save("refusal-recipe-not-found", call("POST", "/v1/objects",
                                      list(decl = "port P agg.A agg.Capstone.Gross"),
                                      paste0(session, "-fresh")))
save("missing-object", call("GET", "/v1/objects/0000000000000000/exhibits"))
