# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AIDIA v0.3.0** (Adaptive Isolation for DIA) - R package for optimizing Data-Independent Acquisition (DIA) isolation windows for mass spectrometry. Uses DIA-NN results to generate optimized RT-dependent isolation windows for **Thermo Fisher Orbitrap** instruments.

**Status**: Development (4-stage pipeline complete, modular architecture)

### Instrument Focus

Verified Thermo Orbitrap instruments (primary targets):
- **Astral / Astral Zoom**: Ultra-high speed (parallel acquisition, 200-270 Hz)
- **Exploris 480**: Modern Orbitrap (sequential, 40 Hz)
- **Q Exactive HF-X / Q Exactive**: Sequential (12-40 Hz)
- **Eclipse Tribrid / Fusion Lumos**: Sequential (20-40 Hz)

Planned (not yet verified): Bruker TimsTOF, SCIEX ZenoTOF, Waters SYNAPT

---

## Quick Start

### Running the Pipeline

```r
source("main.R")

results <- run_complete_pipeline(
  data_dir = "data",                    # Contains *report.parquet files
  output_base_dir = "output_complete",
  instrument_preset = "astral",         # or "exploris", "qexactive_hfx", etc.
  target_dppp = 7.0,                    # Quant mode (or 1.5 for ID mode)
  target_satisfaction = 0.70,
  mz_strategies = c("greedy", "kde", "quantile", "coverage", "outlier"),
  window_mode = "density",              # or "fixed", "staggered"
  create_plots = TRUE,
  create_pdf = TRUE
)
```


### Testing

```r
# testthat unit tests (recommended — uses devtools::load_all() automatically)
devtools::test()

# Functional tests (require real data in data/ directory)
source("tests/manual/test_stage1_real_data.R")
source("tests/manual/test_stage2_real_data.R")
source("tests/manual/test_stage3_real_data.R")
source("tests/manual/test_stage4_simple.R")
source("tests/manual/test_full_pipeline.R")     # End-to-end integration

# Strategy-specific tests
source("tests/manual/test_greedy_strategy.R")
source("tests/manual/test_kde_strategy.R")
```

### Shiny Web App

```r
# Option 1: Package function (recommended)
aidia::run_aidia_app()

# Option 2: Development mode
shiny::runApp(system.file("shiny_app", package = "aidia"))
```

---

## Architecture

### 4-Stage Pipeline

```
Stage 1: Data Validation
  Input:  DIA-NN parquet/TSV
  Output: ValidatedData (5-6 essential columns)
  Main:   create_validated_dataset()
  File:   R/data_validation.R

Stage 2: Optimization Planning
  Input:  ValidatedData + experiment config
  Output: OptimizationPlan (DPPP diagnosis, window count, cycle time)
  Main:   plan_optimization()
  File:   R/optimization_planning.R

Stage 3: Window Optimization + Export
  Input:  ValidatedData + OptimizationPlan
  Output: OptimizedWindows + 22-column CSV files
  Main:   optimize_windows()  (accepts optional strategy_config)
  File:   R/window_optimization.R (orchestrator)
          R/strategy_config.R (5 strategy constructors)
          R/mz_optimization.R (5 strategies)
          R/window_generation.R (3 modes)
          R/export_methods.R (Thermo CSV)
          R/rt_binning.R
          R/window_statistics.R

Stage 4: Visualization (Plots Only)
  Input:  All previous outputs
  Output: Plots + PDF report
  Main:   generate_visualizations()
  File:   R/visualization.R (orchestrator)
          R/plot_*.R (15 modular plot files)
```

**Design Principle**: Stage 3 handles all data export. Stage 4 is visualization-only.

### Shared Utility Modules

Extracted from the original monolithic `utils_common.R`:

| Module | Contents |
|--------|----------|
| `R/dppp.R` | `PEAK_WIDTH_FACTOR`, `calculate_dppp()`, `ensure_fwhm_seconds()`, `estimate_window_count_preview()` |
| `R/precursor_matching.R` | `count_precursors_in_windows()`, `count_precursors_in_2d_windows()`, `calculate_precursor_temporal_density()` |
| `R/validation_helpers.R` | `validate_input_type()`, `validate_numeric_range()`, `validate_positive_integer()` |
| `R/strategy_config.R` | `greedy_config()`, `quantile_config()`, `coverage_config()`, `outlier_config()`, `kde_config()` |
| `R/smoothing_utils.R` | `smooth_whittaker()`, `smooth_savgol()`, `smooth_boundaries()` (dispatcher) |
| `R/bootstrap_boundary.R` | `bootstrap_boundary_ci()`, `compute_mz_boundaries_quiet()` |
| `R/utils_common.R` | Progress/UI helpers, stats, data access, timing, output filenames, gradient heuristics |

### Shared API Layer

Canonical functions that ALL entry points (main.R, Shiny app) must use:

| Function | Location | Purpose |
|----------|----------|---------|
| `ensure_fwhm_seconds()` | `R/dppp.R` | Auto-detect minutes vs seconds, convert |
| `estimate_window_count_preview()` | `R/dppp.R` | Quick window count from FWHM/DPPP/MS2 |
| `extract_gradient_name()` | `R/utils_common.R` | Parse gradient name from file path |
| `estimate_cycle_time()` | `R/utils_common.R` | Estimate cycle time from gradient length |
| `is_orbitrap_instrument()` | `R/instrument_utils.R` | Data-driven from JSON `analyzer_type` |
| `is_astral_instrument()` | `R/instrument_utils.R` | Data-driven from JSON `analyzer_type` |
| `export_windows_to_csv()` | `R/export_methods.R` | Unified 22-column Thermo CSV (z=0) |
| `calculate_duty_cycle_sync()` | `R/instrument_utils.R` | Duty cycle % and idle times for parallel instruments |
| `calculate_sync_optimal_windows()` | `R/instrument_utils.R` | Sync-optimal window count for parallel instruments |
| `get_instrument_width_recommendations()` | `R/instrument_utils.R` | Per-instrument min/max width from JSON |
| `calculate_precursor_temporal_density()` | `R/precursor_matching.R` | Sweepline co-elution density (lower bound) |

**Rule**: Never inline FWHM conversion (`median < 1 → *60`) or window count formulas. Always use shared functions.

### S3 Class Hierarchy

Defined in `R/s3_classes.R` (766 lines). Each stage produces a typed S3 object:
- `ValidatedData` → `OptimizationPlan` → `OptimizedWindows`

### Shiny App Module Structure

3-Step Wizard (Data → Setup → Results), decomposed into 7 files:

```
inst/shiny_app/
  app.R                  (orchestrator: source + wire modules)
  ui_step1_data.R        (Step 1: upload, data summary, DPPP preview)
  ui_step2_setup.R       (Step 2: instrument, strategy, RT binning, expert)
  ui_step3_results.R     (Step 3: before/after, window preview, downloads)
  server_instrument.R    (cycle time reactive — returned to other modules)
  server_data.R          (upload handler, DPPP preview, info boxes)
  server_optimization.R  (run optimization, results display, summary tables)
  server_downloads.R     (CSV + PDF download handlers)
```

Key design: `server_instrument()` returns the `cycle_time_result` reactive, which `server_data()` and `server_optimization()` receive as a parameter. No Shiny `NS()` namespacing — all `conditionalPanel` JS conditions preserved as-is.

**Strategy/Mode Previews**: Step 2 displays pre-generated schematic PNGs from `inst/shiny_app/www/strategy_previews/` when users select a strategy or window mode. Images are rendered via `renderUI` in `server_optimization.R`. KDE/Coverage selections include a collapsible bimodal comparison panel. Generate previews: `source("tests/manual/generate_schematic_previews.R")`.

---

## Key Technical Details

### DPPP Formula
```r
DPPP = (1.7 * FWHM_seconds) / cycle_time_seconds
```
Targets: 7.0 (quant), 4.0 (balanced), 1.5 (ID mode)

### Cycle Time Calculation
```r
# Astral (parallel): MS2 during MS1
cycle_time <- max(MS1_time, n_windows * MS2_time)

# Exploris/Orbitrap (sequential): MS1 then MS2
cycle_time <- MS1_time + (n_windows * MS2_time)
```

Resolution-to-transient time conversion is handled by `R/instrument_utils.R` (1,299 lines) with per-instrument lookup tables.

### Strategy Config Objects

Instead of passing 15+ flat parameters to `optimize_windows()`, use typed config constructors:

```r
# New way (recommended)
optimize_windows(data, plan, strategy_config = greedy_config(apply_smoothing = TRUE))
optimize_windows(data, plan, strategy_config = kde_config(density_threshold = 0.05))

# Legacy way (still works, full backward compatibility)
optimize_windows(data, plan, mz_strategy = "quantile", quantile_lower = 0.05)
```

Constructors: `greedy_config()`, `quantile_config()`, `coverage_config()`, `outlier_config()`, `kde_config()`

### m/z Optimization Strategies (5 total)

**GLOBAL Strategies** (gradient-wide optimization):
| Strategy | Algorithm | Smoothing | Best For |
|----------|-----------|:---:|----------|
| **greedy** | MacCoss Lab sliding window | WH (default ON) | General purpose, recommended |
| **kde** | Kernel Density Estimation | N/A | Peak-focused regions |

**LOCAL Strategies** (per-RT-bin, independent):
| Strategy | Algorithm | Smoothing | Best For |
|----------|-----------|:---:|----------|
| **quantile** | P5-P95 percentiles | WH (default ON) | Fast, robust |
| **coverage** | Minimum range for target % | N/A | Discovery, comprehensive |
| **outlier** | Mean +/- 3 sigma | WH (default ON) | High-throughput, inclusive |

Boundary smoothing uses Whittaker-Henderson (WH) by default with per-point `sqrt(n_precursors)` weights. Savitzky-Golay (SG) available via `smoothing_method = "sg"`. Smoothing is a post-processing option (`*_apply_smoothing` parameters), not a standalone strategy.

### Bootstrap Boundary CI

`bootstrap_boundary_ci()` estimates m/z boundary uncertainty via stratified bootstrap resampling. Precursors are resampled with replacement within each RT bin, and boundaries are recalculated N times to produce percentile-based CIs.

```r
ci <- bootstrap_boundary_ci(validated, plan, strategy_config = greedy_config(), n_boot = 200)
plot_boundary_ci(ci, validated)           # density heatmap + CI ribbons
plot_boundary_ci_width(ci)                # per-bin CI bar chart
plot_boundary_ci_comparison(ci_a, ci_b)   # compare two methods
```

### Window Modes (3 total)

- **density** (variable): Adaptive width based on precursor density per RT bin
- **fixed**: Equal-width windows across m/z range
- **staggered**: Alternating offset between odd/even RT bins (reduces boundary effects)

### Technical Replicate Handling

Three methods in `R/replicate_utils.R`:
1. **Consensus** (recommended): Median + geometric CV filtering (30% threshold)
2. **Average**: Arithmetic mean across replicates
3. **Representative**: Select best quality run

**Geometric CV** for log-normal proteomics data: `sqrt(exp(sigma_log^2) - 1)`

### 22-Column Thermo Method File Export

`export_windows_to_csv()` in `R/export_methods.R` produces Xcalibur-compatible CSV with compound template fields, m/z boundaries, RT windows, and acquisition parameters.

---

## Development Workflow

### Before Modifying Code

1. Run relevant functional tests to confirm GREEN state
2. Make minimal changes, re-test immediately
3. Run `source("tests/manual/test_full_pipeline.R")` after any stage changes

### Testing Philosophy

- **Real data first**: Functional tests use actual DIA-NN parquet files in `data/`
- **TDD approach**: Confirm GREEN before refactoring (Kent Beck)
- **Functional over unit**: Prefer integration tests with real data
- Tests are in `tests/manual/` (source-based) and `tests/testthat/` (automated)

### Code Style

- **Function naming**: `verb_noun_modifier()` (e.g., `calculate_current_dppp()`)
- **Tidyverse style**: dplyr pipes, ggplot2, functional programming
- **Error handling**: Fail-fast with informative `stop()` messages
- **Documentation**: roxygen2 `@param`/`@return` for exported functions

### Common Pitfalls

1. Always use **geometric CV** for log-normal intensity data (arithmetic CV underestimates by ~14x)
2. Run full pipeline test after any changes to ensure stage integration
3. Stage 3 submodules are all in `R/` top level (no subdirectories — R packages require flat `R/`)
4. Never inline FWHM conversion — use `ensure_fwhm_seconds()` from `R/dppp.R`
5. Never inline window count formula — use `estimate_window_count_preview()` from `R/dppp.R`
6. All plots live in `R/plot_*.R` (flat in `R/`, no subdirectories)
7. Config files: `inst/config/instruments.json` (use `system.file("config", "instruments.json", package = "aidia")`)
8. Shiny app: `inst/shiny_app/` — 7 module files, launch via `aidia::run_aidia_app()`
9. Run `devtools::test()` (not `testthat::test_dir()`) for unit tests during development

---

## Common Development Tasks

### Adding a New m/z Strategy

1. Implement in `R/mz_optimization.R`:
```r
optimize_mz_ranges_newstrategy_internal <- function(data, rt_bins, ...) {
  return(mz_ranges_df)  # Must have: rt_segment_id, mz_start, mz_end
}
```

2. Add to strategy dispatcher in `optimize_mz_ranges_internal()`

3. Test: `optimize_windows(validated_data, plan, mz_strategy = "newstrategy")`

### Adding a New Instrument

1. Add to `inst/config/instruments.json` with scan times, cycle calculation mode, and `analyzer_type`
2. Add resolution/transient lookup table in `R/instrument_utils.R` (if Orbitrap)
3. Add to Shiny `selectInput` choices in `inst/shiny_app/ui_step2_setup.R`
4. Instrument classification (`is_orbitrap_instrument()` etc.) is automatic from JSON `analyzer_type`

### Adding New Plots

1. Create `R/plot_new.R` with function returning a ggplot object (flat in `R/`, no subdirectories)
2. Add to `generate_visualizations()` in `R/visualization.R`

---

## Verification Skills

| Skill | Description |
|-------|-------------|
| `verify-shiny-design` | CSS token compliance, shared API usage, typography hierarchy in Shiny app |
| `verify-instrument-config` | JSON schema consistency, shared API usage, overhead plausibility, export format alignment |
| `verify-implementation` | Run all verify skills sequentially, produce unified report |

---

## Dependencies

Core (Imports in DESCRIPTION):
- `dplyr`, `tibble`, `tidyr`, `arrow`, `ggplot2`, `jsonlite`
- `scales`, `ggridges`, `viridis`, `gridExtra`, `grid`, `stats`, `utils`, `grDevices`

Optional (Suggests in DESCRIPTION):
- `prospectr` (Savitzky-Golay), `yaml` (config)
- `shiny` + `bs4Dash` + `shinyjs` + `shinybusy` + `DT` (web app)
- `testthat`, `knitr`, `rmarkdown` (development, documentation)

---

## Version History

**v0.4.0** (2026-03): Astral Sync-First UX + Strategy Unification
- **Conditional Step 2 layout**: Parallel instruments get sync-first Section A; sequential keeps DPPP layout
- Sync-first hero: sync-optimal window count as primary, DPPP as confirmation badge
- `output$is_parallel_instrument` reactive for conditional UI rendering
- `auto_windows_info` now reactive to `target_satisfaction` for sequential instruments
- Unified auto window count across all 5 strategies (was greedy-only)
- Quantile and outlier smoothing defaults changed to ON (Whittaker-Henderson)

**v0.3.1** (2026-03): Astral Optimization — Duty Cycle Sync + Temporal Density
- **Duty cycle sync** for parallel instruments: `calculate_duty_cycle_sync()`, `calculate_sync_optimal_windows()`
- Sync-first window count for Astral: uses sync-optimal N instead of DPPP-only
- **Precursor temporal density**: sweepline co-elution proxy in `calculate_precursor_temporal_density()`
- `evaluate_windows()` extended with `temporal_density_max`, `temporal_density_mean` per window
- New plot: `plot_temporal_density()` — geom_rect heatmap with inferno colorscale
- Per-instrument width recommendations from JSON (`recommended_min_width_da`, `recommended_max_width_da`)
- `ms2_overhead_ms` added to all instruments in JSON (replaces hardcoded 2.0 for Astral)
- Shiny: duty cycle sync badge in Step 2, temporal density plot in Step 3
- Shiny: instrument-specific width defaults auto-populate on selection
- Removed `astral_sensitive` (not a real instrument model)
- Boxcar/MAP-MS concept documented (deferred to v0.4.0)

**v0.2.1** (2026-03): Smoothing, Bootstrap CI, Visualization & Preview
- Whittaker-Henderson (WH) smoother now **default** for all strategies (SG available via `smoothing_method = "sg"`)
- Bootstrap boundary CI: `bootstrap_boundary_ci()` with stratified resampling + 3 visualization functions
- Visualization overhaul: 5 new plots, PDF restructure, data-driven FZ zoom
- Strategy/mode schematic previews: 18 PNGs in `inst/shiny_app/www/strategy_previews/`
- Shiny Step 2 preview integration: live image display on strategy/mode selection
- KDE vs Coverage bimodal comparison diagram
- DRY refactoring: `extract_before_after_metrics()`, `select_median_rt_segment()`, vectorized FZ transform

**v0.2.0** (2026-02): Modular architecture refactoring
- Exports reduced 149 → 61 (internal functions marked `@keywords internal`)
- Removed source()-era scaffolding (`isNamespaceLoaded` guards, module `cat()` messages)
- Removed `future`/`future.apply` parallel processing (sequential `lapply` only)
- Split `utils_common.R` into cohesive modules: `dppp.R`, `precursor_matching.R`, `validation_helpers.R`
- Added `strategy_config.R`: typed config constructors for `optimize_windows()` (backward compatible)
- Decomposed Shiny app from monolithic 2,564-line `app.R` into 7 module files
- 3-Step Wizard UI (Data → Setup → Results) with progressive disclosure

**v0.1.0** (2026-02): R package packaging
- Proper R package structure: DESCRIPTION, NAMESPACE, .Rbuildignore, inst/
- Flattened R/ (no subdirectories — R package requirement)
- Config files moved to inst/config/ (system.file() access)
- Shiny app moved to inst/shiny_app/ with run_aidia_app() launcher
- Removed top-level library()/cat() calls, guarded source() for package compliance
- Version reset to 0.1.0 for development phase

**v1.0.0** (2026-02): AIDIA rebrand (pre-packaging)
- Rebranded from "DIA Window Optimizer"
- Added Greedy + KDE strategies (5 total), removed standalone Smoothing
- Added Staggered window mode (3 total)
- Shiny web app with bs4Dash (3-tab body layout)
- Cycle time calculator with resolution-to-transient mapping
- Shared API layer: `ensure_fwhm_seconds()`, `estimate_window_count_preview()`, data-driven instrument classification
- Removed legacy development artifacts from repository

**v2.1** (2025-11): Method file export moved to Stage 3

**v2.0** (2025-11): GLOBAL/LOCAL m/z optimization, technical replicates, TDD review

**v1.x** (2025-10): Initial 4-stage pipeline
