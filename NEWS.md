# aidia 0.4.0

## Reporting redesign and publication export

* `export_publication_figures()` and `get_journal_preset()`:
  re-render any subset of plots at journal-specific dimensions and
  theme sizing. Presets cover JPR, MCP, Anal Chem, Nature Methods,
  Proteomics, and JASMS for single/1.5/double column widths
* PDF/SVG/TIFF (LZW)/PNG @ 600 DPI output, with optional multi-panel
  assembly and A/B/C tagging via `patchwork` (Suggests)
* `compute_data_summary()`: shared data statistics consumed by both
  the PDF report and the Shiny data summary panel
* Plot infrastructure prepared for publication rendering: `base_size`
  parameter on table/grob plots, `aidia_colors` token replacement of
  hardcoded fills/lines
* Reporting redesign: 3-section + appendices PDF structure with
  unified plot key naming (`s{section}_{order}_{name}`,
  `app_{appendix}_{name}`)
* Baseline comparisons added to S2 plots: full m/z range overlay on
  window coverage, dodged Baseline vs Optimized load balance with CV
  delta, equal-width temporal density before/after subtitle
* Active strategy highlighting on S3 cross-strategy plots: bold table
  row, fully opaque ridge with selected marker, emphasized width
  profile line and points

## v0.4.0 baseline (Astral sync-first UX + strategy unification)

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
