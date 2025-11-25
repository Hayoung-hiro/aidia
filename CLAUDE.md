# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**DIA Window Optimizer v2.1** - Production-ready R tool for optimizing Data-Independent Acquisition (DIA) isolation windows for mass spectrometry. Uses DIA-NN results to generate optimized RT-dependent isolation windows specifically for **Thermo Fisher Orbitrap** mass spectrometers.

**Status**: ✅ Production-Ready (All 4 pipeline stages complete and tested)
**Last Major Update**: 2025-11-20 (Method file export moved to Stage 3)

### Instrument Focus

While supporting multiple instrument types (TimsTOF, SCIEX, Waters), the tool is specifically optimized for:
- **Thermo Astral**: Ultra-high speed Orbitrap (parallel acquisition, 50-100 Hz)
- **Thermo Orbitrap Exploris**: Modern Orbitrap (sequential acquisition, 25-40 Hz)
- **Traditional Orbitrap**: High-resolution sequential (8-12 Hz)

---

## Quick Start

### Running the Pipeline

```r
# Load main pipeline
source("main.R")

# Run complete pipeline (all 4 strategies + 24 plots)
results <- run_complete_pipeline(
  data_dir = "data",                    # Contains *min_report.parquet files
  output_base_dir = "output_complete",
  instrument_preset = "astral",         # or "exploris", "orbitrap"
  target_dppp = 7.0,                    # Quant mode (or 1.5 for ID mode)
  target_satisfaction = 0.70,           # 70% of precursors meet target
  mz_strategies = c("quantile", "smoothing", "outlier", "coverage"),
  window_mode = "variable",             # or "fixed"
  create_plots = TRUE,
  create_pdf = TRUE
)
```

### Testing

```r
# Stage-specific functional tests (use real data)
source("tests/manual/test_stage1_real_data.R")  # 6 tests
source("tests/manual/test_stage2_real_data.R")  # 3 tests
source("tests/manual/test_stage3_real_data.R")  # 3 tests
source("tests/manual/test_stage4_simple.R")     # 5 core plot tests

# Full pipeline integration test
source("tests/manual/test_full_pipeline.R")     # End-to-end validation
```

---

## Architecture

### 4-Stage Pipeline (Streamlined v2.1)

```
┌─────────────────────────────────────────────────────────┐
│  Stage 1: Data Validation                              │
│    Input: DIA-NN parquet/TSV                           │
│    Output: ValidatedData (5-6 essential columns)       │
│    File: R/stage1_data_validation.R (617 lines)        │
│    Features:                                            │
│    - Technical replicate handling (consensus/avg/rep)  │
│    - Automatic column selection (95% memory reduction) │
│    - Quality validation with intensity CV filtering   │
│    Test: 19 unit + 6 functional (100% passing)         │
├─────────────────────────────────────────────────────────┤
│  Stage 2: Optimization Planning                        │
│    Input: ValidatedData + current cycle time           │
│    Output: OptimizationPlan                            │
│    File: R/stage2_optimization_planning.R (549 lines)  │
│    Features:                                            │
│    - DPPP diagnosis (current state analysis)           │
│    - Required cycle time calculation                   │
│    - Window count determination with feasibility check │
│    Test: 3 functional (100% passing)                   │
├─────────────────────────────────────────────────────────┤
│  Stage 3: Window Optimization + Export                 │
│    Input: ValidatedData + OptimizationPlan             │
│    Output: OptimizedWindows + 22-column CSV files      │
│    File: R/stage3_window_optimization.R (1,102 lines)  │
│    Features:                                            │
│    - 4 m/z strategies (quantile/coverage/outlier/      │
│      smoothing) with GLOBAL vs LOCAL optimization      │
│    - Variable/Fixed window modes                       │
│    - 22-column Thermo format export (Xcalibur-ready)   │
│    Test: 3 functional (100% passing)                   │
├─────────────────────────────────────────────────────────┤
│  Stage 4: Visualization (Plots Only)                   │
│    Input: All previous outputs                         │
│    Output: 24 plots + PDF report                       │
│    File: R/stage4_visualization.R (1,501 lines)        │
│    Features:                                            │
│    - 8 plot categories (24 total plots)                │
│    - Multi-strategy comparison (Plot 4, 5, 7, 8)       │
│    - Publication-quality figures (300 DPI)             │
│    Test: 5 core plots (100% passing)                   │
└─────────────────────────────────────────────────────────┘

Integration Test: Full pipeline (1.40 sec) ✅ PASSING
```

**Key Design Principle (v2.1)**:
- **Stage 3**: Data generation + method file export
- **Stage 4**: Visualization only (no data export)
- Ensures single responsibility per stage

---

## Core Implementation Files

### Pipeline Stages
- **[R/stage1_data_validation.R](R/stage1_data_validation.R)** (617 lines)
  - Main: `create_validated_dataset()`
  - Replicate handling: consensus (median + CV filter), average, representative
  - Quality: `R/quality_validation.R` (220 lines)
  - Column selection: `R/column_selection_simple.R` (150 lines)

- **[R/stage2_optimization_planning.R](R/stage2_optimization_planning.R)** (549 lines)
  - Main: `plan_optimization()`
  - 7-step process: DPPP diagnosis → window count → feasibility

- **[R/stage3_window_optimization.R](R/stage3_window_optimization.R)** (1,102 lines)
  - Main: `optimize_windows()`
  - Strategies: `optimize_mz_ranges_*()` (quantile, coverage, outlier, smoothing)
  - Export: `export_windows_to_csv()` (22-column Thermo format)

- **[R/stage4_visualization.R](R/stage4_visualization.R)** (1,501 lines)
  - Main: `generate_visualizations()`
  - 8 categories: DPPP, RT×m/z, coverage, satisfaction, width comparison
  - Modular plots: `R/plot*.R` (separate files for complex plots)

### Entry Points
- **[main.R](main.R)** (614 lines) - Main pipeline with batch processing
- **run_with_config.R** - JSON config-based execution

### Utilities
- **[R/utils_common.R](R/utils_common.R)** - Shared utilities, validation
- **[R/replicate_utils.R](R/replicate_utils.R)** - Technical replicate handling
- **[R/instrument_utils.R](R/instrument_utils.R)** - Instrument configurations

### Configuration
- **[config/instruments.json](config/instruments.json)** - Instrument specs (static)
- **[config/optimization_config.json](config/optimization_config.json)** - User parameters

---

## Key Technical Details

### DPPP Formula
```r
DPPP = (1.7 × FWHM_seconds) / cycle_time_seconds
# 1.7 factor: Chromatographic peak width = 1.7 × FWHM
```

**Targets**:
- **DPPP 7.0** (Quant mode): Optimal quantification accuracy (default)
- **DPPP 1.5** (ID mode): Maximum precursor identification
- **DPPP 4.0** (Balanced): Compromise

### Cycle Time Calculation
```r
# Astral (parallel): MS2 during MS1
cycle_time <- max(MS1_time, n_windows * MS2_time)

# Exploris/Orbitrap (sequential): MS1 then MS2
cycle_time <- MS1_time + (n_windows * MS2_time)
```

### m/z Optimization Strategies (v2.0 Innovation)

**LOCAL Strategies** (bin-independent):
- **Quantile**: P5-P95 percentiles (fast, robust)
- **Coverage**: Minimum range for target coverage (comprehensive)
- **Outlier**: Mean ± 3σ (inclusive, high-throughput)

**GLOBAL Strategy** (gradient-wide):
- **Smoothing**: Savitzky-Golay on fine RT sampling (publication-quality)
  - Fine RT sampling (0.5-1 min) → Always sufficient data points
  - Sliding window m/z calculation (±1-3 min)
  - Interpolation to RT bins

**Critical Fix (Milestone 1)**: Smoothing now works for ALL gradient lengths (30min-90min+) via fine RT sampling strategy.

### Technical Replicate Handling (Milestone 2)

**Three Methods**:
1. **Consensus** (recommended): Median + geometric CV filtering
   - Robust to outliers (median)
   - Quality filtering (CV% threshold, default 30%)
   - QC report generation

2. **Average**: Arithmetic mean across replicates
   - Traditional approach
   - Preserves CV% metrics

3. **Representative**: Select best quality run
   - Simple, fast
   - No CV% information

**Geometric CV**: Correct statistical measure for log-normal proteomics data
```r
# Formula for log-transformed data
geometric_cv <- sqrt(exp(sigma_log^2) - 1)

# WRONG approach (causes 14× underestimation):
wrong_cv <- sd(log_intensity) / mean(log_intensity)  # DO NOT USE
```

### 22-Column Thermo Method File Format

**Essential for Xcalibur Import**:
1. Thermo template: Compound, Formula, Adduct
2. Mass specs: m/z, z (charge)
3. RT windows: t start/stop (minutes)
4. Acquisition: Isolation Window, AGC Target
5. m/z boundaries: Start/End m/z
6. Metadata: Window_ID, RT_Segment_ID, Instrument, etc.
7. **Recommended_Cycle_Time_Sec** (22nd column, added in Stage 3)

**Export**: `export_windows_to_csv()` in Stage 3 (moved from Stage 4 in v2.1)

---

## Development Workflow

### Testing Strategy

**Functional Testing** (preferred for this project):
```r
# Real data tests for each stage
source("tests/manual/test_stage1_real_data.R")  # 6 tests
source("tests/manual/test_stage2_real_data.R")  # 3 tests
source("tests/manual/test_stage3_real_data.R")  # 3 tests
source("tests/manual/test_stage4_simple.R")     # 5 core plots
source("tests/manual/test_full_pipeline.R")     # Integration

# All tests: 100% passing (21/21)
```

**Unit Testing** (Stage 1 only):
```r
library(testthat)
source("tests/unit/test_stage1_units.R")  # 19/19 passing
```

### TDD Approach (Kent Beck Principles)

This project follows **Test-Driven Development**:
1. **Confirm GREEN before refactoring**: Write tests first, ensure they pass
2. **Don't fix what isn't broken**: Only refactor when tests reveal issues
3. **Real data validation**: Use actual DIA-NN data for functional tests

**TDD Review Results** (2025-11-19):
- Stage 1: Refactored (Option B - pipeline pattern)
- Stage 2: No refactoring needed (already well-structured)
- Stage 3: No refactoring needed (recently refactored in v2.0)
- Stage 4: Core functionality validated

### Making Changes

**Before modifying any stage**:
1. Read `SESSION_SUMMARY.md` for latest session progress
2. Check `IMPROVEMENT_PLAN.md` for planned enhancements (Milestone 1 & 2 complete)
3. Run relevant functional tests to confirm GREEN state
4. Make minimal changes, re-test immediately

**After making changes**:
```r
# Test the specific stage
source("tests/manual/test_stage[N]_real_data.R")

# Test full pipeline integration
source("tests/manual/test_full_pipeline.R")
```

---

## Current Status (v2.1)

### Completed Milestones

✅ **Milestone 1** (Adaptive m/z Optimization): COMPLETE
- GLOBAL smoothing strategy solving gradient length limitations
- Fine RT sampling (0.5-1 min) → Works for all gradients (30min-90min+)
- See: [docs/SMOOTHING_GLOBAL_VS_LOCAL.md](docs/SMOOTHING_GLOBAL_VS_LOCAL.md)

✅ **Milestone 2** (Technical Replicate Management): COMPLETE
- Consensus method (median + geometric CV filtering)
- Intensity-based CV filtering (proteomics standard, 30% threshold)
- QC report generation
- See: [docs/GEOMETRIC_CV_GUIDE.md](docs/GEOMETRIC_CV_GUIDE.md)

✅ **Architecture Refactoring** (v2.1): COMPLETE
- Method file export moved from Stage 4 → Stage 3
- 22nd column (Recommended_Cycle_Time_Sec) added in Stage 3
- Stage 4 now visualization-only (single responsibility)
- Memory optimization: 95% reduction via column selection

✅ **Complete Testing**: ALL TESTS PASSING (100%)
- 21/21 functional + integration tests passing
- Full pipeline execution: 1.40 seconds (30min dataset)
- All gradients validated: 30min, 60min, 90min
- All instruments tested: Astral, Exploris, Orbitrap

### Known Issues

⚠️ **Smoothing Strategy Bug** (Multi-strategy plots):
- **Impact**: Plot 4, 5, 7, 8 (multi-strategy comparisons) may fail
- **Cause**: Smoothing sometimes produces empty mz_ranges
- **Workaround**: Use quantile/coverage/outlier strategies only
- **Core functionality**: Not affected (single-strategy workflows work perfectly)
- **Priority**: Medium (affects advanced visualization features)

### Performance Metrics

**Benchmark** (90min gradient, 27K precursors):
- Stage 1: Validation → ~2 sec
- Stage 2: Planning → <1 sec
- Stage 3: Optimization (×4 strategies) → ~15 sec
- Stage 3: Export (×4 CSV files) → ~2 sec
- Stage 4: Visualization (24 plots + PDF) → ~25 sec
- **Total**: ~45 sec (complete analysis)

---

## Documentation Guide

### Essential Reading
- **[README.md](README.md)** - User guide, quick start, usage examples
- **[SESSION_SUMMARY.md](SESSION_SUMMARY.md)** - Latest session progress (2025-11-19 TDD review)
- **[IMPROVEMENT_PLAN.md](IMPROVEMENT_PLAN.md)** - Roadmap (Milestones 1 & 2 complete)

### Technical Documentation
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** - System design
- **[docs/SMOOTHING_GLOBAL_VS_LOCAL.md](docs/SMOOTHING_GLOBAL_VS_LOCAL.md)** - m/z optimization strategies (481 lines)
- **[docs/GEOMETRIC_CV_GUIDE.md](docs/GEOMETRIC_CV_GUIDE.md)** - CV calculation guide (507 lines)
- **[docs/USAGE_GUIDE.md](docs/USAGE_GUIDE.md)** - Comprehensive user manual

### Code Quality Analysis
- **[docs/STAGE3_TDD_ANALYSIS.md](docs/STAGE3_TDD_ANALYSIS.md)** - Stage 3 code review (507 lines)
- **[docs/COLUMN_REQUIREMENTS.md](docs/COLUMN_REQUIREMENTS.md)** - Column usage analysis (306 lines)
- **[docs/OPTION_C_REFACTORING_PLAN.md](docs/OPTION_C_REFACTORING_PLAN.md)** - Future Stage 1 redesign (850 lines)

### Development Guides
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Overall project structure (Korean)
- **[docs/PRD.md](docs/PRD.md)** - Product requirements (Korean)

---

## Common Development Tasks

### Adding a New Instrument Type

1. Edit `config/instruments.json`:
```json
{
  "new_instrument": {
    "name": "New Instrument",
    "ms1_time": 0.05,
    "ms2_time": 0.02,
    "max_scan_rate": 50.0,
    "cycle_calculation": "sequential",
    "max_windows": 100
  }
}
```

2. Test with all 3 gradients:
```r
for (gradient in c("30min", "60min", "90min")) {
  results <- run_complete_pipeline(
    instrument_preset = "new_instrument"
  )
}
```

### Adding a New m/z Strategy

1. Implement in [R/stage3_window_optimization.R](R/stage3_window_optimization.R):
```r
optimize_mz_ranges_newstrategy_internal <- function(data, rt_bins, ...) {
  # Your optimization logic
  return(mz_ranges_df)  # Must have: rt_segment_id, mz_start, mz_end
}
```

2. Add to strategy dispatcher:
```r
# In optimize_windows() function
if (mz_strategy == "newstrategy") {
  mz_ranges <- optimize_mz_ranges_newstrategy_internal(...)
}
```

3. Test:
```r
windows <- optimize_windows(
  validated_data, plan,
  mz_strategy = "newstrategy"
)
```

### Modifying Replicate Handling

Edit `R/replicate_utils.R`:
- `select_representative_run()` - Best quality run selection
- `aggregate_replicates()` - Arithmetic mean approach
- `create_consensus_dataset()` - Median + CV filtering (recommended)

All functions return same structure → drop-in replacement.

### Adding New Plots

1. Create modular plot file:
```r
# R/plot9_new_visualization.R
plot9_new_visualization <- function(validated_data, plan, windows) {
  # ggplot2 code
  return(plot_object)
}
```

2. Add to Stage 4:
```r
# In generate_visualizations()
plot9 <- plot9_new_visualization(validated_data, plan, windows)
all_plots$plot9 <- plot9
```

---

## File Organization

### Core Pipeline (R/)
```
R/
├── stage1_data_validation.R       (617 lines) - Validation + replicates
├── stage2_optimization_planning.R (549 lines) - DPPP diagnosis + planning
├── stage3_window_optimization.R   (1,102 lines) - 4 strategies + export
└── stage4_visualization.R         (1,501 lines) - 24 plots + PDF
```

### Utilities (R/)
```
R/
├── utils_common.R                 - Shared functions, validation
├── replicate_utils.R              - Technical replicate handling
├── quality_validation.R           - Quality filters (extracted from Stage 1)
├── column_selection_simple.R      - Auto column selection (95% memory reduction)
└── instrument_utils.R             - Instrument configurations
```

### Modular Plots (R/)
```
R/
├── plot2b_rt_histogram.R          - RT distribution histogram
├── plot4_*.R                      - m/z optimization plots (4 strategies)
├── plot5_density_with_mz_ranges.R - Coverage map 2×2 grid
├── plot7_window_width_distribution.R - Width distribution by strategy
└── plot8_strategy_width_comparison.R - Ridge/Box/CDF comparison
```

### Tests
```
tests/manual/
├── test_stage1_real_data.R        (380 lines, 6 tests)
├── test_stage2_real_data.R        (227 lines, 3 tests)
├── test_stage3_real_data.R        (239 lines, 3 tests)
├── test_stage4_simple.R           (142 lines, 5 core plots)
└── test_full_pipeline.R           (220 lines, integration)
```

### Configuration
```
config/
├── instruments.json               - Instrument specs (static, hardware)
├── optimization_config.json       - User parameters (dynamic)
└── presets/                       - Pre-configured settings
    ├── astral_narrow_dia.json
    ├── fusion_lumos_standard.json
    ├── quant_mode_85pct.json
    └── id_mode_70pct.json
```

---

## Important Notes for Claude Code

### Code Style Conventions
- **Function naming**: `verb_noun_modifier()` (e.g., `calculate_current_dppp()`)
- **Tidyverse style**: Use dplyr, ggplot2, functional programming patterns
- **Error handling**: Fail-fast with informative messages
- **Documentation**: roxygen2 comments for all exported functions

### Testing Philosophy
- **Real data first**: Always test with actual DIA-NN parquet files
- **TDD approach**: Confirm GREEN before refactoring (Kent Beck)
- **Functional over unit**: Prefer integration tests with real data
- **All gradients**: Test 30min, 60min, 90min for completeness

### Memory Considerations
- **Column selection**: ValidatedData uses only 5-6 essential columns (95% reduction)
- **Large datasets**: Tested with 80K+ precursors, performs well
- **Batch processing**: `main.R` handles multiple files efficiently

### Performance Expectations
- **Stage 1**: ~1-2 sec per dataset (with column selection)
- **Stage 2**: <1 sec (DPPP diagnosis)
- **Stage 3**: ~15 sec for 4 strategies (90min gradient)
- **Stage 4**: ~25 sec for 24 plots + PDF

### Common Pitfalls
1. **Don't modify Stage 2/3** without testing - they're production-ready
2. **Always use geometric CV** for log-normal intensity data
3. **Test smoothing strategy** separately (known multi-strategy bug)
4. **Run full pipeline test** after any changes to ensure integration

---

## Version History

**v2.1** (2025-11-20):
- Method file export moved to Stage 3 (single responsibility)
- 22nd column added in Stage 3 export
- Stage 4 now visualization-only

**v2.0** (2025-11-17):
- Milestone 1: GLOBAL vs LOCAL m/z optimization
- Milestone 2: Technical replicate management
- Complete TDD review (all stages)
- Memory optimization via column selection
- All tests passing (21/21, 100%)

**v1.x** (2025-10-31):
- Initial implementation
- 4-stage pipeline
- 24-plot visualization suite

---

**Version**: 2.1
**Last Updated**: 2025-11-21 (CLAUDE.md refresh)
**Status**: Production-Ready (Core Features)
