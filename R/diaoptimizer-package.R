#' @keywords internal
"_PACKAGE"

#' diaoptimizer: DIA Isolation Window Optimizer
#'
#' @description
#' Production-ready R package for optimizing Data-Independent Acquisition (DIA)
#' isolation windows for mass spectrometry. Specifically designed for Thermo Fisher
#' Orbitrap instruments.
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
#' @section Supported Instruments:
#' \itemize{
#'   \item Thermo Astral (parallel acquisition)
#'   \item Thermo Orbitrap Exploris (sequential)
#'   \item Thermo Orbitrap Fusion Lumos
#'   \item Bruker TimsTOF
#'   \item SCIEX 7600
#'   \item Waters Synapt
#' }
#'
#' @section m/z Optimization Strategies:
#' \itemize{
#'   \item \strong{quantile}: P5-P95 percentiles (fast, robust)
#'   \item \strong{coverage}: Minimum range for target coverage
#'   \item \strong{outlier}: Mean ± 3σ (inclusive)
#'   \item \strong{smoothing}: Savitzky-Golay gradient-wide smoothing
#' }
#'
#' @section Quick Start:
#' \preformatted{
#' library(diaoptimizer)
#'
#' # Load and validate data
#' data <- create_validated_dataset("path/to/report.parquet")
#'
#' # Plan optimization
#' config <- get_instrument_config("astral")
#' plan <- plan_optimization(data, config, target_dppp = 7.0)
#'
#' # Generate optimized windows
#' windows <- optimize_windows(data, plan, mz_strategy = "quantile")
#'
#' # Export method file
#' export_windows_to_csv(windows, "method.csv", data, plan)
#' }
#'
#' @import dplyr
#' @import ggplot2
#' @importFrom tibble tibble as_tibble
#' @importFrom arrow read_parquet
#' @importFrom jsonlite fromJSON toJSON
#' @importFrom tidyr pivot_longer pivot_wider
#' @importFrom scales comma percent
#' @importFrom viridis viridis
#' @importFrom ggridges geom_density_ridges
#' @importFrom gridExtra grid.arrange
#' @importFrom grid unit
#' @importFrom stats median sd quantile ecdf density
#' @importFrom utils read.csv write.csv head tail
#' @importFrom grDevices pdf dev.off
NULL

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
