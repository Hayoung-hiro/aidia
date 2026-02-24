# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AIDIA v0.1.0** (Adaptive Isolation for DIA) - R package for optimizing Data-Independent Acquisition (DIA) isolation windows for mass spectrometry. Uses DIA-NN results to generate optimized RT-dependent isolation windows for **Thermo Fisher Orbitrap** instruments.

**Status**: Development (All 4 pipeline stages complete, packaging in progress)

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
# Functional tests (require real data in data/ directory)
source("tests/manual/test_stage1_real_data.R")
source("tests/manual/test_stage2_real_data.R")
source("tests/manual/test_stage3_real_data.R")
source("tests/manual/test_stage4_simple.R")
source("tests/manual/test_full_pipeline.R")     # End-to-end integration

# Strategy-specific tests
source("tests/manual/test_greedy_strategy.R")
source("tests/manual/test_kde_strategy.R")

# testthat unit tests
testthat::test_dir("tests/testthat")
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
  File:   R/stage1_data_validation.R (537 lines)

Stage 2: Optimization Planning
  Input:  ValidatedData + experiment config
  Output: OptimizationPlan (DPPP diagnosis, window count, cycle time)
  Main:   plan_optimization()
  File:   R/stage2_optimization_planning.R (1,006 lines)

Stage 3: Window Optimization + Export  [MODULARIZED]
  Input:  ValidatedData + OptimizationPlan
  Output: OptimizedWindows + 22-column CSV files
  Main:   optimize_windows()
  File:   R/stage3_window_optimization.R (orchestrator)
          R/stage3_mz_optimization.R (5 strategies)
          R/stage3_window_generation.R (3 modes)
          R/stage3_export.R (Thermo CSV)
          R/stage3_rt_binning.R
          R/stage3_statistics.R

Stage 4: Visualization (Plots Only)
  Input:  All previous outputs
  Output: Plots + PDF report
  Main:   generate_visualizations()
  File:   R/stage4_visualization.R (orchestrator)
          R/plot_*.R (13 modular plot files, including 7 legacy)
```

**Design Principle**: Stage 3 handles all data export. Stage 4 is visualization-only.

### Shared API Layer

Canonical functions that ALL entry points (main.R, inst/shiny_app/app.R) must use:

| Function | Location | Purpose |
|----------|----------|---------|
| `ensure_fwhm_seconds()` | `R/utils_common.R` | Auto-detect minutes vs seconds, convert |
| `estimate_window_count_preview()` | `R/utils_common.R` | Quick window count from FWHM/DPPP/MS2 |
| `extract_gradient_name()` | `R/utils_common.R` | Parse gradient name from file path |
| `estimate_cycle_time()` | `R/utils_common.R` | Estimate cycle time from gradient length |
| `is_orbitrap_instrument()` | `R/instrument_utils.R` | Data-driven from JSON `analyzer_type` |
| `is_astral_instrument()` | `R/instrument_utils.R` | Data-driven from JSON `analyzer_type` |
| `export_windows_to_csv()` | `R/stage3/stage3_export.R` | Unified 22-column Thermo CSV (z=0) |

**Rule**: Never inline FWHM conversion (`median < 1 → *60`) or window count formulas. Always use shared functions.

### S3 Class Hierarchy

Defined in `R/s3_classes.R` (760 lines). Each stage produces a typed S3 object:
- `ValidatedData` → `OptimizationPlan` → `OptimizedWindows`

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

Resolution-to-transient time conversion is handled by `R/instrument_utils.R` (1,534 lines) with per-instrument lookup tables.

### m/z Optimization Strategies (5 total)

**GLOBAL Strategies** (gradient-wide optimization):
| Strategy | Algorithm | SG Smoothing | Best For |
|----------|-----------|:---:|----------|
| **greedy** | MacCoss Lab sliding window | Optional (default ON) | General purpose, recommended |
| **kde** | Kernel Density Estimation | N/A | Peak-focused regions |

**LOCAL Strategies** (per-RT-bin, independent):
| Strategy | Algorithm | SG Smoothing | Best For |
|----------|-----------|:---:|----------|
| **quantile** | P5-P95 percentiles | Optional (default OFF) | Fast, robust |
| **coverage** | Minimum range for target % | N/A | Discovery, comprehensive |
| **outlier** | Mean +/- 3 sigma | Optional (default OFF) | High-throughput, inclusive |

SG smoothing is a post-processing option (`*_apply_smoothing` parameters), not a standalone strategy.

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

`export_windows_to_csv()` in `R/stage3/stage3_export.R` produces Xcalibur-compatible CSV with compound template fields, m/z boundaries, RT windows, and acquisition parameters.

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
3. Stage 3 submodules (`R/stage3_*.R`) are all in `R/` top level (no subdirectories — R packages require flat `R/`)
4. Never inline FWHM conversion — use `ensure_fwhm_seconds()` from `R/utils_common.R`
5. Never inline window count formula — use `estimate_window_count_preview()` from `R/utils_common.R`
6. Deprecated code is in `archive/deprecated_modules/R/` (NOT in `R/`)
7. All plots live in `R/plot_*.R` (flat in `R/`, no subdirectories)
8. Config files: `inst/config/instruments.json` (use `system.file("config", "instruments.json", package = "aidia")`)
9. Shiny app: `inst/shiny_app/` (launch via `aidia::run_aidia_app()`)

---

## Common Development Tasks

### Adding a New m/z Strategy

1. Implement in `R/stage3_mz_optimization.R`:
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
3. Add to Shiny `selectInput` choices in `inst/shiny_app/app.R`
4. Instrument classification (`is_orbitrap_instrument()` etc.) is automatic from JSON `analyzer_type`

### Adding New Plots

1. Create `R/plot_new.R` with function returning a ggplot object (flat in `R/`, no subdirectories)
2. Add to `generate_visualizations()` in `R/stage4_visualization.R`

---

## Dependencies

Core (Imports in DESCRIPTION):
- `dplyr`, `tibble`, `tidyr`, `arrow`, `ggplot2`, `jsonlite`
- `scales`, `ggridges`, `viridis`, `gridExtra`, `grid`, `stats`, `utils`, `grDevices`

Optional (Suggests in DESCRIPTION):
- `prospectr` (Savitzky-Golay), `yaml` (config)
- `shiny` + `bs4Dash` + `shinyjs` + `shinybusy` + `DT` (web app)
- `future` + `future.apply` (parallel processing)
- `testthat`, `knitr`, `rmarkdown` (dev/docs)

---

## Version History

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
- Archived 81 dead files to `archive/`

**v2.1** (2025-11): Method file export moved to Stage 3

**v2.0** (2025-11): GLOBAL/LOCAL m/z optimization, technical replicates, TDD review

**v1.x** (2025-10): Initial 4-stage pipeline
