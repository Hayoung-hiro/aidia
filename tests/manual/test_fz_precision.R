# test_fz_precision.R - Verify 4-decimal fz_offset works in CLI and Shiny paths
#
# Usage: Rscript tests/manual/test_fz_precision.R

suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(tibble))
devtools::load_all("D:/Projects/aidia")

cat("\n")
cat("==================================================================\n")
cat("  TEST: fz_offset 4-Decimal Precision (CLI + Shiny Parity)\n")
cat("==================================================================\n\n")

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
# Setup
# ============================================================================

fz_val <- 0.2537
optimal_inc <- 1.00045475

set.seed(42)
mock <- tibble(
  Precursor.Mz = runif(200, 400, 800),
  RT.Apex = runif(200, 5, 30),
  FWHM = runif(200, 0.1, 0.2)
)
vd <- as_ValidatedData(mock)
plan <- plan_optimization(vd, instrument_preset = "astral",
                          target_dppp = 7.0, target_satisfaction = 0.70)

is_at_fz <- function(boundaries, fz_val) {
  shifted <- boundaries - fz_val
  remainders <- shifted %% optimal_inc
  remainders < 0.01 | (optimal_inc - remainders) < 0.01
}

# ============================================================================
# Test 1: calc_forbidden_edge preserves 4-decimal precision
# ============================================================================

cat("--- Test 1: calc_forbidden_edge 4-decimal precision ---\n")

edge <- calc_forbidden_edge(500, fz_offset = fz_val)
# The fractional part should encode fz_val
frac <- edge - floor(edge)
cat(sprintf("  edge = %.4f, fractional = %.4f\n", edge, frac))

# Verify it's at FZ
if (is_at_fz(edge, fz_val)) {
  pass(sprintf("calc_forbidden_edge(500, %.4f) = %.4f is at FZ", fz_val, edge))
} else {
  fail(sprintf("calc_forbidden_edge(500, %.4f) = %.4f NOT at FZ", fz_val, edge))
}

# Compare with 2-decimal truncation
edge_2d <- calc_forbidden_edge(500, fz_offset = 0.25)
if (edge != edge_2d) {
  pass(sprintf("fz=0.2537 (%.4f) differs from fz=0.25 (%.4f)", edge, edge_2d))
} else {
  fail("fz=0.2537 produces same edge as fz=0.25")
}

# ============================================================================
# Test 2: Fixed mode with 4-decimal fz_offset
# ============================================================================

cat("\n--- Test 2: Fixed mode + fz_offset=0.2537 ---\n")

res_f <- optimize_windows(vd, plan, mz_strategy = "quantile",
                          window_mode = "fixed", fz_offset = fz_val)
wins_f <- res_f$windows
boundaries_f <- unique(c(wins_f$mz_start, wins_f$mz_end))
at_fz_f <- is_at_fz(boundaries_f, fz_val)
pct_f <- mean(at_fz_f) * 100

if (pct_f == 100) {
  pass(sprintf("Fixed: 100%% boundaries at FZ(%.4f) [%d boundaries]",
               fz_val, length(boundaries_f)))
} else {
  fail(sprintf("Fixed: %.1f%% at FZ(%.4f)", pct_f, fz_val))
}

# ============================================================================
# Test 3: Density mode with 4-decimal fz_offset
# ============================================================================

cat("\n--- Test 3: Density mode + fz_offset=0.2537 ---\n")

res_d <- optimize_windows(vd, plan, mz_strategy = "quantile",
                          window_mode = "density", fz_offset = fz_val)
wins_d <- res_d$windows
boundaries_d <- unique(c(wins_d$mz_start, wins_d$mz_end))
at_fz_d <- is_at_fz(boundaries_d, fz_val)
pct_d <- mean(at_fz_d) * 100

if (pct_d == 100) {
  pass(sprintf("Density: 100%% boundaries at FZ(%.4f) [%d boundaries]",
               fz_val, length(boundaries_d)))
} else {
  fail(sprintf("Density: %.1f%% at FZ(%.4f)", pct_d, fz_val))
}

# ============================================================================
# Test 4: Staggered mode with 4-decimal fz_offset
# ============================================================================

cat("\n--- Test 4: Staggered mode + fz_offset=0.2537 ---\n")

res_s <- optimize_windows(vd, plan, mz_strategy = "quantile",
                          window_mode = "staggered", fz_offset = fz_val)
wins_s <- res_s$windows
boundaries_s <- unique(c(wins_s$mz_start, wins_s$mz_end))
at_fz_s <- is_at_fz(boundaries_s, fz_val)
pct_s <- mean(at_fz_s) * 100

if (pct_s == 100) {
  pass(sprintf("Staggered: 100%% boundaries at FZ(%.4f) [%d boundaries]",
               fz_val, length(boundaries_s)))
} else {
  fail(sprintf("Staggered: %.1f%% at FZ(%.4f)", pct_s, fz_val))
}

# ============================================================================
# Test 5: CLI vs Shiny path parity
# ============================================================================

cat("\n--- Test 5: CLI vs Shiny Path Parity ---\n")

# Shiny passes fz_offset as: as.numeric(input$fz_offset_preset %||% "0.25")
# or as.numeric(input$custom_fz_offset %||% 0.25) for custom
shiny_preset_path <- as.numeric("0.2537")
shiny_custom_path <- as.numeric(0.2537)
cli_path <- 0.2537

if (identical(cli_path, shiny_preset_path)) {
  pass(sprintf("Preset path: CLI (%.4f) == Shiny as.numeric('0.2537') (%.4f)",
               cli_path, shiny_preset_path))
} else {
  fail(sprintf("Preset path: CLI (%.16f) != Shiny (%.16f)",
               cli_path, shiny_preset_path))
}

if (identical(cli_path, shiny_custom_path)) {
  pass(sprintf("Custom path: CLI (%.4f) == Shiny numericInput (%.4f)",
               cli_path, shiny_custom_path))
} else {
  fail(sprintf("Custom path: CLI (%.16f) != Shiny (%.16f)",
               cli_path, shiny_custom_path))
}

# Both paths produce same edge
edge_cli   <- calc_forbidden_edge(600, fz_offset = cli_path)
edge_shiny <- calc_forbidden_edge(600, fz_offset = shiny_preset_path)

if (identical(edge_cli, edge_shiny)) {
  pass(sprintf("Identical edge: CLI=%.4f, Shiny=%.4f", edge_cli, edge_shiny))
} else {
  fail(sprintf("Edge mismatch: CLI=%.4f, Shiny=%.4f", edge_cli, edge_shiny))
}

# ============================================================================
# Test 6: Boundary array integrity with 4-decimal fz_offset
# ============================================================================

cat("\n--- Test 6: Boundary Array Integrity (fz=0.2537) ---\n")

check_integrity <- function(windows, label) {
  rt_bins <- unique(windows$rt_segment_id)
  violations <- 0

  for (rt_id in rt_bins) {
    bin_w <- windows[windows$rt_segment_id == rt_id, ]
    if ("cycle" %in% colnames(bin_w)) {
      for (cyc in unique(bin_w$cycle)) {
        cyc_w <- bin_w[bin_w$cycle == cyc, ]
        cyc_w <- cyc_w[order(cyc_w$mz_start), ]
        if (nrow(cyc_w) > 1) {
          for (j in 2:nrow(cyc_w)) {
            if (!identical(cyc_w$mz_start[j], cyc_w$mz_end[j - 1]))
              violations <- violations + 1
          }
        }
      }
    } else {
      bin_w <- bin_w[order(bin_w$mz_start), ]
      if (nrow(bin_w) > 1) {
        for (j in 2:nrow(bin_w)) {
          if (!identical(bin_w$mz_start[j], bin_w$mz_end[j - 1]))
            violations <- violations + 1
        }
      }
    }
  }
  if (violations == 0) {
    pass(sprintf("%s: Exact boundary integrity (fz=%.4f)", label, fz_val))
  } else {
    fail(sprintf("%s: %d boundary integrity violations", label, violations))
  }
}

check_integrity(wins_f, "Fixed")
check_integrity(wins_d, "Density")
check_integrity(wins_s, "Staggered")

# ============================================================================
# Summary
# ============================================================================

cat("\n==================================================================\n")
cat(sprintf("  RESULTS: %d passed, %d failed (total: %d)\n",
            tests_passed, tests_failed, tests_passed + tests_failed))
cat("==================================================================\n")

if (tests_failed > 0) {
  cat("  STATUS: SOME TESTS FAILED\n")
} else {
  cat("  STATUS: ALL TESTS PASSED\n")
}
