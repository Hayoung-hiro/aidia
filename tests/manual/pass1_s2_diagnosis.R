# Pass 1: Section 2 — Acquisition Diagnosis
# Plots: 04 DPPP + Instrument table (combined), 05 Satisfaction curve
# Two cases: (A) no current CT → Current column blank
#            (B) user-provided current CT → Current column populated
# Run: source("tests/manual/pass1_s2_diagnosis.R")

devtools::load_all()

outdir <- "output_report_test/pass1/S2_Diagnosis"
if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

cat("=== Stage 1 ===\n")
validated <- create_validated_dataset("data/30min_report.parquet")

# ---- Case A: current_cycle_time = NULL (auto-estimated → Current = "—") ----
cat("\n=== Case A: No current CT (auto-estimated) ===\n")
plan_a <- plan_optimization(validated, instrument_preset = "astral", target_dppp = 7.0)
stopifnot(plan_a$diagnosis$current_ct_is_estimated == TRUE)

cat("[A-04] DPPP Table (Current = blank)\n")
p <- plot_dppp_diagnosis_table(plan_a, validated)
png(file.path(outdir, "S2_04_dppp_table.png"),
    width = 1400, height = 900, res = 150)
grid::grid.draw(p)
dev.off()

cat("[A-05] Satisfaction Curve (no Current point)\n")
p <- plot_satisfaction_curve(plan_a, validated)
ggsave(file.path(outdir, "S2_05_satisfaction.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

# ---- Case B: current_cycle_time provided (user-input → Current populated) ----
cat("\n=== Case B: User-provided current CT = 2.5 sec ===\n")
plan_b <- plan_optimization(validated, instrument_preset = "astral", target_dppp = 7.0,
                            current_cycle_time = 2.5)
stopifnot(plan_b$diagnosis$current_ct_is_estimated == FALSE)

cat("[B-04] DPPP Table (Current populated)\n")
p <- plot_dppp_diagnosis_table(plan_b, validated)
png(file.path(outdir, "S2_04_dppp_table_with_current.png"),
    width = 1400, height = 900, res = 150)
grid::grid.draw(p)
dev.off()

cat("[B-05] Satisfaction Curve (with Current point)\n")
p <- plot_satisfaction_curve(plan_b, validated)
ggsave(file.path(outdir, "S2_05_satisfaction_with_current.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

cat("\n=== S2 Done ===\n")
cat(paste(" ", list.files(outdir, pattern = "S2_")), sep = "\n")
