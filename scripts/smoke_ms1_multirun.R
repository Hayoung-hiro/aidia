# Run after alphaextract aidia-export for SampleA/60min/Fixed/01-03.
# All source data/cache are read only. Run from this worktree's root.
devtools::load_all(quiet = TRUE)
args <- commandArgs(trailingOnly = TRUE)
export_dir <- if (length(args)) args[1] else "test_output/ms1-multirun/alphaextract-export-verified"
out <- file.path("test_output/ms1-multirun", format(Sys.time(), "comparison-%Y%m%d-%H%M%S"))
dir.create(out, recursive = TRUE)
runs <- sprintf("20260608_SampleA_60min_Fixed_%02d", 1:3)
report <- "D:/AIDIA_benchmark/Diann_res_261012_60min/report.parquet"
manifest <- jsonlite::fromJSON(file.path(export_dir, "manifest.json"))
stopifnot(setequal(manifest$runs$run_name, runs))
sources <- c(manifest$sources$path, report)
before <- tools::md5sum(sources)
paths <- file.path(export_dir, manifest$runs$file)
ms1 <- create_ms1_feature_dataset(paths, provenance = list(export_manifest = manifest))
single_file <- create_ms1_feature_dataset(file.path(export_dir, "features.parquet"))
stopifnot(identical(ms1$data, single_file$data), ms1$metadata$n_runs == 3,
          ms1$metadata$min_replicates == 2)
evaluation <- create_ms1_feature_dataset(paths, aggregation = "pooled")
columns <- c("Run", "Precursor.Id", "Protein.Group", "Protein.Ids", "Precursor.Mz",
  "RT.Start", "RT.Stop", "FWHM", "Precursor.Charge", "Decoy", "Q.Value", "PG.Q.Value")
dataset <- arrow::open_dataset(report)
selected <- dplyr::collect(dplyr::filter(dplyr::select(dataset, dplyr::all_of(columns)), Run %in% runs))
stopifnot(setequal(unique(selected$Run), runs))
selected <- selected[selected$Decoy == 0 & selected$Q.Value <= .01 & selected$PG.Q.Value <= .01 &
  !grepl("cRAP", selected$Protein.Ids, ignore.case = TRUE) &
  !grepl("cRAP", selected$Protein.Group, ignore.case = TRUE), ]
id_path <- file.path(out, "selected_id.parquet")
arrow::write_parquet(selected, id_path)
id <- create_validated_dataset(id_path, apply_quality_filters = FALSE, run_name = runs)
stopifnot(id$metadata$n_runs == 3, id$metadata$min_replicates == 2)
plan <- plan_optimization(id, current_cycle_time = 2.7, instrument_preset = "exploris",
  target_dppp = 4, target_satisfaction = .8, ms2_resolution = 30000, ms2_time_override = .022)
stopifnot(plan$feasibility$is_feasible)
comparison <- compare_input_maps(id, ms1, plan, seq(10, 80, 5), c(390, 970),
  context = list(sample = "SampleA; same three runs in both maps",
    lc_condition = "60min Fixed 01-03; exact run-name selection; native RT; shifts = 0",
    settings_source = "TEST REFERENCE: Exploris, MS2 30K/22ms, CT 2.7s, DPPP4/80%; frozen ID plan, not historical timing",
    id_filter = "Decoy=0; Q.Value<=.01; PG.Q.Value<=.01; cRAP excluded; no Global/Lib filtering"),
  evaluation_data = evaluation)
export_input_map_comparison(comparison, file.path(out, "fixed-comparison"))
windows <- optimize_windows(ms1, plan, strategy_config = quantile_config(apply_smoothing = FALSE),
  rt_bin_width_min = 5, mz_range_min = 390, mz_range_max = 970)
export_windows_to_csv(windows, file.path(out, "ms1_method.csv"), ms1)
viz <- generate_visualizations(ms1, plan, windows, output_dir = file.path(out, "plots"),
  create_pdf = FALSE, create_individual_plots = TRUE, report_template = "minimal", plot_dpi = 100)
stopifnot(length(viz$plots) >= 5)
# Shared axes and bandwidth make normalized population densities comparable.
population <- dplyr::bind_rows(lapply(c("ID consensus", "MS1 consensus", "MS1 all detections"), function(name) {
  x <- switch(name, "ID consensus" = id, "MS1 consensus" = ms1, "MS1 all detections" = evaluation)
  data.frame(population = name, mz = x$data$Precursor.Mz, rt = x$data$RT.Apex,
    fwhm_sec = aidia:::get_fwhm_values(x))
}))
for (variable in c("mz", "rt", "fwhm_sec")) {
  bandwidth <- stats::bw.nrd0(population[[variable]])
  plot <- ggplot2::ggplot(population, ggplot2::aes(x = .data[[variable]], colour = .data$population)) +
    ggplot2::geom_density(bw = bandwidth) + ggplot2::theme_minimal() +
    ggplot2::labs(title = "SampleA / 60min / Fixed / 01-03", colour = "Input population")
  ggplot2::ggsave(file.path(out, paste0("distribution-", variable, ".png")), plot, width = 9, height = 4.5)
}
after <- tools::md5sum(sources)
stopifnot(identical(before, after))
write.csv(data.frame(path = sources, md5_before = unname(before), md5_after = unname(after)),
  file.path(out, "source_integrity.csv"), row.names = FALSE)
writeLines(capture.output(sessionInfo()), file.path(out, "sessionInfo.txt"))
print(comparison$input_counts)
print(comparison$satisfaction)
cat("\nMatched-condition multi-run smoke completed:", out, "\n")
