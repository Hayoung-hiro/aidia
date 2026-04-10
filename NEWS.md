# aidia 0.4.0

* Conditional Step 2 layout: parallel instruments get sync-first Section A;
  sequential instruments keep DPPP layout
* Sync-first hero: sync-optimal window count as primary metric for Astral
* FZ offset validation plot with mass defect period (1.00045475 Da)
* Unified auto window count across all 5 strategies (was greedy-only)
* Smoothing defaults: quantile and outlier now ON (Whittaker-Henderson)
* `auto_windows_info` now reactive to `target_satisfaction` for sequential
  instruments
* Window count ValueBox shows actual per-bin count from results

# aidia 0.3.1

* Duty cycle sync for parallel instruments: `calculate_duty_cycle_sync()`,
* `calculate_sync_optimal_windows()`
* Precursor temporal density via sweepline algorithm
* `evaluate_windows()` extended with `temporal_density_max`,
  `temporal_density_mean` per window
* New plot: `plot_temporal_density()` with inferno colorscale
* Per-instrument width recommendations from JSON config
* `ms2_overhead_ms` added to all instruments (replaces hardcoded values)
* Removed `astral_sensitive` (not a real instrument model)
* Shiny: duty cycle sync badge, temporal density plot, auto-populate width
  defaults

# aidia 0.2.1

* Whittaker-Henderson (WH) smoother now default for all strategies
* Savitzky-Golay available via `smoothing_method = "sg"`
* Bootstrap boundary CI: `bootstrap_boundary_ci()` with stratified resampling
* 3 new CI visualization functions
* 5 new plots, PDF report restructure, data-driven FZ zoom
* Strategy/mode schematic previews (18 PNGs) for Shiny Step 2
* KDE vs Coverage bimodal comparison diagram
* DRY refactoring: `extract_before_after_metrics()`,
  `select_median_rt_segment()`, vectorized FZ transform

# aidia 0.2.0

* Modular architecture refactoring
* Exports reduced 149 to 61 (internal functions marked `@keywords internal`)
* Removed `future`/`future.apply` parallel processing
* Split `utils_common.R` into `dppp.R`, `precursor_matching.R`,
  `validation_helpers.R`
* Added `strategy_config.R`: typed config constructors for `optimize_windows()`
* Decomposed Shiny app from monolithic 2,564-line `app.R` into 7 module files
* 3-Step Wizard UI (Data, Setup, Results) with progressive disclosure

# aidia 0.1.0

* R package structure: DESCRIPTION, NAMESPACE, .Rbuildignore, inst/
* Flattened R/ directory (no subdirectories, R package requirement)
* Config files moved to inst/config/ with `system.file()` access
* Shiny app moved to inst/shiny_app/ with `run_aidia_app()` launcher
* Removed top-level `library()`/`cat()` calls for package compliance
