# capacity_kpis.R - Acquisition Capacity KPI Derivation (v0.4.x)
#
# Purpose: Derive four "did I use the instrument well?" capacity KPIs from
# existing OptimizationPlan + OptimizedWindows + evaluate_windows() fields.
# Derive-only — no new S3 fields, no PLOT_REGISTRY entry. Shiny diagnostic
# layer; PDF report intentionally excludes the dashboard.
#
# Decisions and rationale: see docs/domain-knowledge.md
#   "Acquisition Capacity vs Identification Yield" and following sections.
#   ADR-0004 rejects raw / method file ingestion.
#
# Dependencies: aidia-package.R (%||%), s3_classes.R (is_OptimizationPlan,
# is_OptimizedWindows).


# =============================================================================
# Default Thresholds
# =============================================================================

#' Default Acquisition Capacity KPI Thresholds
#'
#' Constructs the named nested list of thresholds consumed by
#' [get_capacity_kpis()] and [classify_capacity_kpi()]. Override individual
#' KPIs by passing a list with the same name; missing keys fall back to the
#' published defaults.
#'
#' @section Default table:
#' \tabular{lllll}{
#'   KPI                          \tab Bad   \tab Warn  \tab OK         \tab Info \cr
#'   `filled_window_ratio`        \tab <0.70 \tab 0.70-0.90 \tab >=0.90  \tab --   \cr
#'   `dppp_headroom_x`            \tab <1    \tab --    \tab 1-2        \tab >=2  \cr
#'   `cycle_time_headroom_pct`    \tab <0    \tab --    \tab 0-15       \tab >=15 \cr
#'   `window_count_headroom_pct`  \tab --    \tab --    \tab 0-30       \tab >=30 \cr
#' }
#'
#' @param filled_window_ratio List with `bad`, `warn` numeric cutoffs
#'   (proportions in 0..1).
#' @param dppp_headroom_x List with `bad`, `info` numeric cutoffs (fold).
#' @param cycle_time_headroom_pct List with `bad`, `info` numeric cutoffs (%).
#' @param window_count_headroom_pct List with `info` numeric cutoff (%).
#'
#' @return Named list with one entry per KPI. Each entry is itself a named
#'   list of numeric cutoffs. Suitable for passing to [get_capacity_kpis()]
#'   via the `thresholds` argument.
#' @export
#'
#' @examples
#' capacity_kpi_thresholds()
#' capacity_kpi_thresholds(
#'   filled_window_ratio = list(bad = 0.60, warn = 0.85),
#'   dppp_headroom_x     = list(bad = 1.0,  info = 3.0)
#' )
capacity_kpi_thresholds <- function(filled_window_ratio        = NULL,
                                    dppp_headroom_x            = NULL,
                                    cycle_time_headroom_pct    = NULL,
                                    window_count_headroom_pct  = NULL) {
  defaults <- list(
    filled_window_ratio       = list(bad = 0.70, warn = 0.90),
    dppp_headroom_x           = list(bad = 1.0,  info = 2.0),
    cycle_time_headroom_pct   = list(bad = 0.0,  info = 15.0),
    window_count_headroom_pct = list(info = 30.0)
  )

  overrides <- list(
    filled_window_ratio       = filled_window_ratio,
    dppp_headroom_x           = dppp_headroom_x,
    cycle_time_headroom_pct   = cycle_time_headroom_pct,
    window_count_headroom_pct = window_count_headroom_pct
  )

  merged <- lapply(names(defaults), function(nm) {
    over <- overrides[[nm]]
    if (is.null(over)) {
      defaults[[nm]]
    } else if (!is.list(over)) {
      stop(sprintf("Threshold override for '%s' must be a named list.", nm),
           call. = FALSE)
    } else {
      utils::modifyList(defaults[[nm]], over)
    }
  })
  names(merged) <- names(defaults)
  merged
}


# =============================================================================
# Main Derivation
# =============================================================================

#' Derive Acquisition Capacity KPIs
#'
#' Computes the four capacity KPIs (filled window ratio, DPPP headroom,
#' cycle-time headroom, window-count headroom) from existing AIDIA outputs.
#' Pure derivation — no S3 mutation, no caching. Mirrors the
#' [evaluate_windows()] pattern: the Shiny app calls this as a reactive,
#' scripts call it directly.
#'
#' @section Field sources:
#' \itemize{
#'   \item Filled window ratio: `1 - length(evaluation$quality_flags$empty_windows) /
#'     evaluation$overall$n_total_windows`.
#'   \item DPPP headroom: `plan$diagnosis$current_dppp_median /
#'     plan$parameters$target_dppp`.
#'   \item Cycle-time headroom: `(plan$required_cycle_time_sec -
#'     plan$actual_cycle_time_sec) / plan$required_cycle_time_sec * 100`.
#'   \item Window-count headroom: `(plan$parameters$max_windows -
#'     plan$window_count_per_bin) / plan$parameters$max_windows * 100`.
#'     When `plan$it_optimization$is_spec_limited` is `TRUE`, the value is
#'     forced to `0` and `is_spec_limited` is propagated for label decoration.
#' }
#'
#' @section Edge cases:
#' When `evaluation` is `NULL` or its quality flag / overall fields are
#' missing, `filled_window_ratio` is `NA_real_` and downstream bottleneck
#' rules #2 / #3 are skipped. The remaining three KPIs are unaffected.
#'
#' @param plan OptimizationPlan S3 object (Stage 2 output).
#' @param windows OptimizedWindows S3 object (Stage 3 output). Currently
#'   reserved for forward compatibility; all required information is read
#'   from `plan` and `evaluation`.
#' @param evaluation Optional list returned by [evaluate_windows()]. When
#'   `NULL`, `filled_window_ratio` is `NA_real_`.
#' @param thresholds Threshold list from [capacity_kpi_thresholds()]
#'   (default).
#'
#' @return Named list with elements:
#'   \describe{
#'     \item{values}{Named numeric vector with `filled_window_ratio`,
#'       `dppp_headroom_x`, `cycle_time_headroom_pct`,
#'       `window_count_headroom_pct`.}
#'     \item{grades}{Named character vector with the same names, each set
#'       to `"Bad"`, `"Warn"`, `"OK"`, `"Info"`, or `"NA"`.}
#'     \item{is_spec_limited}{Logical scalar. When `TRUE`, the
#'       `window_count_headroom_pct` value has been clamped to `0` and the
#'       gauge label should append `"(spec-limited)"`.}
#'     \item{thresholds}{The threshold list used (echoed for downstream
#'       consumers).}
#'   }
#' @export
#'
#' @examples
#' \dontrun{
#' kpis <- get_capacity_kpis(plan, windows, evaluation = evaluate_windows(
#'   optimized_windows = windows,
#'   validated_data    = validated,
#'   optimization_plan = plan
#' ))
#' kpis$values
#' kpis$grades
#' }
get_capacity_kpis <- function(plan,
                              windows,
                              evaluation = NULL,
                              thresholds = capacity_kpi_thresholds()) {

  if (!inherits(plan, "OptimizationPlan")) {
    stop("`plan` must be an OptimizationPlan object.", call. = FALSE)
  }
  if (!inherits(windows, "OptimizedWindows")) {
    stop("`windows` must be an OptimizedWindows object.", call. = FALSE)
  }

  # --- Filled window ratio (NA-safe) ------------------------------------------
  filled_ratio <- compute_filled_ratio(evaluation)

  # --- DPPP headroom -----------------------------------------------------------
  dppp_headroom <- compute_dppp_headroom(
    dppp_median  = plan$diagnosis$current_dppp_median,
    target_dppp  = plan$parameters$target_dppp
  )

  # --- Cycle-time headroom -----------------------------------------------------
  cycle_headroom_pct <- compute_cycle_headroom_pct(
    required_cycle_time_sec = plan$required_cycle_time_sec,
    actual_cycle_time_sec   = plan$actual_cycle_time_sec
  )

  # --- Window-count headroom (spec-limited clamp) ------------------------------
  is_spec_limited <- isTRUE(plan$it_optimization$is_spec_limited)
  window_headroom_pct <- compute_window_headroom_pct(
    max_windows = plan$parameters$max_windows,
    n_windows   = plan$window_count_per_bin,
    is_spec_limited = is_spec_limited
  )

  values <- c(
    filled_window_ratio        = filled_ratio,
    dppp_headroom_x            = dppp_headroom,
    cycle_time_headroom_pct    = cycle_headroom_pct,
    window_count_headroom_pct  = window_headroom_pct
  )

  grades <- vapply(
    names(values),
    function(nm) classify_capacity_kpi(values[[nm]], nm, thresholds),
    character(1)
  )

  list(
    values          = values,
    grades          = grades,
    is_spec_limited = is_spec_limited,
    thresholds      = thresholds
  )
}


# =============================================================================
# Individual KPI Computations (Internal)
# =============================================================================

#' Compute Filled-Window Ratio
#'
#' Fraction of windows that contain at least one precursor. Returns
#' `NA_real_` when `evaluation` is `NULL` or required fields are missing.
#'
#' @param evaluation List returned by [evaluate_windows()] or `NULL`.
#' @return Numeric in 0..1 or `NA_real_`.
#' @keywords internal
compute_filled_ratio <- function(evaluation) {
  if (is.null(evaluation)) return(NA_real_)
  total   <- evaluation$overall$n_total_windows
  empties <- evaluation$quality_flags$empty_windows
  if (is.null(total) || is.na(total) || total <= 0) return(NA_real_)
  n_empty <- if (is.null(empties)) 0L else length(empties)
  1 - (n_empty / total)
}

#' Compute DPPP Headroom (fold)
#'
#' Ratio of the current median DPPP to the target DPPP. `1.0` means the
#' method is exactly at target; values below 1 mean the target is not met.
#'
#' @param dppp_median Numeric, `plan$diagnosis$current_dppp_median`.
#' @param target_dppp Numeric, `plan$parameters$target_dppp`.
#' @return Numeric fold value, or `NA_real_` when inputs are missing or
#'   `target_dppp <= 0`.
#' @keywords internal
compute_dppp_headroom <- function(dppp_median, target_dppp) {
  if (is.null(dppp_median) || is.null(target_dppp)) return(NA_real_)
  if (is.na(dppp_median)   || is.na(target_dppp))   return(NA_real_)
  if (target_dppp <= 0) return(NA_real_)
  dppp_median / target_dppp
}

#' Compute Cycle-Time Headroom (%)
#'
#' Relative slack between required and actual cycle time. Positive means
#' the method has spare time; negative means the cycle is too long for the
#' required peak sampling.
#'
#' @param required_cycle_time_sec Numeric, `plan$required_cycle_time_sec`.
#' @param actual_cycle_time_sec Numeric, `plan$actual_cycle_time_sec`.
#' @return Numeric percent, or `NA_real_` when inputs are missing or
#'   `required_cycle_time_sec <= 0`.
#' @keywords internal
compute_cycle_headroom_pct <- function(required_cycle_time_sec,
                                       actual_cycle_time_sec) {
  if (is.null(required_cycle_time_sec) || is.null(actual_cycle_time_sec)) {
    return(NA_real_)
  }
  if (is.na(required_cycle_time_sec) || is.na(actual_cycle_time_sec)) {
    return(NA_real_)
  }
  if (required_cycle_time_sec <= 0) return(NA_real_)
  (required_cycle_time_sec - actual_cycle_time_sec) /
    required_cycle_time_sec * 100
}

#' Compute Window-Count Headroom (%)
#'
#' Slack between the instrument's `max_windows` ceiling and the planned
#' per-bin window count. Forced to `0` when the IT optimizer reports
#' `is_spec_limited = TRUE`, since the hardware ceiling is the binding
#' constraint and additional headroom is unreachable.
#'
#' @param max_windows Integer, `plan$parameters$max_windows`.
#' @param n_windows Integer, `plan$window_count_per_bin`.
#' @param is_spec_limited Logical, `plan$it_optimization$is_spec_limited`.
#' @return Numeric percent, or `NA_real_` when inputs are missing or
#'   `max_windows <= 0`.
#' @keywords internal
compute_window_headroom_pct <- function(max_windows, n_windows,
                                        is_spec_limited = FALSE) {
  if (isTRUE(is_spec_limited)) return(0)
  if (is.null(max_windows) || is.null(n_windows)) return(NA_real_)
  if (is.na(max_windows)   || is.na(n_windows))   return(NA_real_)
  if (max_windows <= 0) return(NA_real_)
  (max_windows - n_windows) / max_windows * 100
}


# =============================================================================
# Classification
# =============================================================================

#' Classify a Capacity KPI Value
#'
#' Maps a numeric KPI value to one of `"Bad"`, `"Warn"`, `"OK"`, `"Info"`,
#' or `"NA"` using the thresholds returned by [capacity_kpi_thresholds()].
#' Two-sided KPIs (DPPP / cycle / window headroom) use `Bad / OK / Info`;
#' the monotonic `filled_window_ratio` uses `Bad / Warn / OK`.
#'
#' Boundary rule: lower bound is inclusive, upper bound exclusive
#' (`Bad < bad <= Warn < warn <= OK < info <= Info`). The
#' `filled_window_ratio` value of exactly `0.70` is `Warn`; exactly `0.90`
#' is `OK`.
#'
#' @param value Numeric scalar (the KPI value to classify).
#' @param kpi_name Character, one of `"filled_window_ratio"`,
#'   `"dppp_headroom_x"`, `"cycle_time_headroom_pct"`,
#'   `"window_count_headroom_pct"`.
#' @param thresholds List from [capacity_kpi_thresholds()].
#' @return Character scalar: `"Bad"`, `"Warn"`, `"OK"`, `"Info"`, or `"NA"`.
#' @export
classify_capacity_kpi <- function(value, kpi_name, thresholds) {
  if (is.null(value) || length(value) == 0L || is.na(value)) {
    return("NA")
  }
  th <- thresholds[[kpi_name]]
  if (is.null(th)) {
    stop(sprintf("Unknown KPI name '%s'.", kpi_name), call. = FALSE)
  }

  switch(kpi_name,
    filled_window_ratio = {
      if (value < th$bad)  "Bad"
      else if (value < th$warn) "Warn"
      else "OK"
    },
    dppp_headroom_x = {
      if (value < th$bad)  "Bad"
      else if (value < th$info) "OK"
      else "Info"
    },
    cycle_time_headroom_pct = {
      if (value < th$bad)  "Bad"
      else if (value < th$info) "OK"
      else "Info"
    },
    window_count_headroom_pct = {
      if (value < th$info) "OK" else "Info"
    },
    stop(sprintf("Unknown KPI name '%s'.", kpi_name), call. = FALSE)
  )
}


# =============================================================================
# Bottleneck Summary (8-rule decision tree)
# =============================================================================

#' Summarize the Dominant Capacity Bottleneck
#'
#' Returns a single English sentence describing the dominant capacity
#' condition. Rules are evaluated in priority order; the first matching
#' rule wins. See `docs/domain-knowledge.md` "Bottleneck Summary -- Rule
#' Set" for the full table.
#'
#' @section Rule order:
#' \enumerate{
#'   \item DPPP `Bad` (equivalently cycle `Bad`) -- target not met.
#'   \item Filled ratio `Bad` (skipped when `filled_window_ratio` is `NA`).
#'   \item Filled ratio `Warn` with no other `Bad`
#'     (skipped when `filled_window_ratio` is `NA`).
#'   \item Cycle `OK` and window `OK` and DPPP `Info` -- ceiling with DPPP
#'     slack, IT / m/z tradeoff available.
#'   \item Cycle `Info` and window `Info` -- underutilized.
#'   \item DPPP `Info` and the remaining three are `OK` -- DPPP-only slack.
#'   \item All `OK` -- well balanced.
#'   \item Fallback message.
#' }
#'
#' @param kpis List returned by [get_capacity_kpis()].
#' @param thresholds List from [capacity_kpi_thresholds()]. Currently used
#'   for forward-compatible signature symmetry with [get_capacity_kpis()].
#' @return Character scalar -- the message text (English).
#' @export
summarize_bottleneck <- function(kpis,
                                 thresholds = capacity_kpi_thresholds()) {
  g <- kpis$grades
  filled <- g[["filled_window_ratio"]]
  dppp   <- g[["dppp_headroom_x"]]
  cycle  <- g[["cycle_time_headroom_pct"]]
  win    <- g[["window_count_headroom_pct"]]

  filled_known <- !identical(filled, "NA")

  # Rule 1 -- DPPP / cycle infeasible
  if (identical(dppp, "Bad")) {
    return("DPPP target not met - cycle too long for required peak sampling. Reduce window count or shorten transient.")
  }

  # Rule 2 -- many empty windows
  if (filled_known && identical(filled, "Bad")) {
    return("Many empty windows - review m/z strategy or RT binning.")
  }

  # Rule 3 -- some empty windows, no other Bad
  if (filled_known && identical(filled, "Warn") &&
      !identical(cycle, "Bad")) {
    return("Some empty windows - consider tightening m/z strategy.")
  }

  # Rule 4 -- cycle / window at ceiling with DPPP slack
  if (identical(cycle, "OK") && identical(win, "OK") &&
      identical(dppp, "Info")) {
    return("Cycle and windows near ceiling with DPPP slack - IT or m/z width tradeoff available.")
  }

  # Rule 5 -- broad underutilization
  if (identical(cycle, "Info") && identical(win, "Info")) {
    return("Underutilized - add more windows or shorten cycle.")
  }

  # Rule 6 -- DPPP-only slack
  if (identical(dppp, "Info") &&
      identical(cycle, "OK") && identical(win, "OK") &&
      (identical(filled, "OK") || !filled_known)) {
    return("Large DPPP headroom - opportunity to lengthen IT for better ion statistics.")
  }

  # Rule 7 -- all healthy
  all_ok <- identical(dppp, "OK") && identical(cycle, "OK") &&
            identical(win, "OK") &&
            (identical(filled, "OK") || !filled_known)
  if (all_ok) {
    return("Well balanced.")
  }

  # Rule 8 -- fallback
  "See individual KPIs for details."
}


# =============================================================================
# Header Context (Sequential vs Parallel)
# =============================================================================

#' One-Line Capacity Header Text
#'
#' Returns the instrument-type context line displayed above the gauge strip
#' in Shiny Step 3. Sequential instruments get a DPPP-bound message;
#' parallel instruments get a sync-aware message because cycle-time
#' headroom is structurally large.
#'
#' @param plan OptimizationPlan S3 object.
#' @return Character scalar (English).
#' @export
capacity_header_text <- function(plan) {
  if (!inherits(plan, "OptimizationPlan")) {
    stop("`plan` must be an OptimizationPlan object.", call. = FALSE)
  }

  sync <- plan$duty_cycle_sync
  if (is.null(sync)) {
    sprintf(
      "Sequential instrument - DPPP-bound at target %.1f.",
      plan$parameters$target_dppp %||% NA_real_
    )
  } else {
    sprintf(
      "Parallel instrument - sync %d%% (%d / %d sync-optimal). DPPP-bound metrics may show high headroom.",
      as.integer(round(sync$duty_cycle_pct %||% NA_real_)),
      as.integer(plan$window_count_per_bin %||% NA_real_),
      as.integer(sync$n_sync_optimal %||% NA_real_)
    )
  }
}
