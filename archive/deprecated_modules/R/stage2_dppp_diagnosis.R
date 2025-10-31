# stage2_dppp_diagnosis.R - Stage 2: DPPP Diagnosis (Corrected Logic)
# DIA Window Optimizer v2.0
#
# Purpose: Diagnose current DPPP status and calculate required cycle time
#
# Scope:
#   Step 1: Analyze current DPPP distribution with existing cycle_time
#   Step 2: Calculate required cycle_time for target satisfaction
#
# Out of Scope (deferred to Phase 3A):
#   - Window count calculation
#   - Instrument feasibility checks
#   - DPPP validation with new cycle_time
#   - Injection time optimization

library(dplyr)
library(tibble)
library(ggplot2)

PEAK_WIDTH_FACTOR <- 1.7  # Chromatographic peak width ≈ 1.7 × FWHM

#' Stage 2: DPPP Diagnosis
#'
#' Analyzes current DPPP distribution and calculates required cycle time
#' to achieve target DPPP satisfaction.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param current_cycle_time Current cycle time in seconds (from existing experiment)
#' @param target_dppp Target minimum DPPP value (default: 7.0)
#' @param target_satisfaction Target satisfaction ratio (default: 0.85 = 85%)
#' @param dppp_tolerance Tolerance for "close enough" (default: 0.0 = strict)
#'
#' @return DiagnosisResult object with current_state and recommendation
#' @export
diagnose_dppp_status <- function(
  validated_data,
  current_cycle_time,
  target_dppp = 7.0,
  target_satisfaction = 0.85,
  dppp_tolerance = 0.0
) {

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   STAGE 2: DPPP Diagnosis                    ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  start_time <- Sys.time()

  # Validate input
  if (!inherits(validated_data, "ValidatedData")) {
    stop("Input must be ValidatedData object from Stage 1")
  }

  if (current_cycle_time <= 0) {
    stop("current_cycle_time must be positive")
  }

  # Extract data
  fwhm_minutes <- validated_data$data$FWHM
  fwhm_seconds <- fwhm_minutes * 60
  n_precursors <- length(fwhm_seconds)

  cat(sprintf("Analyzing %d precursors\n", n_precursors))
  cat(sprintf("FWHM range: %.2f - %.2f sec (median: %.2f sec)\n",
              min(fwhm_seconds), max(fwhm_seconds), median(fwhm_seconds)))

  # ============================================================
  # STEP 1: Current State Analysis
  # ============================================================
  cat("\n─── Step 1: Current State Analysis ───\n")
  cat(sprintf("Current cycle time: %.3f sec\n", current_cycle_time))

  current_state <- calculate_current_dppp_distribution(
    validated_data = validated_data,
    cycle_time_sec = current_cycle_time,
    target_dppp = target_dppp,
    tolerance = dppp_tolerance
  )

  cat(sprintf("\nCurrent DPPP distribution:\n"))
  cat(sprintf("  Mean: %.2f, Median: %.2f\n",
              current_state$dppp_stats$mean,
              current_state$dppp_stats$median))
  cat(sprintf("  Range: %.2f - %.2f\n",
              current_state$dppp_stats$min,
              current_state$dppp_stats$max))

  cat(sprintf("\nCurrent satisfaction (DPPP ≥ %.1f):\n", target_dppp))
  cat(sprintf("  %.1f%% (%d / %d precursors)\n",
              current_state$satisfaction_ratio * 100,
              current_state$n_satisfied,
              current_state$n_total))

  # User guidance
  if (current_state$satisfaction_ratio >= target_satisfaction) {
    cat(sprintf("\n✅ ALREADY MEETING TARGET (%.1f%% ≥ %.0f%%)\n",
                current_state$satisfaction_ratio * 100,
                target_satisfaction * 100))
    cat("   → Current cycle_time is acceptable\n")
    cat("   → Consider: Reduce cycle_time for even higher DPPP\n")
  } else {
    cat(sprintf("\n⚠️  BELOW TARGET (%.1f%% < %.0f%%)\n",
                current_state$satisfaction_ratio * 100,
                target_satisfaction * 100))
    cat(sprintf("   → Need to improve DPPP for %.1f%% more precursors\n",
                (target_satisfaction - current_state$satisfaction_ratio) * 100))
  }

  # ============================================================
  # STEP 2: Required Cycle Time Calculation
  # ============================================================
  cat("\n─── Step 2: Required Cycle Time Calculation ───\n")
  cat(sprintf("Goal: DPPP ≥ %.1f for %.0f%% of precursors\n\n",
              target_dppp, target_satisfaction * 100))

  required_cycle_time <- calculate_required_cycle_time(
    fwhm_minutes = fwhm_minutes,
    target_dppp = target_dppp,
    target_satisfaction = target_satisfaction
  )

  cat(sprintf("\n📊 RECOMMENDATION:\n"))
  cat(sprintf("   Current cycle time: %.3f sec\n", current_cycle_time))
  cat(sprintf("   Required cycle time: ≤ %.3f sec\n", required_cycle_time))

  adjustment_needed <- abs(required_cycle_time - current_cycle_time) > 0.01

  if (required_cycle_time < current_cycle_time) {
    cat(sprintf("   → Need to REDUCE cycle time by %.3f sec (%.1f%%)\n",
                current_cycle_time - required_cycle_time,
                (1 - required_cycle_time / current_cycle_time) * 100))
    cat("\n   💡 Options to achieve this in Phase 3A:\n")
    cat("      1. Reduce injection time → more windows fit in shorter cycle\n")
    cat("      2. Reduce window count → shorter total scan time\n")
    cat("      3. Combination of both\n")
    adjustment_direction <- "REDUCE"

  } else if (required_cycle_time > current_cycle_time) {
    cat(sprintf("   → Can INCREASE cycle time by up to %.3f sec (%.1f%%)\n",
                required_cycle_time - current_cycle_time,
                (required_cycle_time / current_cycle_time - 1) * 100))
    cat("\n   💡 Benefits:\n")
    cat("      1. Longer injection time → better spectrum quality\n")
    cat("      2. More windows → better coverage\n")
    adjustment_direction <- "INCREASE"

  } else {
    cat("   → Current cycle time is OPTIMAL\n")
    adjustment_direction <- "MAINTAIN"
  }

  # ============================================================
  # Construct Result
  # ============================================================

  processing_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  result <- structure(
    list(
      current_state = current_state,

      recommendation = list(
        target_dppp = target_dppp,
        target_satisfaction = target_satisfaction,
        required_cycle_time_sec = required_cycle_time,
        current_cycle_time_sec = current_cycle_time,
        needs_adjustment = adjustment_needed,
        adjustment_direction = adjustment_direction,
        adjustment_magnitude_sec = abs(required_cycle_time - current_cycle_time),
        adjustment_magnitude_pct = abs(required_cycle_time / current_cycle_time - 1) * 100
      ),

      metadata = list(
        n_precursors = n_precursors,
        fwhm_median_sec = median(fwhm_seconds),
        fwhm_range_sec = c(min(fwhm_seconds), max(fwhm_seconds)),
        mz_range = validated_data$metadata$mz_range,
        analysis_timestamp = Sys.time(),
        processing_time_sec = processing_time
      )
    ),
    class = c("DiagnosisResult", "list")
  )

  cat("\n═══ STAGE 2 COMPLETE ═══\n")
  cat(sprintf("Processing time: %.2f sec\n", processing_time))
  cat("\n📋 Next: Proceed to Phase 3A (Window Count Determination)\n")
  cat(sprintf("   Input required_cycle_time = %.3f sec into Phase 3A\n", required_cycle_time))

  return(result)
}


# =====================================================
# Helper Functions
# =====================================================

#' Calculate Current DPPP Distribution
#'
#' Calculates DPPP for all precursors using existing cycle_time
#' and computes satisfaction ratio.
#'
#' @param validated_data ValidatedData object
#' @param cycle_time_sec Cycle time in seconds
#' @param target_dppp Target minimum DPPP
#' @param tolerance Tolerance for satisfaction
#' @return List with DPPP distribution and statistics
calculate_current_dppp_distribution <- function(
  validated_data,
  cycle_time_sec,
  target_dppp,
  tolerance = 0.0
) {

  fwhm_seconds <- validated_data$data$FWHM * 60

  # Calculate DPPP for all precursors
  # DPPP = (1.7 × FWHM_sec) / cycle_time_sec
  dppp_values <- (PEAK_WIDTH_FACTOR * fwhm_seconds) / cycle_time_sec

  # Compute satisfaction (CORRECTED LOGIC: >= target only)
  sat_result <- compute_satisfaction_ratio(dppp_values, target_dppp, tolerance)

  # Statistics
  dppp_stats <- list(
    mean = mean(dppp_values, na.rm = TRUE),
    median = median(dppp_values, na.rm = TRUE),
    sd = sd(dppp_values, na.rm = TRUE),
    min = min(dppp_values, na.rm = TRUE),
    max = max(dppp_values, na.rm = TRUE),
    p25 = quantile(dppp_values, 0.25, na.rm = TRUE),
    p75 = quantile(dppp_values, 0.75, na.rm = TRUE)
  )

  return(list(
    cycle_time_sec = cycle_time_sec,
    dppp_values = dppp_values,
    dppp_stats = dppp_stats,
    satisfaction_ratio = sat_result$satisfaction_ratio,
    n_satisfied = sat_result$n_satisfied,
    n_total = sat_result$n_total,
    distribution = tibble(
      precursor_id = seq_along(dppp_values),
      rt = validated_data$data$RT.Start,
      mz = validated_data$data$Precursor.Mz,
      fwhm_sec = fwhm_seconds,
      dppp_value = dppp_values,
      meets_target = sat_result$meets_target
    )
  ))
}


#' Calculate Required Cycle Time for Target DPPP
#'
#' Finds the MAXIMUM cycle time that achieves target DPPP satisfaction.
#'
#' CORRECTED LOGIC:
#' - 70% satisfaction means rescue 70%, abandon bottom 30%
#' - Use (1 - target_satisfaction) percentile to find critical FWHM
#' - This is the shortest FWHM among the "rescued" precursors
#'
#' @param fwhm_minutes FWHM vector in minutes
#' @param target_dppp Target minimum DPPP
#' @param target_satisfaction Target satisfaction ratio (e.g., 0.70)
#' @return Required maximum cycle time in seconds
calculate_required_cycle_time <- function(
  fwhm_minutes,
  target_dppp,
  target_satisfaction
) {

  fwhm_seconds <- fwhm_minutes * 60

  # ========================================
  # CRITICAL FIX: Use (1 - target_satisfaction) percentile
  # ========================================
  #
  # DPPP = (1.7 × FWHM) / cycle_time
  #
  # Short FWHM → Low DPPP (hard to achieve target)
  # Long FWHM → High DPPP (easy to achieve target)
  #
  # 70% satisfaction:
  # - Rescue top 70% (longer FWHM)
  # - Abandon bottom 30% (shortest FWHM)
  # - Find the shortest FWHM among rescued 70% = 30th percentile

  critical_percentile <- 1 - target_satisfaction
  fwhm_critical <- quantile(fwhm_seconds, critical_percentile)

  cat(sprintf("  Critical FWHM (%.0f-percentile): %.2f sec\n",
              critical_percentile * 100, fwhm_critical))
  cat(sprintf("  → This represents the shortest FWHM among the top %.0f%% precursors\n",
              target_satisfaction * 100))

  # Calculate MAXIMUM cycle time that achieves target DPPP for this critical FWHM
  # DPPP = (1.7 × FWHM) / cycle_time
  # → cycle_time = (1.7 × FWHM) / DPPP

  required_max_cycle_time <- (PEAK_WIDTH_FACTOR * fwhm_critical) / target_dppp

  cat(sprintf("  → To achieve DPPP ≥ %.1f for this critical FWHM:\n", target_dppp))
  cat(sprintf("     cycle_time ≤ (%.1f × %.2f) / %.1f = %.3f sec\n",
              PEAK_WIDTH_FACTOR, fwhm_critical, target_dppp, required_max_cycle_time))

  return(required_max_cycle_time)
}


#' Compute DPPP Satisfaction Ratio (Corrected Logic)
#'
#' Calculates the proportion of precursors meeting target DPPP.
#'
#' CORRECTED LOGIC:
#' - Target DPPP is a MINIMUM threshold
#' - Higher DPPP is better (better quantification)
#' - No upper limit
#'
#' @param dppp_values Vector of DPPP values
#' @param target_dppp Target minimum DPPP
#' @param tolerance Tolerance for "close enough" (default: 0.0 = strict)
#' @return List with satisfaction metrics
compute_satisfaction_ratio <- function(
  dppp_values,
  target_dppp,
  tolerance = 0.0
) {

  # CORRECTED LOGIC:
  # Target DPPP is MINIMUM acceptable value
  # Higher DPPP = better quantification
  # No upper limit

  threshold <- target_dppp - tolerance
  meets_target <- dppp_values >= threshold

  satisfaction_ratio <- mean(meets_target, na.rm = TRUE)
  n_satisfied <- sum(meets_target, na.rm = TRUE)
  n_total <- length(dppp_values)

  return(list(
    satisfaction_ratio = satisfaction_ratio,
    n_satisfied = n_satisfied,
    n_total = n_total,
    threshold = threshold,
    meets_target = meets_target
  ))
}


# =====================================================
# S3 Methods for DiagnosisResult
# =====================================================

#' Print method for DiagnosisResult
#'
#' @param x DiagnosisResult object
#' @param ... Additional arguments
#' @export
print.DiagnosisResult <- function(x, ...) {
  cat("DiagnosisResult object\n")
  cat(sprintf("  Current cycle time: %.3f sec\n",
              x$recommendation$current_cycle_time_sec))
  cat(sprintf("  Required cycle time: %.3f sec\n",
              x$recommendation$required_cycle_time_sec))
  cat(sprintf("  Adjustment needed: %s\n",
              ifelse(x$recommendation$needs_adjustment,
                     x$recommendation$adjustment_direction,
                     "NO")))
  cat(sprintf("  Current satisfaction: %.1f%%\n",
              x$current_state$satisfaction_ratio * 100))

  invisible(x)
}


#' Summary method for DiagnosisResult
#'
#' @param object DiagnosisResult object
#' @param ... Additional arguments
#' @export
summary.DiagnosisResult <- function(object, ...) {
  cat("╔═══════════════════════════════════════════════╗\n")
  cat("║   Diagnosis Summary                          ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  cat("Current State:\n")
  cat(sprintf("  Cycle time: %.3f sec\n", object$current_state$cycle_time_sec))
  cat(sprintf("  Mean DPPP: %.2f\n", object$current_state$dppp_stats$mean))
  cat(sprintf("  Median DPPP: %.2f\n", object$current_state$dppp_stats$median))
  cat(sprintf("  Range: %.2f - %.2f\n",
              object$current_state$dppp_stats$min,
              object$current_state$dppp_stats$max))
  cat(sprintf("  Satisfaction: %.1f%% (target: %.0f%%)\n",
              object$current_state$satisfaction_ratio * 100,
              object$recommendation$target_satisfaction * 100))

  cat("\nRecommendation:\n")
  cat(sprintf("  Target DPPP: ≥ %.1f\n", object$recommendation$target_dppp))
  cat(sprintf("  Required cycle time: ≤ %.3f sec\n",
              object$recommendation$required_cycle_time_sec))

  if (object$recommendation$needs_adjustment) {
    cat(sprintf("  Action: %s by %.3f sec (%.1f%%)\n",
                object$recommendation$adjustment_direction,
                object$recommendation$adjustment_magnitude_sec,
                object$recommendation$adjustment_magnitude_pct))
  } else {
    cat("  Action: No adjustment needed\n")
  }

  cat("\nData Summary:\n")
  cat(sprintf("  Precursors: %d\n", object$metadata$n_precursors))
  cat(sprintf("  FWHM median: %.2f sec\n", object$metadata$fwhm_median_sec))
  cat(sprintf("  m/z range: %.1f - %.1f Da\n",
              object$metadata$mz_range[1], object$metadata$mz_range[2]))

  invisible(object)
}


# =====================================================
# Visualization Functions
# =====================================================

#' Plot DPPP Distribution Histogram
#'
#' Creates a histogram showing DPPP distribution with target threshold
#' and satisfaction metrics.
#'
#' @param diagnosis_result DiagnosisResult object from diagnose_dppp_status()
#' @param output_file Optional file path to save the plot (PNG format)
#' @param width Plot width in inches (default: 10)
#' @param height Plot height in inches (default: 6)
#' @param dpi Resolution for PNG output (default: 300)
#' @return ggplot object
#' @export
plot_dppp_histogram <- function(
  diagnosis_result,
  output_file = NULL,
  width = 10,
  height = 6,
  dpi = 300
) {

  # Validate input
  if (!inherits(diagnosis_result, "DiagnosisResult")) {
    stop("Input must be a DiagnosisResult object")
  }

  # Extract data
  dppp_values <- diagnosis_result$current_state$dppp_values
  target_dppp <- diagnosis_result$recommendation$target_dppp
  cycle_time <- diagnosis_result$current_state$cycle_time_sec
  satisfaction <- diagnosis_result$current_state$satisfaction_ratio
  dppp_median <- diagnosis_result$current_state$dppp_stats$median
  tolerance <- diagnosis_result$recommendation$target_dppp * 0.08  # 8% tolerance for display

  # Create data frame for plotting
  plot_data <- data.frame(dppp = dppp_values)

  # Calculate histogram breaks for better visualization
  breaks <- seq(0, max(dppp_values) * 1.1, length.out = 50)

  # Create the plot
  p <- ggplot(plot_data, aes(x = dppp)) +
    # Histogram
    geom_histogram(
      bins = 50,
      fill = "steelblue",
      color = "white",
      alpha = 0.7
    ) +

    # Density curve overlay
    geom_density(
      aes(y = after_stat(count)),
      color = "red",
      linewidth = 1.5,
      alpha = 0.8
    ) +

    # Target DPPP threshold (green dashed line)
    geom_vline(
      xintercept = target_dppp,
      color = "darkgreen",
      linetype = "dashed",
      linewidth = 1.5
    ) +

    # Median DPPP (yellow dashed line)
    geom_vline(
      xintercept = dppp_median,
      color = "gold",
      linetype = "dashed",
      linewidth = 1.5
    ) +

    # Labels and theme
    labs(
      title = "DPPP Distribution Analysis",
      subtitle = sprintf(
        "Scan time: %.2f sec | Target DPPP: %.2f ± %.2f | Satisfaction: %.1f%%",
        cycle_time,
        target_dppp,
        tolerance,
        satisfaction * 100
      ),
      x = "DPPP (Data Points Per Peak)",
      y = "Count"
    ) +

    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(size = 18, face = "bold", hjust = 0),
      plot.subtitle = element_text(size = 12, hjust = 0),
      axis.title = element_text(size = 14, face = "bold"),
      axis.text = element_text(size = 12),
      panel.grid.major = element_line(color = "gray90"),
      panel.grid.minor = element_line(color = "gray95"),
      plot.margin = margin(20, 20, 20, 20)
    ) +

    # Add annotations
    annotate(
      "text",
      x = target_dppp,
      y = max(table(cut(dppp_values, breaks = breaks))) * 0.95,
      label = sprintf("Target\nDPPP: %.1f", target_dppp),
      color = "darkgreen",
      size = 4,
      hjust = -0.1,
      fontface = "bold"
    ) +

    annotate(
      "text",
      x = dppp_median,
      y = max(table(cut(dppp_values, breaks = breaks))) * 0.85,
      label = sprintf("Median\nDPPP: %.1f", dppp_median),
      color = "gold4",
      size = 4,
      hjust = -0.1,
      fontface = "bold"
    )

  # Save to file if requested
  if (!is.null(output_file)) {
    ggsave(
      filename = output_file,
      plot = p,
      width = width,
      height = height,
      dpi = dpi,
      bg = "white"
    )
    cat(sprintf("✅ DPPP histogram saved: %s\n", output_file))
  }

  return(p)
}
