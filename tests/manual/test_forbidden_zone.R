# test_forbidden_zone.R - Forbidden Zone Window Placement Optimization Test
#
# Purpose: Verify forbidden zone boundary snapping works across all window modes
#          (fixed, density, staggered) with various fz_offset values.
#
# Usage: Rscript tests/manual/test_forbidden_zone.R

library(dplyr)
library(tibble)

devtools::load_all("D:/Projects/aidia")

cat("\n")
cat("==================================================================\n")
cat("  TEST: Forbidden Zone Window Placement - All Modes\n")
cat("==================================================================\n\n")

# Track pass/fail
tests_passed <- 0
tests_failed <- 0

pass <- function(msg) {
  tests_passed <<- tests_passed + 1
  cat(sprintf("  [PASS] %s\n", msg))
}

fail <- function(msg) {
  tests_failed <<- tests_failed + 1
  cat(sprintf("  [FAIL] %s\n", msg))
}

# ============================================================================
# Step 0: Create mock ValidatedData (~500 precursors)
# ============================================================================

cat("--- Step 0: Create mock ValidatedData ---\n")

set.seed(42)
n <- 500

mock_data <- tibble(
  Precursor.Id = paste0("Precursor_", seq_len(n)),
  Precursor.Mz = runif(n, min = 400, max = 1200),
  RT.Apex      = runif(n, min = 5, max = 60),
  FWHM         = runif(n, min = 0.08, max = 0.25)
)

validated_data <- as_ValidatedData(mock_data)

# Create optimization plan (Astral, quant mode)
plan <- plan_optimization(
  validated_data = validated_data,
  instrument_preset = "astral",
  target_dppp = 7.0,
  target_satisfaction = 0.70
)

cat(sprintf("  Mock data: %d precursors, %d windows/bin\n",
            nrow(mock_data), plan$window_count_per_bin))

# ============================================================================
# Helper: Check if boundary is at a forbidden zone
# ============================================================================

is_at_forbidden_zone <- function(mz_val, fz_offset = 0.25, tolerance = 0.01) {
  optimal_increment <- 1.00045475
  # A forbidden zone edge satisfies: mz = ceil(x / inc) * inc + fz_offset
  # Check: (mz - fz_offset) is close to a multiple of optimal_increment
  shifted <- mz_val - fz_offset
  remainder <- shifted %% optimal_increment
  remainder < tolerance || (optimal_increment - remainder) < tolerance
}

# ============================================================================
# Test 1: Fixed mode + forbidden zone (0.25)
# ============================================================================

cat("\n--- Test 1: Fixed + Forbidden Zone (0.25) ---\n")

result_fixed_fz <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = plan,
  mz_strategy = "greedy",
  window_mode = "fixed",
  fz_offset = 0.25
)

windows_fixed <- result_fixed_fz$windows

# Check all boundaries are at forbidden zones
boundaries <- c(windows_fixed$mz_start, windows_fixed$mz_end)
at_fz <- vapply(boundaries, is_at_forbidden_zone, logical(1), fz_offset = 0.25)
fz_pct <- mean(at_fz) * 100

if (fz_pct == 100) {
  pass(sprintf("Fixed+FZ(0.25): %.1f%% boundaries at forbidden zones", fz_pct))
} else {
  fail(sprintf("Fixed+FZ(0.25): Only %.1f%% boundaries at forbidden zones (expected 100%%)", fz_pct))
}

# Check all windows have positive width
if (all(windows_fixed$window_width > 0)) {
  pass("Fixed+FZ(0.25): All windows have positive width")
} else {
  fail(sprintf("Fixed+FZ(0.25): %d windows have non-positive width",
               sum(windows_fixed$window_width <= 0)))
}

# ============================================================================
# Test 2: Fixed mode + forbidden zone (0.18, phospho)
# ============================================================================

cat("\n--- Test 2: Fixed + Forbidden Zone (0.18, Phospho) ---\n")

result_fixed_phospho <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = plan,
  mz_strategy = "greedy",
  window_mode = "fixed",
  fz_offset = 0.18
)

windows_phospho <- result_fixed_phospho$windows

boundaries_p <- c(windows_phospho$mz_start, windows_phospho$mz_end)
at_fz_p <- vapply(boundaries_p, is_at_forbidden_zone, logical(1), fz_offset = 0.18)
fz_pct_p <- mean(at_fz_p) * 100

if (fz_pct_p == 100) {
  pass(sprintf("Fixed+FZ(0.18): %.1f%% boundaries at forbidden zones", fz_pct_p))
} else {
  fail(sprintf("Fixed+FZ(0.18): Only %.1f%% boundaries at forbidden zones (expected 100%%)", fz_pct_p))
}

# Verify 0.18 boundaries differ from 0.25 boundaries
if (!identical(windows_fixed$mz_start, windows_phospho$mz_start)) {
  pass("Fixed: 0.18 vs 0.25 produce different boundaries")
} else {
  fail("Fixed: 0.18 and 0.25 produce identical boundaries (should differ)")
}

# ============================================================================
# Test 3: Density mode + forbidden zone
# ============================================================================

cat("\n--- Test 3: Density + Forbidden Zone (0.25) ---\n")

result_density_fz <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = plan,
  mz_strategy = "greedy",
  window_mode = "density",
  fz_offset = 0.25
)

windows_density <- result_density_fz$windows

boundaries_d <- c(windows_density$mz_start, windows_density$mz_end)
at_fz_d <- vapply(boundaries_d, is_at_forbidden_zone, logical(1), fz_offset = 0.25)
fz_pct_d <- mean(at_fz_d) * 100

if (fz_pct_d == 100) {
  pass(sprintf("Density+FZ(0.25): %.1f%% boundaries at forbidden zones", fz_pct_d))
} else {
  fail(sprintf("Density+FZ(0.25): Only %.1f%% boundaries at forbidden zones (expected 100%%)", fz_pct_d))
}

if (all(windows_density$window_width > 0)) {
  pass("Density+FZ(0.25): All windows have positive width")
} else {
  fail(sprintf("Density+FZ(0.25): %d windows have non-positive width",
               sum(windows_density$window_width <= 0)))
}

# ============================================================================
# Test 4: fz_offset = 0 (disabled, no snap)
# ============================================================================

cat("\n--- Test 4: fz_offset = 0 (Disabled) ---\n")

result_no_snap <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = plan,
  mz_strategy = "greedy",
  window_mode = "fixed",
  fz_offset = 0
)

windows_no_snap <- result_no_snap$windows

# With fz_offset=0, boundaries should NOT be at forbidden zones (0.25)
# They should be at natural fixed-width boundaries
boundaries_ns <- c(windows_no_snap$mz_start, windows_no_snap$mz_end)
at_fz_ns <- vapply(boundaries_ns, is_at_forbidden_zone, logical(1), fz_offset = 0.25)
fz_pct_ns <- mean(at_fz_ns) * 100

if (fz_pct_ns < 50) {
  pass(sprintf("No snap (ptm=0): Only %.1f%% at forbidden zones (expected low)", fz_pct_ns))
} else {
  # Some may coincidentally land on forbidden zones, but should be much lower
  fail(sprintf("No snap (ptm=0): %.1f%% at forbidden zones (suspiciously high)", fz_pct_ns))
}

# ============================================================================
# Test 5: Staggered mode — unchanged behavior
# ============================================================================

cat("\n--- Test 5: Staggered Mode (Unchanged) ---\n")

result_staggered <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = plan,
  mz_strategy = "greedy",
  window_mode = "staggered",
  fz_offset = 0.25
)

windows_staggered <- result_staggered$windows

# Staggered must have cycle column
if ("cycle" %in% colnames(windows_staggered)) {
  pass("Staggered: 'cycle' column present")
} else {
  fail("Staggered: 'cycle' column missing")
}

# C1 count == C2 count per RT bin (Loop Control N integrity)
if ("cycle" %in% colnames(windows_staggered)) {
  cycle_counts <- windows_staggered %>%
    group_by(rt_segment_id, cycle) %>%
    summarise(n = n(), .groups = "drop") %>%
    tidyr::pivot_wider(names_from = cycle, values_from = n, names_prefix = "C")

  if (all(cycle_counts$C1 == cycle_counts$C2)) {
    pass(sprintf("Staggered: C1 == C2 in all %d RT bins", nrow(cycle_counts)))
  } else {
    fail("Staggered: C1 != C2 in some RT bins")
  }
}

# All staggered boundaries at forbidden zones
boundaries_s <- c(windows_staggered$mz_start, windows_staggered$mz_end)
at_fz_s <- vapply(boundaries_s, is_at_forbidden_zone, logical(1), fz_offset = 0.25)
fz_pct_s <- mean(at_fz_s) * 100

if (fz_pct_s == 100) {
  pass(sprintf("Staggered: %.1f%% boundaries at forbidden zones", fz_pct_s))
} else {
  fail(sprintf("Staggered: Only %.1f%% boundaries at forbidden zones (expected 100%%)", fz_pct_s))
}

# ============================================================================
# Test 6: Continuous coverage (within each RT bin)
# ============================================================================

cat("\n--- Test 6: Continuous Coverage Check ---\n")

check_continuous <- function(windows, mode_label, tolerance = 1e-10) {
  rt_bins <- unique(windows$rt_segment_id)
  gaps_found <- 0
  max_gap <- 0

  for (rt_id in rt_bins) {
    bin_w <- windows %>%
      filter(rt_segment_id == rt_id) %>%
      arrange(mz_start)

    # For staggered, check per cycle
    if ("cycle" %in% colnames(bin_w)) {
      for (cyc in unique(bin_w$cycle)) {
        cyc_w <- bin_w %>% filter(cycle == cyc)
        if (nrow(cyc_w) > 1) {
          for (j in 2:nrow(cyc_w)) {
            gap <- abs(cyc_w$mz_start[j] - cyc_w$mz_end[j - 1])
            max_gap <- max(max_gap, gap)
            if (gap > tolerance) gaps_found <- gaps_found + 1
          }
        }
      }
    } else {
      if (nrow(bin_w) > 1) {
        for (j in 2:nrow(bin_w)) {
          gap <- abs(bin_w$mz_start[j] - bin_w$mz_end[j - 1])
          max_gap <- max(max_gap, gap)
          if (gap > tolerance) gaps_found <- gaps_found + 1
        }
      }
    }
  }

  if (gaps_found == 0) {
    pass(sprintf("%s: Continuous coverage (max gap: %.2e, tolerance: %.0e)", mode_label, max_gap, tolerance))
  } else {
    fail(sprintf("%s: %d gaps > %.0e found (max gap: %.6f Da)", mode_label, gaps_found, tolerance, max_gap))
  }
}

check_continuous(windows_fixed, "Fixed+FZ")
check_continuous(windows_density, "Density+FZ")
check_continuous(windows_staggered, "Staggered")

# ============================================================================
# Test 7: Overlap + Forbidden Zone warning
# ============================================================================

cat("\n--- Test 7: Overlap + Forbidden Zone Warning ---\n")

tryCatch({
  warns <- character(0)
  withCallingHandlers(
    result_overlap_fz <- optimize_windows(
      validated_data = validated_data,
      optimization_plan = plan,
      mz_strategy = "greedy",
      window_mode = "fixed",
      fz_offset = 0.25,
      overlap_percentage = 10
    ),
    warning = function(w) {
      warns <<- c(warns, w$message)
      invokeRestart("muffleWarning")
    }
  )

  overlap_warns <- grep("Overlap.*conflict|overlap.*forbidden", warns,
                        value = TRUE, ignore.case = TRUE)
  if (length(overlap_warns) > 0) {
    pass("Overlap+FZ: Warning issued about conflict")
  } else {
    fail("Overlap+FZ: No warning about overlap/forbidden zone conflict")
  }
}, error = function(e) {
  fail(sprintf("Overlap+FZ: Error occurred: %s", e$message))
})

# ============================================================================
# Test 8: Degenerate window defense
# ============================================================================

cat("\n--- Test 8: Degenerate Window Defense ---\n")

# All modes with forbidden zone should produce only positive-width windows
all_positive <- all(windows_fixed$window_width > 0) &&
  all(windows_density$window_width > 0) &&
  all(windows_staggered$window_width > 0)

if (all_positive) {
  pass("All modes: window_width > 0 for all windows")
} else {
  fail("Some windows have non-positive width")
}

# ============================================================================
# Test 9: Boundary Array Integrity (core invariant)
# ============================================================================

cat("\n--- Test 9: Boundary Array Integrity ---\n")

# The core invariant of boundary-array architecture:
# mz_start[j] == mz_end[j-1] for ALL j (exact equality, not tolerance)
check_boundary_integrity <- function(windows, mode_label) {
  rt_bins <- unique(windows$rt_segment_id)
  violations <- 0

  for (rt_id in rt_bins) {
    bin_w <- windows %>%
      filter(rt_segment_id == rt_id) %>%
      arrange(mz_start)

    if ("cycle" %in% colnames(bin_w)) {
      for (cyc in unique(bin_w$cycle)) {
        cyc_w <- bin_w %>% filter(cycle == cyc)
        if (nrow(cyc_w) > 1) {
          for (j in 2:nrow(cyc_w)) {
            if (!identical(cyc_w$mz_start[j], cyc_w$mz_end[j - 1])) {
              violations <- violations + 1
            }
          }
        }
      }
    } else {
      if (nrow(bin_w) > 1) {
        for (j in 2:nrow(bin_w)) {
          if (!identical(bin_w$mz_start[j], bin_w$mz_end[j - 1])) {
            violations <- violations + 1
          }
        }
      }
    }
  }

  if (violations == 0) {
    pass(sprintf("%s: Boundary array integrity (exact mz_start[j] == mz_end[j-1])", mode_label))
  } else {
    fail(sprintf("%s: %d boundary integrity violations", mode_label, violations))
  }
}

check_boundary_integrity(windows_fixed, "Fixed+FZ")
check_boundary_integrity(windows_density, "Density+FZ")
check_boundary_integrity(windows_staggered, "Staggered")

# ============================================================================
# Test 10: Loop Control N Synchronization (Staggered Mode)
# ============================================================================

cat("\n--- Test 10: Loop Control N Sync (Staggered) ---\n")

# In staggered mode, Thermo Loop Control N requires:
# 1. Every RT bin has exactly the same number of windows per cycle
# 2. C1 count == C2 count in each RT bin
# 3. The count equals the planned n_windows_per_bin

if ("cycle" %in% colnames(windows_staggered)) {
  # Count windows per RT bin per cycle
  loop_counts <- windows_staggered %>%
    group_by(rt_segment_id, cycle) %>%
    summarise(n = n(), .groups = "drop") %>%
    tidyr::pivot_wider(names_from = cycle, values_from = n, names_prefix = "C")

  # Check 10a: C1 == C2 in ALL RT bins
  if (all(loop_counts$C1 == loop_counts$C2)) {
    pass(sprintf("Loop Control: C1 == C2 in all %d RT bins (%d windows each)",
                 nrow(loop_counts), loop_counts$C1[1]))
  } else {
    mismatched <- loop_counts %>% filter(C1 != C2)
    fail(sprintf("Loop Control: C1 != C2 in %d RT bins (e.g., bin %d: C1=%d, C2=%d)",
                 nrow(mismatched), mismatched$rt_segment_id[1],
                 mismatched$C1[1], mismatched$C2[1]))
  }

  # Check 10b: Same window count across ALL RT bins (uniform Loop Control N)
  unique_counts <- unique(loop_counts$C1)
  if (length(unique_counts) == 1) {
    pass(sprintf("Loop Control N: Uniform %d windows/bin/cycle across all RT bins",
                 unique_counts))
  } else {
    fail(sprintf("Loop Control N: Non-uniform window counts across bins: %s",
                 paste(unique_counts, collapse = ", ")))
  }

  # Check 10c: Per-cycle count matches planned count
  planned_n <- plan$window_count_per_bin
  if (unique_counts[1] == planned_n) {
    pass(sprintf("Loop Control N: Matches planned count (%d)", planned_n))
  } else {
    fail(sprintf("Loop Control N: Actual %d != planned %d", unique_counts[1], planned_n))
  }
} else {
  fail("Loop Control: Staggered windows missing 'cycle' column")
}

# ============================================================================
# Summary
# ============================================================================

cat("\n==================================================================\n")
cat(sprintf("  RESULTS: %d passed, %d failed (total: %d)\n",
            tests_passed, tests_failed, tests_passed + tests_failed))
cat("==================================================================\n")

if (tests_failed > 0) {
  cat("  STATUS: SOME TESTS FAILED\n")
  quit(status = 1)
} else {
  cat("  STATUS: ALL TESTS PASSED\n")
}
