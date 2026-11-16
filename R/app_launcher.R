#' Launch AIDIA Shiny Application
#'
#' Opens the interactive web interface for DIA isolation window optimization.
#' Local path input is enabled by default for loopback hosts only. Override with
#' \code{options(aidia.shiny.local_files = TRUE/FALSE)} before launching.
#'
#' @param ... Additional arguments passed to \code{\link[shiny]{runApp}}
#' @return This function does not return a value; it launches the Shiny app.
#' @export
run_aidia_app <- function(...) {
  app_dir <- system.file("shiny_app", package = "aidia")
  if (!nzchar(app_dir)) {
    stop("Shiny app directory not found. Is 'aidia' properly installed?")
  }
  host <- list(...)$host %||% getOption("shiny.host", "127.0.0.1")
  previous <- options(aidia.shiny.local_files = getOption("aidia.shiny.local_files",
    host %in% c("127.0.0.1", "::1", "localhost")))
  on.exit(options(previous), add = TRUE)
  shiny::runApp(app_dir, ...)
}
