# test-namespace-coverage.R
#
# Regression guard against a recurring bug class:
#
#   Code in inst/shiny_app/ or main.R references an aidia function or
#   constant that is marked @keywords internal (not exported). The dev
#   environment hides the bug because devtools::load_all() makes ALL
#   package symbols visible on the search path, including internals.
#   The bug only surfaces after install + library(aidia), when the
#   internal symbol is not on the user search path.
#
# History:
#   - 98803f1 "fix: export 12 symbols required by Shiny app"
#   - 93bc998 (this session) needed to export STRATEGY_PREFERRED_ORDER
#     because Shiny server_downloads.R referenced it without prefix.
#
# This test fails any future commit that introduces a similar gap.


# Helper: extract every bare identifier from a file as a vector of strings
.extract_identifiers <- function(file_path) {
  if (!file.exists(file_path)) return(character(0))
  txt <- paste(readLines(file_path, warn = FALSE), collapse = "\n")
  ids <- regmatches(txt, gregexpr("[a-zA-Z_][a-zA-Z0-9_.]+", txt))[[1]]
  unique(ids)
}

# Helper: list aidia internal symbols (defined in namespace, not exported,
# and not "private" via leading dot — which call sites would never use
# without explicit ::: anyway).
.aidia_internal_symbols <- function() {
  exports <- getNamespaceExports("aidia")
  all_syms <- ls(asNamespace("aidia"))
  internal <- setdiff(all_syms, exports)
  internal[!startsWith(internal, ".")]
}

# Helper: format violations as a readable message
.format_violations <- function(violations) {
  parts <- vapply(names(violations), function(f) {
    sprintf("  %s -> %s", f, paste(violations[[f]], collapse = ", "))
  }, character(1))
  paste(parts, collapse = "\n")
}


test_that("Shiny app references only exported aidia symbols", {
  shiny_dir <- system.file("shiny_app", package = "aidia")
  skip_if(!nzchar(shiny_dir) || !dir.exists(shiny_dir),
          "Shiny app dir not found (package not fully installed)")

  internal <- .aidia_internal_symbols()
  shiny_files <- list.files(shiny_dir, pattern = "\\.R$", full.names = TRUE)

  violations <- list()
  for (f in shiny_files) {
    ids <- .extract_identifiers(f)
    hits <- intersect(internal, ids)
    if (length(hits) > 0) {
      violations[[basename(f)]] <- hits
    }
  }

  expect_equal(length(violations), 0L,
    info = sprintf(
      paste0(
        "Shiny modules reference aidia internal symbols:\n%s\n\n",
        "Each symbol must either be @export-ed in R/ or accessed via ",
        "aidia:::symbol from Shiny code. Marking it @keywords internal ",
        "while Shiny consumes it without a prefix breaks under library(aidia)."
      ),
      .format_violations(violations)
    )
  )
})


test_that("main.R references only exported aidia symbols", {
  # main.R is a dev-tree script; not present after R CMD INSTALL.
  candidates <- c(
    "../../main.R",       # devtools::test() working dir = tests/testthat/
    "main.R",             # if test_dir() is run from project root
    file.path(testthat::test_path(), "..", "..", "main.R")
  )
  main_path <- NULL
  for (p in candidates) {
    if (file.exists(p)) { main_path <- p; break }
  }
  skip_if(is.null(main_path), "main.R not in dev tree (this is fine in installed checks)")

  internal <- .aidia_internal_symbols()
  ids <- .extract_identifiers(main_path)
  hits <- intersect(internal, ids)

  expect_equal(length(hits), 0L,
    info = sprintf(
      paste0(
        "main.R references aidia internal symbols: %s\n\n",
        "main.R uses library(aidia) and must restrict itself to exported names."
      ),
      paste(hits, collapse = ", ")
    )
  )
})


test_that("audit helpers themselves work (sanity check)", {
  # Confirm we actually find non-trivial numbers of exports + internals,
  # so a future refactor that empties the namespace doesn't silently turn
  # the audit into a no-op.
  exports <- getNamespaceExports("aidia")
  internal <- .aidia_internal_symbols()

  expect_gt(length(exports), 30L,
            label = "aidia should expose more than 30 exports")
  expect_gt(length(internal), 30L,
            label = "aidia should have more than 30 internal helpers ",
            "(if this fails, .aidia_internal_symbols is broken)")
})
