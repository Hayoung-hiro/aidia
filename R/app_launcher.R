#' Launch AIDIA Shiny Application
#'
#' Opens the interactive web interface for DIA isolation window optimization.
#'
#' @param ... Additional arguments passed to \code{\link[shiny]{runApp}}
#' @return This function does not return a value; it launches the Shiny app.
#' @export
run_aidia_app <- function(...) {
  shiny_deps <- c("shiny", "bs4Dash", "shinyjs", "shinybusy", "DT")
  missing <- shiny_deps[!vapply(shiny_deps, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0) {
    stop(sprintf(
      "Required packages not installed: %s\nInstall with: install.packages(c(%s))",
      paste(missing, collapse = ", "),
      paste(sprintf('"%s"', missing), collapse = ", ")
    ))
  }
  app_dir <- system.file("shiny_app", package = "aidia")
  if (!nzchar(app_dir)) {
    stop("Shiny app directory not found. Is 'aidia' properly installed?")
  }
  shiny::runApp(app_dir, ...)
}
