#' AIDIA: Adaptive Isolation for DIA
#'
#' @description
#' AIDIA (Adaptive Isolation for DIA) aids researchers in optimizing
#' Data-Independent Acquisition isolation windows for mass spectrometry.
#' Specifically designed for Thermo Fisher Orbitrap instruments.
#'
#' @section Package Name:
#' \strong{AIDIA} = \strong{A}daptive \strong{I}solation for \strong{DIA}
#'
#' Also represents: "Your \strong{Aid} for DIA optimization"
#'
#' @section Main Pipeline Functions:
#' \describe{
#'   \item{\code{\link{create_validated_dataset}}}{Stage 1: Load and validate DIA-NN data}
#'   \item{\code{\link{plan_optimization}}}{Stage 2: Calculate optimal parameters}
#'   \item{\code{\link{optimize_windows}}}{Stage 3: Generate optimized windows}
#'   \item{\code{\link{generate_visualizations}}}{Stage 4: Create plots and reports}
#' }
#'
#' @section Instrument Management:
#' \describe{
#'   \item{\code{\link{get_instrument_config}}}{Get instrument configuration}
#'   \item{\code{\link{list_available_instruments}}}{List supported instruments}
#' }
#'
#' @section Export Functions:
#' \describe{
#'   \item{\code{\link{export_windows_to_csv}}}{Export windows to CSV method file}
#'   \item{\code{\link{export_method_files}}}{Batch export multiple strategies}
#' }
#'
#' @section Supported Instruments (Verified):
#' \itemize{
#'   \item Thermo Astral / Astral Zoom (parallel acquisition)
#'   \item Thermo Q Exactive / HF-X (sequential)
#'   \item Thermo Exploris 480 (sequential)
#'   \item Thermo Eclipse Tribrid (sequential)
#'   \item Thermo Fusion Lumos (sequential)
#' }
#'
#' @section Planned Instruments (Not Yet Verified):
#' \itemize{
#'   \item Bruker TimsTOF series
#'   \item SCIEX ZenoTOF 7600
#'   \item Waters SYNAPT
#' }
#'
#' @section m/z Optimization Strategies:
#' \itemize{
#'   \item \strong{greedy}: MacCoss Lab algorithm (recommended, with optional SG smoothing)
#'   \item \strong{kde}: Kernel Density Estimation for peak detection
#'   \item \strong{quantile}: P5-P95 percentiles (fast, robust, with optional SG smoothing)
#'   \item \strong{coverage}: Minimum range for target coverage
#'   \item \strong{outlier}: Mean +/- 3 sigma (inclusive, with optional SG smoothing)
#' }
#'
#' @section SG Smoothing Option:
#' Greedy, Quantile, and Outlier strategies support optional Savitzky-Golay
#' smoothing to prevent abrupt m/z boundary jumps across RT bins.
#'
#' @section Window Modes:
#' \itemize{
#'   \item \strong{variable}: Density-based adaptive width (Dense=Narrow)
#'   \item \strong{fixed}: Equal width windows
#'   \item \strong{staggered}: Offset windows in alternating RT bins
#' }
#'
#' @section Quick Start:
#' \preformatted{
#' library(aidia)
#'
#' # Load and validate data
#' data <- create_validated_dataset("path/to/report.parquet")
#'
#' # Plan optimization
#' config <- get_instrument_config("astral")
#' plan <- plan_optimization(data, config, target_dppp = 7.0)
#'
#' # Generate optimized windows
#' windows <- optimize_windows(data, plan, mz_strategy = "greedy")
#'
#' # Export method file
#' export_windows_to_csv(windows, "method.csv", data, plan)
#' }
#'
#' @import dplyr
#' @import ggplot2
#' @importFrom tibble tibble as_tibble deframe
#' @importFrom arrow read_parquet
#' @importFrom jsonlite fromJSON toJSON
#' @importFrom tidyr pivot_longer pivot_wider
#' @importFrom scales comma percent
#' @importFrom viridis viridis
#' @importFrom ggridges geom_density_ridges
#' @importFrom gridExtra grid.arrange
#' @importFrom grid unit
#' @importFrom graphics hist
#' @importFrom stats median sd quantile ecdf density approx complete.cases cycle setNames
#' @importFrom utils read.csv write.csv read.delim head tail capture.output
#' @importFrom grDevices pdf dev.off
#'
#' @keywords internal
"_PACKAGE"

#' Pipe operator
#'
#' See \code{dplyr::\link[dplyr:reexports]{\%>\%}} for details.
#'
#' @name %>%
#' @rdname pipe
#' @keywords internal
#' @export
#' @importFrom dplyr %>%
#' @usage lhs \%>\% rhs
NULL

#' Default value operator
#'
#' If \code{x} is \code{NULL}, return \code{y}; otherwise return \code{x}.
#' Provides compatibility for R < 4.4.0 where base \code{\%||\%} is unavailable.
#'
#' @param x A value to check.
#' @param y A default value to use if \code{x} is \code{NULL}.
#' @return \code{x} if not \code{NULL}, otherwise \code{y}.
#' @name op-null-default
#' @rdname null-default
#' @keywords internal
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
