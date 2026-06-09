# test_staggered_export.R - Staggered Window Mode + CSV Export Test
#
# Purpose: Verify staggered window generation (cycle 1 & 2) and
#          16-column Thermo CSV export with mock data (~500 precursors)
#
# Usage: Rscript tests/manual/test_staggered_export.R

library(dplyr)
library(tibble)

devtools::load_all("D:/Projects/aidia")

cat("\n")
cat("==================================================================\n")
cat("  TEST: Staggered Window Mode + CSV Export (Mock Data)\n")
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
# Step 1: Create mock ValidatedData (~500 precursors)
# ============================================================================

cat("--- Step 1: Create mock ValidatedData ---\n")

set.seed(42)
n <- 500

mock_data <- tibble(

  Precursor.Id = paste0("Precursor_", seq_len(n)),
  Precursor.Mz = runif(n, min = 400, max = 1200),
  RT.Apex      = runif(n, min = 5, max = 60),       # minutes
  FWHM         = runif(n, min = 0.08, max = 0.25)    # minutes (DIA-NN style)
)

validated_data <- as_ValidatedData(mock_data)

if (inherits(validated_data, "ValidatedData")) {
  pass(sprintf("ValidatedData created: %d precursors", nrow(validated_data$data)))
} else {
  fail("Failed to create ValidatedData")
}

# ============================================================================
# Step 2: Run plan_optimization()
# ============================================================================

cat("\n--- Step 2: Run plan_optimization() ---\n")

plan <- tryCatch({
  plan_optimization(
    validated_data     = validated_data,
    instrument_preset  = "astral",
    target_dppp        = 7.0,
    target_satisfaction = 0.70
  )
}, error = function(e) {
  fail(sprintf("plan_optimization() error: %s", e$message))
  NULL
})

if (!is.null(plan) && inherits(plan, "OptimizationPlan")) {
  pass(sprintf("OptimizationPlan created: %d windows/bin, cycle_time=%.3f sec",
               plan$window_count_per_bin, plan$required_cycle_time_sec))
} else if (!is.null(plan)) {
  fail("plan_optimization() returned wrong class")
}

# ============================================================================
# Step 3: Run optimize_windows() with staggered mode + fz_offset
# ============================================================================

cat("\n--- Step 3: Run optimize_windows(window_mode='staggered', fz_offset=0.25) ---\n")

opt_result <- tryCatch({
  optimize_windows(
    validated_data    = validated_data,
    optimization_plan = plan,
    mz_strategy       = "quantile",
    window_mode       = "staggered",
    fz_offset      = 0.25
  )
}, error = function(e) {
  fail(sprintf("optimize_windows() error: %s", e$message))
  NULL
})

if (is.null(opt_result)) {
  cat("\n  Aborting remaining tests (optimize_windows failed).\n")
} else {

  if (inherits(opt_result, "OptimizedWindows")) {
    pass("OptimizedWindows object created")
  } else {
    fail("optimize_windows() returned wrong class")
  }

  win <- opt_result$windows

  # ---- Check 3a: 'cycle' column exists with values 1L and 2L ----
  if ("cycle" %in% colnames(win)) {
    cycle_vals <- sort(unique(win$cycle))
    if (identical(cycle_vals, c(1L, 2L))) {
      pass(sprintf("'cycle' column present with values {1, 2} (%d cycle-1, %d cycle-2)",
                   sum(win$cycle == 1L), sum(win$cycle == 2L)))
    } else {
      fail(sprintf("'cycle' column has unexpected values: %s",
                   paste(cycle_vals, collapse = ", ")))
    }
  } else {
    fail("'cycle' column missing from windows tibble")
  }

  # ---- Check 3b: 'is_staggered' column exists ----
  if ("is_staggered" %in% colnames(win)) {
    pass(sprintf("'is_staggered' column present (TRUE count: %d, FALSE count: %d)",
                 sum(win$is_staggered), sum(!win$is_staggered)))
  } else {
    fail("'is_staggered' column missing from windows tibble")
  }

  # ---- Check 3c: Both cycles have windows ----
  n_cycle1 <- sum(win$cycle == 1L)
  n_cycle2 <- sum(win$cycle == 2L)

  if (n_cycle1 > 0 && n_cycle2 > 0) {
    pass(sprintf("Both cycles have windows: cycle1=%d, cycle2=%d", n_cycle1, n_cycle2))
  } else {
    fail(sprintf("Missing windows in a cycle: cycle1=%d, cycle2=%d", n_cycle1, n_cycle2))
  }

  # ==========================================================================
  # Step 4: Export to CSV
  # ==========================================================================

  cat("\n--- Step 4: Export windows to CSV ---\n")

  tmp_dir <- tempdir()
  csv_path <- file.path(tmp_dir, "staggered_test_method.csv")

  export_ok <- tryCatch({
    export_windows_to_csv(
      optimized_windows = opt_result,
      output_file       = csv_path,
      validated_data    = validated_data
    )
    TRUE
  }, error = function(e) {
    fail(sprintf("export_windows_to_csv() error: %s", e$message))
    FALSE
  })

  if (export_ok && file.exists(csv_path)) {
    pass(sprintf("CSV exported: %s", csv_path))
  } else if (export_ok) {
    fail("export_windows_to_csv() ran but file not found")
  }

  # ==========================================================================
  # Step 5: Read CSV back and verify
  # ==========================================================================

  cat("\n--- Step 5: Verify CSV contents ---\n")

  if (file.exists(csv_path)) {

    csv_data <- read.csv(csv_path, stringsAsFactors = FALSE)

    # ---- Check 5a: 16 columns (base) or 17 columns (staggered: +Cycle) ----
    n_cols <- ncol(csv_data)
    expected_cols <- if ("Cycle" %in% colnames(csv_data)) 17 else 16
    if (n_cols == expected_cols) {
      pass(sprintf("CSV has %d columns (%s format)",
                   n_cols, if (expected_cols == 17) "staggered 17-col" else "Thermo 16-col"))
    } else {
      fail(sprintf("CSV has %d columns, expected %d. Columns: %s",
                   n_cols, expected_cols, paste(colnames(csv_data), collapse = ", ")))
    }

    # ---- Check 5b: Window boundaries match generated windows ----
    # CSV column names use dots for spaces after read.csv
    csv_mz_start <- csv_data[["Start..m.z."]]
    csv_mz_end   <- csv_data[["End..m.z."]]

    # Compare to the original windows (rounded to 1 decimal in export)
    orig_mz_start <- round(win$mz_start, 1)
    orig_mz_end   <- round(win$mz_end, 1)

    if (length(csv_mz_start) == nrow(win) &&
        all(abs(csv_mz_start - orig_mz_start) < 0.15) &&
        all(abs(csv_mz_end - orig_mz_end) < 0.15)) {
      pass(sprintf("Window boundaries match: %d rows, m/z values consistent", nrow(win)))
    } else {
      fail(sprintf("Window boundary mismatch: CSV rows=%d vs windows=%d",
                   length(csv_mz_start), nrow(win)))
    }

    # ---- Check 5c: No NA in critical Thermo fields ----
    critical_cols <- c("m.z", "z", "t.start..min.", "t.stop..min.",
                       "Isolation.Window..m.z.", "Start..m.z.", "End..m.z.")
    # Map to actual CSV column names (read.csv sanitizes)
    available_critical <- intersect(critical_cols, colnames(csv_data))

    na_counts <- sapply(available_critical, function(col) sum(is.na(csv_data[[col]])))
    total_na <- sum(na_counts)

    if (total_na == 0) {
      pass(sprintf("No NA in critical fields (%d columns checked)",
                   length(available_critical)))
    } else {
      fail(sprintf("Found %d NA values in critical fields: %s",
                   total_na, paste(names(na_counts[na_counts > 0]),
                                   na_counts[na_counts > 0],
                                   sep = "=", collapse = ", ")))
    }

    # ---- Check 5d: z column is all 0 (Thermo standard) ----
    z_vals <- csv_data[["z"]]
    if (all(z_vals == 0)) {
      pass("z column is all 0 (Thermo standard)")
    } else {
      fail(sprintf("z column contains non-zero values: %s",
                   paste(unique(z_vals), collapse = ", ")))
    }

    # ---- Check 5e: Staggered-specific: Cycle column ----
    if ("Cycle" %in% colnames(csv_data)) {
      cycle_vals <- sort(unique(csv_data$Cycle))
      if (identical(cycle_vals, c(1L, 2L))) {
        n_c1 <- sum(csv_data$Cycle == 1L)
        n_c2 <- sum(csv_data$Cycle == 2L)
        if (n_c1 == n_c2) {
          pass(sprintf("Cycle column: C1=%d, C2=%d (equal count)", n_c1, n_c2))
        } else {
          fail(sprintf("Cycle column: C1=%d, C2=%d (unequal!)", n_c1, n_c2))
        }
      } else {
        fail(sprintf("Cycle column has unexpected values: %s", paste(cycle_vals, collapse=", ")))
      }
    }

    # ---- Check 5f: Staggered-specific: Compound naming (C1_RT1_W01 format) ----
    compounds <- csv_data[["Compound"]]
    if (all(nchar(compounds) > 0)) {
      sample_cpd <- compounds[1]
      if (grepl("^C[12]_RT\\d+_W\\d+$", sample_cpd)) {
        pass(sprintf("Compound naming: '%s' format (Loop Control friendly)", sample_cpd))
      } else {
        fail(sprintf("Compound naming unexpected format: '%s'", sample_cpd))
      }
    }

    # ---- Check 5g: C1 windows ordered before C2 within each RT bin ----
    if ("Cycle" %in% colnames(csv_data) && "RT_Segment_ID" %in% colnames(csv_data)) {
      order_ok <- TRUE
      for (rt_id in unique(csv_data$RT_Segment_ID)) {
        bin_data <- csv_data[csv_data$RT_Segment_ID == rt_id, ]
        cycles <- bin_data$Cycle
        # All C1 should come before all C2
        if (any(diff(cycles) < 0)) {
          order_ok <- FALSE
          break
        }
      }
      if (order_ok) {
        pass("Window order: C1 before C2 within each RT bin (Loop Control compatible)")
      } else {
        fail("Window order: C1/C2 not properly sorted within RT bins")
      }
    }

  } else {
    fail("CSV file does not exist, skipping content checks")
  }

}

# ============================================================================
# Summary
# ============================================================================

cat("\n")
cat("==================================================================\n")
cat(sprintf("  SUMMARY: %d passed, %d failed (total: %d)\n",
            tests_passed, tests_failed, tests_passed + tests_failed))
cat("==================================================================\n")

if (tests_failed == 0) {
  cat("  ALL TESTS PASSED\n\n")
} else {
  cat("  SOME TESTS FAILED - review output above\n\n")
}

# Exit with appropriate code
quit(save = "no", status = tests_failed)
