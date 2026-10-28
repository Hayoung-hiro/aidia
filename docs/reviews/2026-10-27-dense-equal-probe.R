# Diagnostic only: load committed generators into isolated environments.
# Run from the repository root. No production functions/files are modified.
#
# Rscript --vanilla docs/reviews/2026-10-27-dense-equal-probe.R
# Rscript --vanilla docs/reviews/2026-10-27-dense-equal-probe.R --assert-adaptive
#   The second command intentionally fails on 4cbb7b4 and passes with
#   --revision=42e2998^ (the parent of the smoothing regression).
#   To verify the local fix, use --assert-adaptive --revision=WORKTREE.
# Optional: --snapshot-dir=PATH loads an extracted 4cbb7b4 package and runs
# the complete Stage 3 entry point plus the three existing relevant test files.

suppressPackageStartupMessages(library(tibble))
args <- commandArgs(trailingOnly = TRUE)
option <- function(name, default = NULL) {
  prefix <- paste0("--", name, "=")
  value <- args[startsWith(args, prefix)]
  if (!length(value)) return(default)
  substring(value[[1]], nchar(prefix) + 1L)
}

load_generator <- function(revision) {
  if (revision == "WORKTREE") {
    env <- new.env(parent = globalenv())
    env$ABSOLUTE_MIN_WIDTH_DA <- 1
    source("R/precursor_matching.R", local = env)
    source("R/window_generation.R", local = env)
    return(env)
  }
  path <- if (revision %in% c("0095c68", "6e94313")) {
    "R/stage3/stage3_window_generation.R"
  } else {
    "R/window_generation.R"
  }
  code <- system2("git", c("show", shQuote(paste0(revision, ":", path))),
                  stdout = TRUE)
  stopifnot(is.null(attr(code, "status")))
  env <- new.env(parent = globalenv())
  # Definition at R/window_optimization.R:38 in the target commit.
  env$ABSOLUTE_MIN_WIDTH_DA <- 1
  suppressPackageStartupMessages(invisible(capture.output(
    source(textConnection(code), local = env)
  )))
  env
}

format_widths <- function(widths) paste(round(widths, 4), collapse = ",")
fixture <- function(n = 10L) {
  # 90% of precursors in the first 20% of the span; count >= 2N.
  c(seq(400.01, 400 + 2 * n * 0.2, length.out = 9 * n),
    seq(400 + 2 * n * 0.21, 400 + 2 * n - 0.01, length.out = n))
}
generate <- function(env, n = 10L, fz = 0) {
  env$generate_variable_windows_internal(
    fixture(n), 400, 400 + 2 * n, n, 1, 80, fz_offset = fz
  )
}

revision <- option("revision", "4cbb7b4")
env <- load_generator(revision)
if ("--assert-adaptive" %in% args) {
  dense <- generate(env)
  equal <- env$generate_fixed_windows_internal(400, 420, 10, 1, 80)
  cat("revision=", revision, " widths=", format_widths(dense$window_width), "\n", sep = "")
  stopifnot("Dense lost adaptation on a nonuniform, feasible input" =
              !isTRUE(all.equal(dense, equal)))
  cat("PASS: Dense differs from Equal on the regression fixture.\n")
  quit(status = 0)
}

cat("Historical comparison: span=400..420, N=10, generation floor=1, max=80\n")
for (rev in c("6e94313", "4553229", "c33420f", "a1ac1a8", "42e2998^",
              "42e2998", "bb6a982", "4cbb7b4")) {
  historical <- load_generator(rev)
  # The February implementation predates the fz_offset argument.
  windows <- historical$generate_variable_windows_internal(fixture(), 400, 420, 10, 1, 80)
  cat(rev, format_widths(windows$window_width), "\n")
}

# Instrument a private function copy; the original calculations are unchanged.
instrumented <- env$generate_variable_windows_internal
body_text <- deparse(body(instrumented), width.cutoff = 500)
needle <- "widths <- diff(boundaries)"
# Match the whole deparsed line to avoid also replacing raw_widths below.
index <- which(trimws(body_text) == needle)
stopifnot(length(index) == 1L)
body_text[index] <- paste0(body_text[index], "; phase2_widths <- widths")
index <- which(trimws(body_text) == "raw_widths <- diff(boundaries)")
stopifnot(length(index) == 1L)
body_text[index] <- paste0(body_text[index],
  "; cat('Phase2:', format_widths(phase2_widths), '\nPost-smoothing:', format_widths(raw_widths), '\n')")
body(instrumented) <- parse(text = body_text)[[1]]
cat("\nPhase inspection (target revision):\n")
windows <- instrumented(fixture(), 400, 420, 10, 1, 80)
cat("Final:", format_widths(windows$window_width), "\n")

# Single-variable ablation: skip only the width smoothing loop in memory.
unsmoothed <- env$generate_variable_windows_internal
body_text <- deparse(body(unsmoothed), width.cutoff = 500)
needle <- "for (smooth_iter in 1:5)"
stopifnot(sum(grepl(needle, body_text, fixed = TRUE)) == 1L)
body_text <- sub(needle, "for (smooth_iter in integer(0))", body_text, fixed = TRUE)
body(unsmoothed) <- parse(text = body_text)[[1]]
cat("\nAblation (diagnostic, not a proposed production fix):\n")
for (n in c(10L, 40L)) {
  for (label in c("target", "skip_width_smoothing")) {
    fun <- if (label == "target") env$generate_variable_windows_internal else unsmoothed
    windows <- fun(fixture(n), 400, 400 + 2 * n, n, 1, 80)
    counts <- vapply(seq_len(nrow(windows)), function(i) {
      sum(fixture(n) >= windows$mz_start[i] & fixture(n) < windows$mz_end[i])
    }, integer(1))
    cat(label, "N=", n, "widths=", format_widths(windows$window_width),
        "count_CV=", round(sd(counts) / mean(counts), 6), "\n")
  }
}

cat("\nMinimal example (four precursors, no sparse fallback):\n")
for (rev in c("42e2998^", "42e2998", "4cbb7b4")) {
  historical <- load_generator(rev)
  windows <- historical$generate_variable_windows_internal(c(401, 402, 402.5, 419),
                                                            400, 420, 2, 1, 80)
  cat(rev, format_widths(windows$window_width), "\n")
}

cat("\nIndependent cap lock: average width 75, step 7.5; max 80 blocks all moves.\n")
mz <- c(seq(400.01, 520, length.out = 900), seq(526, 999.99, length.out = 100))
for (cap in c(80, 85, 120, 600)) {
  windows <- env$generate_variable_windows_internal(mz, 400, 1000, 8, 2, cap)
  cat("max=", cap, "widths=", format_widths(windows$window_width), "\n")
}

cat("\nwidth_grid_step is ignored by the target generator:\n")
for (grid in list(NULL, 0, 0.1, 0.5, 1, 2)) {
  windows <- env$generate_variable_windows_internal(fixture(), 400, 420, 10, 1, 80,
                                                   width_grid_step = grid)
  cat("grid=", if (is.null(grid)) "NULL" else grid,
      "widths=", format_widths(windows$window_width), "\n")
}

snapshot_dir <- option("snapshot-dir")
if (!is.null(snapshot_dir)) {
  pkgload::load_all(snapshot_dir, quiet = TRUE)
  n <- 40L
  vd <- structure(list(data = tibble(Precursor.Mz = fixture(n), RT.Apex = 2, FWHM = 4)),
                  class = c("ValidatedData", "list"))
  plan <- structure(list(
    window_count_per_bin = n,
    instrument = list(preset = "test", cycle_mode = "sequential",
                      ms1_time_sec = 0.5, ms2_time_sec = 0.05),
    scan_time = list(t_scan_ms = 50), required_cycle_time_sec = 2
  ), class = c("OptimizationPlan", "list"))
  cat("\nFull Stage 3 on the supplied snapshot: Greedy, N40, min2, max80\n")
  for (fz in c(0, 0.25)) {
    results <- list()
    for (mode in c("density", "fixed")) {
      invisible(capture.output(results[[mode]] <- suppressWarnings(optimize_windows(
        vd, plan, strategy_config = greedy_config(apply_smoothing = FALSE),
        window_mode = mode, min_width_da = 2, max_width_da = 80,
        fz_offset = fz, mz_range_min = 400, mz_range_max = 1000
      ))))
    }
    cols <- c("mz_start", "mz_end", "window_width", "n_precursors")
    dense <- results$density$windows[, cols]
    equal <- results$fixed$windows[, cols]
    cat("FZ=", fz, "identical=", isTRUE(all.equal(dense, equal)),
        "count_range=", paste(range(dense$n_precursors), collapse = ".."), "\n")
  }
  devtools::test(snapshot_dir,
    filter = "density-direction-independence|width-semantics-split|window_digitization",
    reporter = "summary", stop_on_failure = TRUE)
}
