# Run from the repository root: Rscript scripts/smoke_ms1_feature_map.R
# Optional positional args: features.parquet report.parquet run_name output_dir
# All acquisition settings below are TEST REFERENCE assumptions, not a
# reconstruction of the historical method used for the supplied acquisitions.
args <- commandArgs(trailingOnly = TRUE)
defaults <- c(
  "D:/AIDIA_benchmark/mzml/cache_60min_mzml_trimmed/20260608_SampleA_60min_dppp4_adap_dense_01/features.parquet",
  "D:/AIDIA_benchmark/Diann_res_261012_60min/report.parquet",
  "20260608_SampleA_60min_dppp4_adap_dense_01",
  file.path("test_output", "ms1-feature-map", format(Sys.time(), "smoke-%Y%m%d-%H%M%S"))
)
defaults[seq_along(args)] <- args
feature_file <- defaults[1]
report_file <- defaults[2]
selected_run <- defaults[3]
output_dir <- defaults[4]
if (length(args) > 4L) stop("Expected at most four positional arguments.")
if (dir.exists(output_dir)) stop("Choose a new output directory.")
root <- normalizePath(".", winslash = "/", mustWork = TRUE)
candidate <- normalizePath(output_dir, winslash = "/", mustWork = FALSE)
if (!startsWith(tolower(candidate), paste0(tolower(root), "/"))) {
  stop("Smoke outputs must be inside the current worktree.")
}
stopifnot(file.exists(feature_file), file.exists(report_file))
devtools::load_all(quiet = TRUE)
dir.create(output_dir, recursive = TRUE)
before <- tools::md5sum(c(feature_file, report_file))

# Read only the exact scouting run and required ID/filter columns.
id_columns <- c("Run", "Precursor.Id", "Protein.Group", "Protein.Ids",
                "Precursor.Mz", "RT.Start", "RT.Stop", "FWHM",
                "Decoy", "Q.Value", "PG.Q.Value")
dataset <- arrow::open_dataset(report_file, format = "parquet")
id_rows <- dplyr::collect(dplyr::filter(
  dplyr::select(dataset, dplyr::all_of(id_columns)), Run == selected_run))
n_selected <- nrow(id_rows)
stopifnot(n_selected > 0, identical(unique(id_rows$Run), selected_run))
id_rows <- id_rows[id_rows$Decoy == 0 & id_rows$Q.Value <= 0.01 &
  id_rows$PG.Q.Value <= 0.01 & !is.na(id_rows$Decoy) & !is.na(id_rows$Q.Value) &
  !is.na(id_rows$PG.Q.Value) &
  !grepl("cRAP", id_rows$Protein.Ids, ignore.case = TRUE) &
  !grepl("cRAP", id_rows$Protein.Group, ignore.case = TRUE), ]
id_path <- file.path(output_dir, "selected_id.parquet")
arrow::write_parquet(id_rows, id_path)
id <- create_validated_dataset(id_path, run_name = selected_run,
  enable_replicate_consensus = FALSE, apply_quality_filters = FALSE)
meta_path <- file.path(dirname(feature_file), "scan_meta.json")
provenance <- if (file.exists(meta_path)) jsonlite::fromJSON(meta_path, simplifyVector = FALSE) else list()
ms1 <- create_ms1_feature_dataset(feature_file, run_name = selected_run, provenance = provenance)
stopifnot(identical(ms1$data$RT.Apex, ms1$data$rt_apex))

# A plan derived once from the ID map. It is reused unchanged for both designs.
reference <- plan_optimization(id, current_cycle_time = 2.7,
  instrument_preset = "exploris", target_dppp = 4, target_satisfaction = 0.8,
  ms2_resolution = 30000, ms2_time_override = 0.022)
stopifnot(reference$feasibility$is_feasible)
result <- compare_input_maps(id, ms1, reference,
  rt_breaks = seq(10, 80, by = 5), mz_range = c(390, 970),
  context = list(sample = "SampleA (from exact scouting run label)",
    lc_condition = paste("Same scouting run:", selected_run),
    settings_source = paste("TEST REFERENCE: Exploris preset, MS2 30K/22 ms, current CT 2.7 s,",
      "DPPP 4, satisfaction 0.80; ID-derived plan frozen; RT 10-80 min, m/z 390-970.",
      "These settings do not reproduce the historical acquisition."),
    id_filter = "Decoy=0; Q.Value<=0.01; PG.Q.Value<=0.01; cRAP excluded; no Global/Lib Q filter",
    source_report = normalizePath(report_file, winslash = "/"),
    selected_run_rows = n_selected, filtered_id_rows = nrow(id_rows)))
export_input_map_comparison(result, file.path(output_dir, "comparison"))

# Existing Stage 2/3/4 and Thermo export also accept MS1 data independently.
# Reuse the ID plan here too; this smoke is not a separate FWHM re-optimization.
windows <- optimize_windows(ms1, reference,
  strategy_config = quantile_config(apply_smoothing = FALSE),
  rt_bin_width_min = 5, mz_range_min = 390, mz_range_max = 970)
export_windows_to_csv(windows, file.path(output_dir, "ms1_standard_method.csv"), ms1)
viz <- generate_visualizations(ms1, reference, windows,
  output_dir = file.path(output_dir, "plots"), create_pdf = FALSE,
  create_individual_plots = TRUE, report_template = "minimal", plot_dpi = 100)
stopifnot(length(viz$plots) >= 5L)
after <- tools::md5sum(c(feature_file, report_file))
stopifnot(identical(before, after))
write.csv(data.frame(file = names(before), md5_before = unname(before), md5_after = unname(after)),
          file.path(output_dir, "source_integrity.csv"), row.names = FALSE)
writeLines(capture.output(sessionInfo()), file.path(output_dir, "sessionInfo.txt"))
write.csv(result$satisfaction, file.path(output_dir, "smoke_satisfaction.csv"), row.names = FALSE)
print(result$input_counts)
print(result$satisfaction)
cat("\nSmoke completed; source parquet checksums unchanged. Output:", output_dir, "\n")
