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

# [exhibits]: the add-in's choices. BasicBook's stats exhibit has a two-level
# stub with rowspans; AggregateStopLoss's reins exhibit has two blocks, two
# header levels and up to three stub levels.
id_of <- function(entry) jsonlite::fromJSON(call("POST", "/v1/objects", list(decl = entry))$text)$id
basic <- id_of("BasicBook")
stop_loss <- id_of("AggregateStopLoss")
save("exhibits-basicbook", call("GET", paste0("/v1/objects/", basic, "/exhibits")))
save("summary-basicbook", call("GET", paste0("/v1/objects/", basic, "/exhibit/summary")))
save("stats-basicbook", call("GET", paste0("/v1/objects/", basic, "/exhibit/stats")))
save("reins-aggregatestoploss",
     call("GET", paste0("/v1/objects/", stop_loss, "/exhibit/reins")))
save("quantiles-basicbook",
     call("GET", paste0("/v1/objects/", basic, "/quantiles?snap=false&p=0,0.5,1")))

# [frames]: a small object, so its whole density frame is a few kilobytes, in
# both formats the client reads.
download <- function(path, file) {
  req <- httr2::req_error(httr2::request(paste0(server, path)), is_error = function(resp) FALSE)
  resp <- httr2::req_perform(req)
  writeBin(httr2::resp_body_raw(resp), file.path(out, file))
  cat(sprintf("%-28s HTTP %d, %s bytes\n", file, httr2::resp_status(resp),
              format(length(httr2::resp_body_raw(resp)), big.mark = ",")))
}
dice <- jsonlite::fromJSON(call("POST", "/v1/objects",
                                list(decl = "agg Dice dfreq [1:2] dsev [1:6]", log2 = 6))$text)$id
save("frames-dice", call("GET", paste0("/v1/objects/", dice, "/frames")))
download(paste0("/v1/objects/", dice, "/frame/density_df.parquet"), "frame-dice.parquet")
download(paste0("/v1/objects/", dice, "/frame/density_df.csv"), "frame-dice.csv")
save("meta", call("GET", "/v1/meta"))

# [library]: the first few entries in file order, with the fields the client
# reads. The whole listing is 150 KB, and the lookup is exact on name.
listing <- jsonlite::fromJSON(call("GET", "/v1/examples")$text, simplifyVector = FALSE)
few <- lapply(listing$items[1:5], function(i) i[c("name", "kind", "decl")])
save("examples-few", list(status = 200L, text = jsonlite::toJSON(list(items = few),
                                                                 auto_unbox = TRUE)))
