# dppp.R - DPPP (Data Points Per Peak) Domain Logic
#
# Purpose: Core DPPP calculations, FWHM unit handling, and window count
# estimation. These are the fundamental formulas driving the entire
# AIDIA optimization pipeline.
#
# Key formula: DPPP = (1.7 * FWHM_seconds) / cycle_time_seconds
#
# ---------------------------------------------------------------------------
# TERMINOLOGY (single source of truth - two easily-confused quantities):
#   * DPPP     = data points across the WHOLE peak (peak width = 1.7 x FWHM = 4 sigma).
#                This is what AIDIA computes, stores, targets, and plots everywhere.
#                Read "DPPP" as shorthand for "dppp_wholepeak".
#   * ppp_fwhm = data points within the FWHM only (common in the literature / DIA-NN).
#   Conversion: DPPP = 1.7 * ppp_fwhm        (equivalently ppp_fwhm = DPPP / 1.7)
#   RULE: when a value is FWHM-based, name it explicitly `ppp_fwhm` - never a bare
#   "PPP" or "DPPP". This one-letter ambiguity has caused real target mix-ups
#   (e.g. "is it 7 or 10?" is usually just whole-peak vs FWHM). See PEAK_WIDTH_FACTOR
#   docs and docs/DPPP_INSTRUMENT_OPERATING_POINTS.md for instrument-dependent guidance.
# ---------------------------------------------------------------------------


# =============================================================================
# Constants
# =============================================================================

#' Peak Width Factor for DPPP Calculation
#'
#' ## UNITS - READ THIS BEFORE CHANGING target_dppp
#' AIDIA's DPPP counts data points across the FULL chromatographic peak, defined as
#' 1.7 x FWHM (= 4 sigma for a Gaussian, ~95% of peak area). Much of the literature
#' instead reports PPP-FWHM (points within the FWHM only). They are related by:
#'
#'     DPPP (AIDIA, whole-peak) = 1.7 x PPP-FWHM
#'
#' Examples: DPPP 7.0 == ~4.1 PPP-FWHM ; PPP-FWHM 5.9 == DPPP ~10 ; PPP-FWHM 3.5 == DPPP ~6.
#' ALWAYS state which unit you mean - most "is it 7 or 10?" disagreements are just a
#' whole-peak vs FWHM unit mismatch, NOT a real conflict.
#'
#' ## Operating points are INSTRUMENT- and GOAL-dependent (no single universal number)
#'   - "Sufficient" floor (good precision, ID-friendly): ~3-3.5 PPP-FWHM (= DPPP ~5-6).
#'       DIA-NN guidance (this tool's input engine; DIA-NN models peaks, so few points
#'       suffice) and Zeng & Bateman, JASMS 2023;34(6):1136-1144,
#'       doi:10.1021/jasms.3c00077 (7 whole-peak points -> <1% peak-area error).
#'   - Orbitrap, MAX quant accuracy: ~6 PPP-FWHM (= DPPP ~10), trading ~20% fewer IDs
#'       (bioRxiv CQE recommendations, doi:10.1101/2025.09.22.677725).
#'   - Fast scanners (timsTOF; and Astral, see below): high PPP is NOT needed; force-
#'       filtering to >=6 PPP-FWHM degrades BOTH ID count and quant efficiency (same CQE).
#'   - Skyline trapezoidal workflows want more (Pino et al., MCP 2020,
#'       doi:10.1074/mcp.P119.001913) - a DIFFERENT quant engine, NOT required for DIA-NN.
#'
#' Default target_dppp = 7.0 (~4.1 PPP-FWHM) is an ID-friendly balance for sequential
#' Orbitrap DIA. ID mode (1.5) intentionally trades quant precision for more IDs.
#'
#' ## Astral (and other parallel instruments): DPPP does NOT drive the result
#' Astral scans so fast that DPPP is essentially always satisfied (cycle time <<
#' required), so AIDIA optimizes these instruments for duty-cycle SYNC instead: window
#' count is set by calculate_sync_optimal_windows() and DPPP is only verified as an
#' (easily-met) constraint. See plan_optimization() "Step 5b: Duty Cycle Sync"
#' (runs when cycle_calculation == "parallel"). For Astral, target_dppp is non-binding
#' by design - do not tune Astral methods via DPPP; tune via duty cycle.
#'
#' @export
PEAK_WIDTH_FACTOR <- 1.7


# =============================================================================
# Core DPPP Functions
# =============================================================================

#' Calculate DPPP (Data Points Per Peak)
#'
#' Computes DPPP using the standard formula:
#' DPPP = (peak_width_factor x FWHM_seconds) / cycle_time_seconds
#'
#' @param fwhm_seconds Numeric vector, FWHM in seconds
#' @param cycle_time_sec Numeric, cycle time in seconds
#' @param peak_width_factor Numeric, peak width factor (default: 1.7)
#'
#' @return Numeric vector of DPPP values
#' @export
#'
#' @examples
#' fwhm <- c(10, 15, 20)  # seconds
#' cycle_time <- 2  # seconds
#' dppp <- calculate_dppp(fwhm, cycle_time)
#' # Returns: c(8.5, 12.75, 17.0)
calculate_dppp <- function(fwhm_seconds, cycle_time_sec,
                          peak_width_factor = PEAK_WIDTH_FACTOR) {
  validate_numeric_range(cycle_time_sec, min = 0, param_name = "cycle_time_sec")

  if (cycle_time_sec == 0) {
    stop("cycle_time_sec cannot be zero")
  }

  dppp <- (peak_width_factor * fwhm_seconds) / cycle_time_sec
  return(dppp)
}

#' Calculate Satisfaction Ratio
#'
#' Computes the proportion of values meeting a target threshold.
#'
#' @param values Numeric vector
#' @param target Numeric, target threshold
#' @param tolerance Numeric, tolerance around target (default: 0.0)
#' @param direction Character, "greater" or "within" (default: "greater")
#'
#' @return List with satisfaction_ratio, n_satisfied, n_total, threshold
#' @export
calculate_satisfaction_ratio <- function(values, target, tolerance = 0.0,
                                        direction = "greater") {
  threshold_lower <- target - tolerance
  threshold_upper <- target + tolerance

  if (direction == "greater") {
    # Values must be >= threshold_lower
    meets_target <- values >= threshold_lower
  } else if (direction == "within") {
    # Values must be within [threshold_lower, threshold_upper]
    meets_target <- values >= threshold_lower & values <= threshold_upper
  } else {
    stop("direction must be 'greater' or 'within'")
  }

  # Keep all three outputs mutually consistent: the ratio is over the VALID
  # (non-NA) values, so n_total must be the non-NA count -- otherwise
  # n_satisfied / n_total disagrees with satisfaction_ratio when values (e.g.
  # DPPP from a missing FWHM) contain NAs.
  n_satisfied <- sum(meets_target, na.rm = TRUE)
  n_total <- sum(!is.na(values))
  satisfaction_ratio <- if (n_total > 0) n_satisfied / n_total else NA_real_

  list(
    satisfaction_ratio = satisfaction_ratio,
    n_satisfied = n_satisfied,
    n_total = n_total,
    threshold_lower = threshold_lower,
    threshold_upper = if (direction == "within") threshold_upper else NULL,
    meets_target = meets_target
  )
}


#' Compute DPPP Satisfaction Percentage
#'
#' Returns the percentage of DPPP values meeting the target threshold.
#' Convenience wrapper used across visualization and planning modules
#' to avoid scattered \code{mean(dppp >= target, na.rm = TRUE) * 100} patterns.
#'
#' @param dppp_values Numeric vector of DPPP values
#' @param target_dppp Numeric, target threshold
#'
#' @return Numeric scalar, percentage (0-100)
#' @keywords internal
dppp_satisfaction_pct <- function(dppp_values, target_dppp) {
  mean(dppp_values >= target_dppp, na.rm = TRUE) * 100
}


# =============================================================================
# FWHM Unit Conversion
# =============================================================================

#' Ensure FWHM Values Are in Seconds
#'
#' Detects whether FWHM values are in minutes (median < 1) and converts
#' to seconds if needed. Uses median-based heuristic: chromatographic FWHM
#' is typically 5-30 seconds, so a median below 1 second is physically
#' implausible and indicates minutes.
#'
#' @param fwhm_vector Numeric vector of FWHM values (may contain NAs)
#'
#' @return Numeric vector of FWHM values in seconds
#' @export
ensure_fwhm_seconds <- function(fwhm_vector) {
  fwhm_clean <- fwhm_vector[!is.na(fwhm_vector)]
  if (length(fwhm_clean) == 0) return(fwhm_vector)
  if (median(fwhm_clean) < 1) {
    return(fwhm_vector * 60)
  }
  return(fwhm_vector)
}


# =============================================================================
# Preview / Estimation Helpers
# =============================================================================

#' Estimate Window Count for Quick Preview
#'
#' Quick estimation of how many MS2 windows fit given FWHM, DPPP target,
#' and MS2 scan time. Used by Shiny preview and quick_dppp_preview.
#'
#' @param fwhm_median_sec Numeric, median FWHM in seconds
#' @param target_dppp Numeric, target data points per peak
#' @param ms2_time_sec Numeric, MS2 scan time in seconds
#' @param min_windows Integer, minimum window count (default: 10)
#' @param max_windows Integer, maximum window count (default: 200)
#'
#' @return Integer, estimated window count clamped to \code{min_windows}:\code{max_windows} range
#' @export
estimate_window_count_preview <- function(fwhm_median_sec, target_dppp, ms2_time_sec,
                                          min_windows = 10, max_windows = 200) {
  n <- floor((1.7 * fwhm_median_sec) / (target_dppp * ms2_time_sec))
  max(min_windows, min(max_windows, n))
}
