# Quick test for output filename formatting functions
source("R/utils_common.R")

cat("\n=== Testing format_short_instrument_name ===\n")
stopifnot(format_short_instrument_name("qexactive_hfx") == "qe_hfx")
stopifnot(format_short_instrument_name("fusion_lumos") == "lumos")
stopifnot(format_short_instrument_name("astral") == "astral")
stopifnot(format_short_instrument_name("astral_zoom") == "astral_zm")
stopifnot(format_short_instrument_name("exploris") == "exploris")
stopifnot(format_short_instrument_name("unknown_instrument") == "unknown_instrument")
cat("All instrument name tests passed\n")

cat("\n=== Testing format_short_window_mode ===\n")
stopifnot(format_short_window_mode("density") == "dens")
stopifnot(format_short_window_mode("fixed") == "Fix")
stopifnot(format_short_window_mode("staggered") == "stag")
cat("All window mode tests passed\n")

cat("\n=== Testing format_short_rt_mode ===\n")
stopifnot(format_short_rt_mode("fixed") == "Fix")
stopifnot(format_short_rt_mode("adaptive") == "Adapt")
stopifnot(format_short_rt_mode("custom", 5) == "5min")
stopifnot(format_short_rt_mode("custom", 2.5) == "2.5min")
cat("All RT mode tests passed\n")

cat("\n=== Testing format_output_filename ===\n")
# Method file
fn1 <- format_output_filename("method", "qexactive_hfx", "greedy", "density", "fixed", date = "20260208")
cat("Method:", fn1, "\n")
stopifnot(fn1 == "method_qe_hfx_greedy_dens_Fix_20260208.csv")

# Report file (no strategy)
fn2 <- format_output_filename("report", "astral", strategy = NULL, "density", "adaptive", ext = "pdf", date = "20260208")
cat("Report:", fn2, "\n")
stopifnot(fn2 == "report_astral_dens_Adapt_20260208.pdf")

# Custom RT bin
fn3 <- format_output_filename("method", "exploris", "kde", "staggered", "custom", 5, date = "20260208")
cat("Custom RT:", fn3, "\n")
stopifnot(fn3 == "method_exploris_kde_stag_5min_20260208.csv")

# Fusion Lumos
fn4 <- format_output_filename("method", "fusion_lumos", "coverage", "fixed", "adaptive", date = "20260208")
cat("Lumos:", fn4, "\n")
stopifnot(fn4 == "method_lumos_coverage_Fix_Adapt_20260208.csv")

cat("\n=== ALL NAMING TESTS PASSED ===\n")
