#' Launch AIDIA Shiny Application
#'
#' Opens the interactive web interface for DIA isolation window optimization.
#'
#' @param ... Additional arguments passed to \code{\link[shiny]{runApp}}
#' @return This function does not return a value; it launches the Shiny app.
#' @export
run_aidia_app <- function(...) {
  app_dir <- system.file("shiny_app", package = "aidia")
  if (!nzchar(app_dir)) {
    stop("Shiny app directory not found. Is 'aidia' properly installed?")
  }
  shiny::runApp(app_dir, ...)
}
