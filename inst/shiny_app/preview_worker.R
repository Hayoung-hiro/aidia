# Executed in the background R process. All inputs are immutable snapshots.
.shiny_preview_worker <- function(request, package_path, app_path) {
  if (!identical(getOption("aidia.preview.package_path"), package_path)) {
    if (dir.exists(file.path(package_path, "R")) &&
        file.exists(file.path(package_path, "DESCRIPTION")) &&
        !file.exists(file.path(package_path, "Meta", "package.rds"))) {
      # Development worktrees must not silently use an older installed package.
      pkgload::load_all(package_path, quiet = TRUE)
    } else {
      library("aidia", character.only = TRUE, lib.loc = dirname(package_path))
    }
    options(aidia.preview.package_path = package_path)
  }
  env <- new.env(parent = as.environment("package:aidia"))
  sys.source(file.path(app_path, "server_optimization.R"), env)
  sys.source(file.path(app_path, "optimization_workflow.R"), env)
  result <- env$.shiny_compute_windows(request$settings, request$data, request$cycle)

  # Reuse the exact RT assignment routine, including sparse-bin/edge handling.
  # Plot selection never approximates membership from overlapping RT endpoints.
  pars <- result$windows$parameters
  rt <- aidia:::perform_rt_binning_internal(
    precursor_data = request$data$data,
    rt_bin_width_min = pars$rt_bin_width_min,
    rt_binning_mode = pars$rt_binning_mode,
    cpd_significance_level = pars$cpd_significance_level,
    cpd_min_bin_width = pars$cpd_min_bin_width,
    cpd_max_bin_width = pars$cpd_max_bin_width,
    cpd_min_precursors_per_bin = pars$cpd_min_precursors_per_bin,
    edge_void_buffer_min = pars$edge_void_buffer_min,
    edge_wash_min_precursors = pars$edge_wash_min_precursors
  )
  stopifnot(isTRUE(all.equal(rt$stats, result$windows$rt_binning$rt_stats)))
  bins <- split(rt$data$Precursor.Mz, rt$data$rt_group)
  make_profile <- function(mz, kde = TRUE) {
    profile <- if (kde && length(mz) >= 10) aidia:::.kde_density_profile(mz) else NULL
    hist <- graphics::hist(mz, breaks = 50, plot = FALSE)
    list(curve = if (!is.null(profile)) data.frame(mz = profile$x, density = profile$y) else NULL,
         histogram = data.frame(mz = hist$mids, density = hist$density,
                                width = diff(hist$breaks)), n = length(mz))
  }
  result$profiles <- lapply(bins, make_profile)
  result$profiles$all <- list(n = nrow(request$data$data))
  # Build density in the worker from the complete validated snapshot, including
  # precursors outside the selected ranges. View changes only draw this result.
  sys.source(file.path(app_path, "preview_display.R"), env)
  grDevices::pdf(file = NULL)
  overview_device <- grDevices::dev.cur()
  on.exit(grDevices::dev.off(overview_device), add = TRUE)
  result$overview <- ggplot2::ggplotGrob(
    env$.shiny_plot_overview(result$windows, request$data))
  result$settings <- request$settings
  result$cycle <- request$cycle
  result$data_version <- request$data_version
  result
}
