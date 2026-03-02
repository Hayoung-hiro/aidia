# test_staggered_regression.R
# Comprehensive regression test: staggered window changes must NOT break
# fixed/density modes, and staggered mode must produce correct output.
#
# Usage: Rscript tests/manual/test_staggered_regression.R
# ============================================================================

cat("=== Staggered Window Regression Test Suite ===\n\n")

# Load package
devtools::load_all("D:/Projects/aidia")

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

# ============================================================================
# Helper: Create mock ValidatedData (500 precursors)
# ============================================================================
create_mock_data <- function(n = 500, seed = 42) {
  set.seed(seed)
  df <- tibble(
    Precursor.Mz = runif(n, 400, 1200),
    RT.Apex       = runif(n, 10, 70),
    FWHM          = rnorm(n, mean = 12, sd = 2)  # seconds
  )
  as_ValidatedData(df)
}

# ============================================================================
# Helper: Create a minimal OptimizationPlan
# ============================================================================
create_mock_plan <- function(validated_data,
                             instrument_preset = "astral",
                             target_dppp = 7.0) {
  plan_optimization(
    validated_data,
    current_cycle_time = 2.0,
    instrument_preset = instrument_preset,
    target_dppp = target_dppp,
    target_satisfaction = 0.70
  )
}

# ============================================================================
# Results tracker
# ============================================================================
results <- list()
add_result <- function(test_name, passed, detail = "") {
  results[[length(results) + 1]] <<- list(
    test  = test_name,
    pass  = passed,
    detail = detail
  )
  status <- if (passed) "PASS" else "FAIL"
  cat(sprintf("  [%s] %s", status, test_name))
  if (nzchar(detail)) cat(sprintf("  (%s)", detail))
  cat("\n")
}

# ============================================================================
# Create shared mock objects
# ============================================================================
cat("Creating mock data (500 precursors)...\n")
mock_data <- create_mock_data()
cat("Creating optimization plan...\n")
mock_plan <- create_mock_plan(mock_data)
cat(sprintf("  Plan: %d windows/bin, cycle time %.3f sec\n\n",
            mock_plan$window_count_per_bin,
            mock_plan$required_cycle_time_sec))

tmp_dir <- tempdir()

# ============================================================================
# TEST 1: Fixed mode (window_mode = "fixed", mz_strategy = "quantile")
# ============================================================================
cat("--- TEST 1: Fixed mode (fixed + quantile) ---\n")

tryCatch({
  res_fixed <- optimize_windows(
    mock_data, mock_plan,
    mz_strategy  = "quantile",
    window_mode  = "fixed"
  )

  wins <- res_fixed$windows

  # 1a: no cycle column
  has_cycle <- "cycle" %in% colnames(wins)
  add_result("1a. Fixed: no 'cycle' column", !has_cycle,
             if (has_cycle) "UNEXPECTED: cycle column present" else "")


  # 1b: no is_staggered column
  has_stag <- "is_staggered" %in% colnames(wins)
  add_result("1b. Fixed: no 'is_staggered' column", !has_stag,
             if (has_stag) "UNEXPECTED: is_staggered column present" else "")

  # 1c: Export CSV → 16 columns
  csv_path <- file.path(tmp_dir, "test_fixed.csv")
  export_windows_to_csv(res_fixed, csv_path, mock_data, mock_plan)
  csv_data <- read.csv(csv_path, check.names = FALSE)

  ncols <- ncol(csv_data)
  add_result("1c. Fixed CSV: 16 columns", ncols == 16,
             sprintf("got %d", ncols))

  # 1d: Compound field is empty "" (read.csv converts all-empty to NA)
  compound_vals <- as.character(csv_data$Compound)
  all_empty <- all(is.na(compound_vals) | compound_vals == "")
  add_result("1d. Fixed CSV: Compound is empty/NA (not C1/C2)", all_empty,
             if (!all_empty) sprintf("non-empty: %s",
               paste(head(unique(compound_vals[!is.na(compound_vals) & compound_vals != ""]), 3),
                     collapse = ", ")) else "")

}, error = function(e) {
  add_result("1. Fixed mode execution", FALSE, conditionMessage(e))
})

cat("\n")

# ============================================================================
# TEST 2: Density mode (window_mode = "density", mz_strategy = "greedy")
# ============================================================================
cat("--- TEST 2: Density mode (density + greedy) ---\n")

tryCatch({
  res_density <- optimize_windows(
    mock_data, mock_plan,
    mz_strategy  = "greedy",
    window_mode  = "density"
  )

  wins <- res_density$windows

  # 2a: no cycle column
  has_cycle <- "cycle" %in% colnames(wins)
  add_result("2a. Density: no 'cycle' column", !has_cycle,
             if (has_cycle) "UNEXPECTED: cycle column present" else "")

  # 2b: no is_staggered column
  has_stag <- "is_staggered" %in% colnames(wins)
  add_result("2b. Density: no 'is_staggered' column", !has_stag,
             if (has_stag) "UNEXPECTED: is_staggered column present" else "")

  # 2c: Export CSV → 16 columns
  csv_path <- file.path(tmp_dir, "test_density.csv")
  export_windows_to_csv(res_density, csv_path, mock_data, mock_plan)
  csv_data <- read.csv(csv_path, check.names = FALSE)

  ncols <- ncol(csv_data)
  add_result("2c. Density CSV: 16 columns", ncols == 16,
             sprintf("got %d", ncols))

  # 2d: Compound field is empty "" (read.csv converts all-empty to NA)
  compound_vals <- as.character(csv_data$Compound)
  all_empty <- all(is.na(compound_vals) | compound_vals == "")
  add_result("2d. Density CSV: Compound is empty/NA (not C1/C2)", all_empty,
             if (!all_empty) sprintf("non-empty: %s",
               paste(head(unique(compound_vals[!is.na(compound_vals) & compound_vals != ""]), 3),
                     collapse = ", ")) else "")

  # 2e: Width variance > 0 (density should produce variable widths)
  width_var <- var(wins$window_width)
  add_result("2e. Density: width variance > 0 (variable widths)", width_var > 0,
             sprintf("var = %.4f", width_var))

}, error = function(e) {
  add_result("2. Density mode execution", FALSE, conditionMessage(e))
})

cat("\n")

# ============================================================================
# TEST 3: Staggered mode (window_mode = "staggered", mz_strategy = "quantile")
# ============================================================================
cat("--- TEST 3: Staggered mode (staggered + quantile) ---\n")

tryCatch({
  # Capture output to check for Loop Control N message
  staggered_output <- capture.output({
    res_staggered <- optimize_windows(
      mock_data, mock_plan,
      mz_strategy   = "quantile",
      window_mode   = "staggered",
      fz_offset  = 0.25
    )
  })

  wins <- res_staggered$windows

  # 3a: cycle column exists
  has_cycle <- "cycle" %in% colnames(wins)
  add_result("3a. Staggered: 'cycle' column exists", has_cycle)

  if (has_cycle) {
    # 3b: Both cycles present with equal counts
    cycle_counts <- table(wins$cycle)
    both_cycles <- all(c(1L, 2L) %in% as.integer(names(cycle_counts)))
    equal_counts <- length(unique(as.integer(cycle_counts))) == 1
    add_result("3b. Staggered: both cycles, equal count",
               both_cycles && equal_counts,
               sprintf("C1=%s, C2=%s",
                       ifelse("1" %in% names(cycle_counts), cycle_counts[["1"]], "0"),
                       ifelse("2" %in% names(cycle_counts), cycle_counts[["2"]], "0")))
  } else {
    add_result("3b. Staggered: both cycles, equal count", FALSE, "no cycle column")
  }

  # 3c: Export CSV → 17 columns (16 base + Cycle)
  csv_path <- file.path(tmp_dir, "test_staggered.csv")
  staggered_csv_output <- capture.output({
    export_windows_to_csv(res_staggered, csv_path, mock_data, mock_plan)
  })
  csv_data <- read.csv(csv_path, check.names = FALSE)

  ncols <- ncol(csv_data)
  add_result("3c. Staggered CSV: 17 columns", ncols == 17,
             sprintf("got %d", ncols))

  # 3d: Cycle column present in CSV
  has_csv_cycle <- "Cycle" %in% colnames(csv_data)
  add_result("3d. Staggered CSV: 'Cycle' column present", has_csv_cycle)

  # 3e: Compound has C1/C2 naming
  compounds <- csv_data$Compound
  has_c1 <- any(grepl("^C1_", compounds))
  has_c2 <- any(grepl("^C2_", compounds))
  add_result("3e. Staggered CSV: Compound has C1/C2 naming", has_c1 && has_c2,
             sprintf("C1: %s, C2: %s", has_c1, has_c2))

  # 3f: C1 windows come before C2 within each RT bin (ordering check)
  if (has_cycle) {
    c1_before_c2 <- TRUE
    for (seg in unique(wins$rt_segment_id)) {
      seg_wins <- wins %>% filter(rt_segment_id == seg)
      if (nrow(seg_wins) > 0 && "cycle" %in% colnames(seg_wins)) {
        cycles_in_order <- seg_wins$cycle
        # All C1 should come before any C2
        first_c2 <- which(cycles_in_order == 2L)[1]
        last_c1  <- max(which(cycles_in_order == 1L))
        if (!is.na(first_c2) && last_c1 >= first_c2) {
          c1_before_c2 <- FALSE
          break
        }
      }
    }
    add_result("3f. Staggered: C1 before C2 within each RT bin", c1_before_c2)
  } else {
    add_result("3f. Staggered: C1 before C2 within each RT bin", FALSE, "no cycle column")
  }

  # 3g: Loop Control N message printed
  all_output <- c(staggered_csv_output)
  has_loop_msg <- any(grepl("Loop Control N", all_output))
  add_result("3g. Staggered: Loop Control N message printed", has_loop_msg,
             if (has_loop_msg) grep("Loop Control N", all_output, value = TRUE)[1] else "message not found")

}, error = function(e) {
  add_result("3. Staggered mode execution", FALSE, conditionMessage(e))
})

cat("\n")

# ============================================================================
# TEST 4: All 5 strategies work with density mode (no staggered)
# ============================================================================
cat("--- TEST 4: All 5 strategies with density mode ---\n")

strategies <- c("greedy", "kde", "quantile", "coverage", "outlier")

for (strat in strategies) {
  tryCatch({
    res <- optimize_windows(
      mock_data, mock_plan,
      mz_strategy = strat,
      window_mode = "density"
    )
    n_windows <- nrow(res$windows)
    # Also verify no cycle/is_staggered leakage
    no_cycle <- !("cycle" %in% colnames(res$windows))
    no_stag  <- !("is_staggered" %in% colnames(res$windows))
    all_ok <- n_windows > 0 && no_cycle && no_stag
    add_result(sprintf("4. Strategy '%s': runs OK, %d windows, no staggered columns",
                       strat, n_windows),
               all_ok,
               if (!all_ok) sprintf("n=%d, cycle=%s, is_stag=%s",
                                    n_windows, !no_cycle, !no_stag) else "")
  }, error = function(e) {
    add_result(sprintf("4. Strategy '%s'", strat), FALSE, conditionMessage(e))
  })
}

cat("\n")

# ============================================================================
# SUMMARY
# ============================================================================
cat("=" |> strrep(60), "\n")
cat("REGRESSION TEST SUMMARY\n")
cat("=" |> strrep(60), "\n\n")

n_total  <- length(results)
n_passed <- sum(vapply(results, function(r) r$pass, logical(1)))
n_failed <- n_total - n_passed

for (r in results) {
  status <- if (r$pass) "PASS" else "FAIL"
  cat(sprintf("  [%s] %s\n", status, r$test))
}

cat(sprintf("\nTotal: %d tests | Passed: %d | Failed: %d\n", n_total, n_passed, n_failed))

if (n_failed == 0) {
  cat("\n*** ALL TESTS PASSED - No regression detected ***\n")
} else {
  cat("\n*** FAILURES DETECTED - Regression possible ***\n")
  cat("\nFailed tests:\n")
  for (r in results) {
    if (!r$pass) {
      cat(sprintf("  - %s: %s\n", r$test, r$detail))
    }
  }
}
