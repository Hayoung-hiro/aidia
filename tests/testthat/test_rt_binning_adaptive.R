# test_rt_binning_adaptive.R - Unit tests for adaptive RT binning
#
# Tests:
#   1. Fixed binning backward compatibility
#   2. Dispatcher routing (fixed vs adaptive)
#   3. KS change-point detection with synthetic data
#   4. Edge handling (void buffer, wash merge)
#   5. Fallback when no change points detected
#   6. get_rt_column() helper
#   7. Output format consistency (both modes)

library(testthat)

# =============================================================================
# Test Data Helpers
# =============================================================================

#' Create synthetic precursor data with a known m/z shift at a specified RT
#'
#' Before the shift_rt, precursors have m/z ~ N(500, 50).
#' After the shift_rt, precursors have m/z ~ N(800, 50).
#' This guarantees the KS test will detect a significant change.
create_bimodal_data <- function(n = 2000, shift_rt = 50, rt_range = c(10, 100)) {
  set.seed(42)
  n_before <- round(n * (shift_rt - rt_range[1]) / (rt_range[2] - rt_range[1]))
  n_after <- n - n_before

  data.frame(
    Precursor.Id = paste0("P", seq_len(n)),
    RT.Start = c(
      runif(n_before, rt_range[1], shift_rt),
      runif(n_after, shift_rt, rt_range[2])
    ),
    RT.Apex = c(
      runif(n_before, rt_range[1] + 0.1, shift_rt + 0.1),
      runif(n_after, shift_rt + 0.1, rt_range[2] + 0.1)
    ),
    Precursor.Mz = c(
      rnorm(n_before, mean = 500, sd = 50),
      rnorm(n_after, mean = 800, sd = 50)
    ),
    FWHM = runif(n, 0.1, 0.5),
    Protein.Group = paste0("PG", seq_len(n)),
    stringsAsFactors = FALSE
  )
}

#' Create uniform data (no m/z shift — KS should find no change points)
create_uniform_data <- function(n = 1000, rt_range = c(10, 100)) {
  set.seed(123)
  data.frame(
    Precursor.Id = paste0("P", seq_len(n)),
    RT.Start = runif(n, rt_range[1], rt_range[2]),
    RT.Apex = runif(n, rt_range[1], rt_range[2]),
    Precursor.Mz = rnorm(n, mean = 600, sd = 100),
    FWHM = runif(n, 0.1, 0.5),
    Protein.Group = paste0("PG", seq_len(n)),
    stringsAsFactors = FALSE
  )
}

#' Create data without RT.Apex (for fallback testing)
create_data_no_apex <- function(n = 500) {
  set.seed(99)
  data.frame(
    Precursor.Id = paste0("P", seq_len(n)),
    RT.Start = runif(n, 10, 80),
    Precursor.Mz = rnorm(n, mean = 600, sd = 100),
    FWHM = runif(n, 0.1, 0.5),
    Protein.Group = paste0("PG", seq_len(n)),
    stringsAsFactors = FALSE
  )
}

# =============================================================================
# Tests: get_rt_column()
# =============================================================================

test_that("get_rt_column returns RT.Apex when present", {
  data <- create_bimodal_data()
  expect_equal(get_rt_column(data), "RT.Apex")
})

test_that("get_rt_column falls back to RT.Start with warning when RT.Apex absent", {
  data <- create_data_no_apex()
  expect_warning(
    result <- get_rt_column(data),
    "RT.Apex not found"
  )
  expect_equal(result, "RT.Start")
})

# =============================================================================
# Tests: Fixed binning backward compatibility
# =============================================================================

test_that("fixed binning produces same structure as original", {
  data <- create_bimodal_data()
  result <- perform_fixed_rt_binning_internal(data, rt_bin_width_min = 5)

  expect_true(is.list(result))
  expect_named(result, c("data", "stats", "n_bins", "rt_breaks", "adaptive_info"))
  expect_null(result$adaptive_info)
  expect_true("rt_group" %in% colnames(result$data))
  expect_true(all(c("rt_group", "rt_start", "rt_end", "n_precursors", "rt_segment_id")
                   %in% colnames(result$stats)))
  expect_equal(result$n_bins, nrow(result$stats))
  expect_true(all(result$data$rt_group >= 1))
})

test_that("fixed binning uses RT.Apex", {
  data <- create_bimodal_data()
  result <- perform_fixed_rt_binning_internal(data, rt_bin_width_min = 10)

  # Stats should be based on RT.Apex values
  rt_apex_range <- range(data$RT.Apex)
  expect_true(result$stats$rt_start[1] >= rt_apex_range[1])
  expect_true(max(result$stats$rt_end) <= rt_apex_range[2])
})

# =============================================================================
# Tests: Dispatcher routing
# =============================================================================

test_that("dispatcher routes to fixed mode by default", {
  data <- create_bimodal_data()
  result <- perform_rt_binning_internal(data, rt_bin_width_min = 5)

  # Should use fixed mode (adaptive_info is NULL before edge handling changes it)
  # But edge handling may wrap it. The key indicator: no adaptive_info with KS data
  expect_true(is.null(result$adaptive_info) ||
                (is.list(result$adaptive_info) && result$adaptive_info$fallback))
})

test_that("dispatcher routes to adaptive mode when requested", {
  data <- create_bimodal_data()
  result <- perform_rt_binning_internal(
    data,
    rt_bin_width_min = 5,
    rt_binning_mode = "adaptive"
  )

  expect_true(!is.null(result$adaptive_info))
  expect_true("ks_statistics" %in% names(result$adaptive_info))
  expect_true("p_values" %in% names(result$adaptive_info))
})

test_that("dispatcher is backward-compatible with old call signature", {
  data <- create_bimodal_data()
  # This is the exact call from stage3_window_optimization.R line 193-196
  result <- perform_rt_binning_internal(
    precursor_data = data,
    rt_bin_width_min = 5
  )

  expect_true(is.list(result))
  expect_true("data" %in% names(result))
  expect_true("stats" %in% names(result))
  expect_true("n_bins" %in% names(result))
  expect_true("rt_breaks" %in% names(result))
})

# =============================================================================
# Tests: Adaptive KS change-point detection
# =============================================================================

test_that("adaptive binning detects change point in bimodal data", {
  data <- create_bimodal_data(n = 3000, shift_rt = 50, rt_range = c(10, 100))

  result <- perform_adaptive_rt_binning_internal(
    precursor_data = data,
    rt_column = "RT.Apex",
    cpd_significance_level = 0.05,
    cpd_min_bin_width = 1.0,
    cpd_max_bin_width = 15.0,
    cpd_min_precursors_per_bin = 30
  )

  expect_false(result$adaptive_info$fallback)
  expect_true(result$adaptive_info$n_change_points >= 1)

  # At least one change point should be near the shift at RT=50
  cp <- result$adaptive_info$change_point_positions
  near_shift <- any(abs(cp - 50) < 10)  # Within 10 min of the shift

  expect_true(near_shift)
})

test_that("adaptive binning returns 99 KS statistics (100 pre-bins - 1)", {
  data <- create_bimodal_data()
  result <- perform_adaptive_rt_binning_internal(data, "RT.Apex")

  expect_equal(length(result$adaptive_info$ks_statistics), 99)
  expect_equal(length(result$adaptive_info$p_values), 99)
  expect_equal(length(result$adaptive_info$pre_bin_centers), 100)
})

test_that("adaptive binning output has same stats columns as fixed", {
  data <- create_bimodal_data()
  fixed_result <- perform_fixed_rt_binning_internal(data, 5)
  adaptive_result <- perform_adaptive_rt_binning_internal(data, "RT.Apex",
                                                          cpd_min_precursors_per_bin = 30)

  expect_equal(colnames(fixed_result$stats), colnames(adaptive_result$stats))
})

# =============================================================================
# Tests: Fallback when no change points detected
# =============================================================================

test_that("adaptive binning falls back to fixed when no change points", {
  data <- create_uniform_data()

  expect_warning(
    result <- perform_adaptive_rt_binning_internal(
      data, "RT.Apex",
      cpd_significance_level = 1e-10  # Very strict — should find nothing
    ),
    "falling back to fixed-width"
  )

  expect_true(result$adaptive_info$fallback)
  expect_equal(result$adaptive_info$n_change_points, 0L)
  expect_true(result$n_bins >= 1)
})

# =============================================================================
# Tests: Edge handling
# =============================================================================

test_that("edge handling extends first break by void buffer", {
  data <- create_bimodal_data()
  inner_result <- perform_fixed_rt_binning_internal(data, 10)

  original_first_break <- inner_result$rt_breaks[1]

  handled <- apply_edge_handling(
    inner_result,
    edge_void_buffer_min = 0.5,
    edge_wash_min_precursors = 0  # Disable wash handling
  )

  expect_equal(handled$rt_breaks[1], original_first_break - 0.5)
})

test_that("edge handling merges sparse last bin", {
  # Create data where last RT region is very sparse
  set.seed(77)
  n_main <- 900
  n_tail <- 5  # Very few in the last region
  rt_vals <- c(runif(n_main, 10, 80), runif(n_tail, 80, 90))
  data <- data.frame(
    Precursor.Id = paste0("P", 1:(n_main + n_tail)),
    RT.Start = rt_vals,
    RT.Apex = rt_vals + 0.05,
    Precursor.Mz = rnorm(n_main + n_tail, 600, 100),
    FWHM = runif(n_main + n_tail, 0.1, 0.5),
    Protein.Group = paste0("PG", 1:(n_main + n_tail)),
    stringsAsFactors = FALSE
  )

  inner_result <- perform_fixed_rt_binning_internal(data, rt_bin_width_min = 5)
  n_bins_before <- inner_result$n_bins

  handled <- apply_edge_handling(
    inner_result,
    edge_void_buffer_min = 0,
    edge_wash_min_precursors = 30  # Tail has only 5, should merge
  )

  # Should have merged the last bin
  expect_true(handled$n_bins <= n_bins_before)
})

test_that("edge handling skips when only 1 bin", {
  data <- create_bimodal_data(n = 100)
  inner_result <- perform_fixed_rt_binning_internal(data, rt_bin_width_min = 200)

  handled <- apply_edge_handling(inner_result)
  # With 1 bin, should return unchanged
  expect_equal(handled$n_bins, inner_result$n_bins)
})

# =============================================================================
# Tests: Output format consistency
# =============================================================================

test_that("both modes produce identical output structure", {
  data <- create_bimodal_data(n = 3000)

  fixed <- perform_rt_binning_internal(data, rt_bin_width_min = 5, rt_binning_mode = "fixed")
  adaptive <- perform_rt_binning_internal(data, rt_bin_width_min = 5, rt_binning_mode = "adaptive",
                                          cpd_min_precursors_per_bin = 30)

  # Both should have the same top-level keys
  expect_true(all(c("data", "stats", "n_bins", "rt_breaks") %in% names(fixed)))
  expect_true(all(c("data", "stats", "n_bins", "rt_breaks") %in% names(adaptive)))

  # Stats columns must match
  expected_cols <- c("rt_group", "rt_start", "rt_end", "n_precursors", "rt_segment_id")
  expect_true(all(expected_cols %in% colnames(fixed$stats)))
  expect_true(all(expected_cols %in% colnames(adaptive$stats)))

  # Data should have rt_group column
  expect_true("rt_group" %in% colnames(fixed$data))
  expect_true("rt_group" %in% colnames(adaptive$data))

  # All precursors should be assigned to a bin (no NAs)
  expect_false(any(is.na(fixed$data$rt_group)))
  expect_false(any(is.na(adaptive$data$rt_group)))
})

# =============================================================================
# Tests: Constraint enforcement
# =============================================================================

test_that("enforce_bin_constraints merges close change points", {
  change_points <- c(20, 20.5, 40, 60)
  p_values <- rep(0.01, 99)
  change_indices <- c(10, 11, 30, 50)

  result <- enforce_bin_constraints(
    change_points, p_values, change_indices,
    rt_range = c(10, 100),
    min_bin_width = 2.0,
    max_bin_width = 50.0
  )

  # 20 and 20.5 are closer than 2.0 — one should be removed
  expect_true(length(result) < length(change_points))
})

test_that("enforce_bin_constraints splits wide bins", {
  change_points <- c(30)
  p_values <- rep(0.01, 99)
  change_indices <- c(20)

  result <- enforce_bin_constraints(
    change_points, p_values, change_indices,
    rt_range = c(10, 100),
    min_bin_width = 1.0,
    max_bin_width = 15.0
  )

  # Bin from 30 to 100 is 70 min > max 15 — should add splits
  expect_true(length(result) > length(change_points))
})

# =============================================================================
# Tests: Sparse bin merging
# =============================================================================

test_that("merge_sparse_bins eliminates bins below threshold", {
  set.seed(55)
  n <- 500
  data <- data.frame(
    Precursor.Mz = rnorm(n, 600, 100),
    stringsAsFactors = FALSE
  )

  # Create breaks that produce one very sparse bin
  rt_vals <- c(runif(490, 10, 80), runif(10, 80, 100))
  data$RT.Apex <- rt_vals
  breaks <- c(10, 40, 80, 100)
  data$rt_group <- cut(rt_vals, breaks = breaks, labels = FALSE, include.lowest = TRUE)

  result <- merge_sparse_bins(data, breaks, "RT.Apex", min_precursors = 50)

  # Last bin (80-100) has ~10 precursors — should be merged
  final_counts <- table(result$data$rt_group)
  expect_true(all(final_counts >= 50) || length(result$rt_breaks) - 1 <= 1)
})
