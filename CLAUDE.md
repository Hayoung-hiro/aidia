# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DIA Window Optimizer is an R-based tool for optimizing Data-Independent Acquisition (DIA) isolation windows for mass spectrometry. It implements a **streamlined 3-stage pipeline** for DIA window optimization using DIA-NN results to diagnose current DPPP status and generate optimized RT-dependent isolation windows.

**Version 2.0 Refactored** (2025-10-25): Unified architecture with improved performance and reduced code complexity.

The tool is specifically designed for the **Thermo Fisher Orbitrap family** of mass spectrometers, with particular optimization for:

- **Thermo Astral**: Ultra-high speed Orbitrap with parallel acquisition (50-100 Hz scan rate)
- **Thermo Orbitrap Exploris**: Modern Orbitrap with sequential acquisition (25-40 Hz scan rate)
- **Traditional Orbitrap**: High-resolution sequential acquisition (8-12 Hz scan rate)

While other instrument types (TimsTOF, SCIEX, Waters) are supported, the optimization algorithms are tailored to Orbitrap-specific acquisition patterns and timing constraints.

---

## Architecture Overview

### Refactored 3-Stage Pipeline (v2.0)

```
┌─────────────────────────────────────────────────────────────┐
│              Streamlined 3-Stage Pipeline (v2.0)            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  [Stage 1] Data Validation                                  │
│      Input: DIA-NN output (+ Raw files, optional)          │
│      Output: ValidatedData object                           │
│      File: R/stage1_data_validation.R (existing)           │
│      ↓                                                       │
│  [Stage 2] Optimization Planning (MERGED)                   │
│      Input: ValidatedData + current cycle time              │
│      Combines:                                              │
│        - DPPP Diagnosis                                     │
│        - Window Count Determination                         │
│      Output: OptimizationPlan object                        │
│      File: R/stage2_optimization_planning.R (NEW)          │
│      ↓                                                       │
│  [Stage 3] Window Optimization (UNIFIED)                    │
│      Input: ValidatedData + OptimizationPlan                │
│      Combines:                                              │
│        - RT Binning (internal)                              │
│        - m/z Range Optimization                             │
│        - Window Generation                                  │
│      Output: OptimizedWindows object                        │
│      File: R/stage3_window_optimization.R (NEW)            │
│      ↓                                                       │
│  [Stage 4] Visualization & Reporting                        │
│      Input: All previous outputs                            │
│      Output: Plots + PDF report + method file              │
│      File: R/stage4_visualization.R (to be updated)        │
│                                                              │
└─────────────────────────────────────────────────────────────┘

🔧 Common Utilities: R/utils_common.R (NEW)
   - Shared functions for validation, statistics, performance
   - 50-100x faster precursor-window matching
   - Unified progress reporting and error handling
```

### Core Design Principles

- **Diagnosis First**: Analyze current DPPP status before generating new windows
- **User-Centric**: Support both Quant mode (DPPP 7.0) and ID mode (DPPP 1.5)
- **Modular**: Each stage is independently developable and testable
- **Evidence-Based**: Use actual injection time from raw files when available

---

## Key Features

### Stage 1: Data Validation
- **DIA-NN Output Loading**: Parquet/TSV/CSV with automatic column detection
- **Raw File Metadata** (optional): Extract actual injection times for enhanced analysis
- **Required Columns**: RT.Start, Precursor.Mz, FWHM
- **Data Quality Validation**: Outlier detection, range checks, missing value handling

### Stage 2: Optimization Planning (v2.0 - Merged Module)
**Combines DPPP Diagnosis + Window Count Determination**
- **Current DPPP Analysis**: Calculate DPPP distribution from FWHM data
- **Satisfaction Ratio**: % of precursors meeting target DPPP
- **Required Cycle Time**: Calculate maximum cycle time for target DPPP
- **Window Count Determination**: Optimal windows per RT bin
- **Feasibility Checks**: Scan rate, cycle time, instrument constraints
- **Unified Output**: Single OptimizationPlan object with all recommendations

### Stage 3: Window Optimization (v2.0 - Unified Module)
**Combines RT Binning + m/z Optimization + Window Generation**

**Internal Steps** (automated, not exposed to user):
1. **RT Binning**: Time-based segmentation (e.g., 5-minute bins)
2. **m/z Range Optimization**: Per-RT-bin range optimization
   - Quantile strategy: Fast and robust (P5-P95)
   - Coverage strategy: Minimum range for target coverage
3. **Window Generation**: Per-RT-bin window creation
   - Fixed mode: Equal-width windows
   - Variable mode: Density-based adaptive windows (recommended)
4. **Performance Optimization**: Vectorized precursor-window matching (50-100x faster)
5. **Statistics Calculation**: Coverage, uniformity, quality metrics

**Key Improvements**:
- Single function call for complete optimization
- Reduced intermediate objects (better memory efficiency)
- Optimized algorithms (dramatic speed improvement)
- Consistent error handling and validation

### Stage 4: Visualization & Reporting
- **8 Essential Plots**: DPPP density, RT allocation, coverage, efficiency, etc.
- **PDF Report**: Comprehensive multi-panel report
- **Method File**: CSV format for Thermo Orbitrap programming
- **Individual Plots**: High-resolution PNG/PDF export

---

## Development Workflow

### Project Structure

```
dia_window_optimizer/
├── DEVELOPMENT.md                      # Main development guide
├── CLAUDE.md                           # This file - Claude Code guidance
├── README.md                           # User documentation
│
├── docs/
│   ├── PRD.md                         # Product requirements (Korean)
│   ├── ARCHITECTURE.md                # System architecture
│   ├── API_SPECIFICATION.md           # Module I/O specifications
│   │
│   └── phases/                        # Phase-by-phase development guides
│       ├── PHASE1_DATA_VALIDATION.md
│       ├── PHASE2_DPPP_DIAGNOSIS.md
│       ├── PHASE3A_WINDOW_COUNT.md
│       ├── PHASE3B_RT_BINNING.md
│       ├── PHASE3C_MZ_RANGE.md
│       ├── PHASE3D_WINDOW_GENERATION.md
│       └── PHASE4_VISUALIZATION.md
│
├── R/
│   ├── stage1_data_validation.R       # Phase 1 implementation
│   ├── stage2_dppp_diagnosis.R        # Phase 2 implementation
│   ├── stage3_window_optimization/
│   │   ├── module3a_window_count.R    # Phase 3A
│   │   ├── module3b_rt_binning.R      # Phase 3B wrapper
│   │   ├── module3c_mz_range_optimization.R  # Phase 3C
│   │   └── module3d_window_generation.R      # Phase 3D
│   ├── stage4_visualization.R         # Phase 4 implementation
│   │
│   ├── rt_segmentation.R              # Existing RT binning (used by 3B)
│   ├── window_generator.R             # Existing Variable mode (used by 3D)
│   ├── mz_boundaries.R                # Existing smoothing (used by 3C)
│   ├── dynamicDIA.R                   # DynamicDIA smoothing algorithms
│   │
│   ├── data_loader.R                  # Data loading utilities
│   ├── dppp_calculator.R              # DPPP calculation engine
│   ├── visualizer.R                   # Visualization utilities
│   ├── method_writer.R                # Method file export
│   └── utils.R                        # General utilities
│
├── tests/
│   ├── mocks/                         # Mock data generators
│   │   ├── mock_stage1_output.R
│   │   ├── mock_stage2_output.R
│   │   ├── mock_stage3a_output.R
│   │   ├── mock_stage3b_output.R
│   │   ├── mock_stage3c_output.R
│   │   ├── mock_stage3d_output.R
│   │   └── mock_stage4_output.R
│   │
│   └── fixtures/                      # Test data
│       ├── stage1_output.rds
│       ├── stage2_output.rds
│       └── ...
│
└── config/
    └── instruments.R                  # Instrument configurations
```

### Development Phases

**Current Status**: 🔴 All phases in development

| Phase | File | Status | Priority |
|-------|------|--------|----------|
| Phase 1 | `R/stage1_data_validation.R` | 🔴 Not started | ⭐⭐⭐ High |
| Phase 2 | `R/stage2_dppp_diagnosis.R` | 🔴 Not started | ⭐⭐⭐ High |
| Phase 3A | `R/stage3_window_optimization/module3a_window_count.R` | 🔴 Not started | ⭐⭐⭐ High |
| Phase 3B | `R/stage3_window_optimization/module3b_rt_binning.R` | ✅ Existing code | ⭐⭐ Integration only |
| Phase 3C | `R/stage3_window_optimization/module3c_mz_range_optimization.R` | 🔴 Not started | ⭐⭐ Medium |
| Phase 3D | `R/stage3_window_optimization/module3d_window_generation.R` | 🟡 Partial | ⭐⭐ Medium |
| Phase 4 | `R/stage4_visualization.R` | 🔴 Not started | ⭐ Low |

### Independent Development

Each phase can be developed independently on different machines using:
- **Phase-specific guides**: See `docs/phases/PHASE[N]_*.md`
- **Mock data**: Use `tests/mocks/mock_stage[N]_output.R`
- **API specs**: See `docs/API_SPECIFICATION.md`

Example workflow for Phase 2 development without Phase 1 complete:
```r
# On PC-A: Develop Phase 2 independently
source("tests/mocks/mock_stage1_output.R")
validated_data <- create_mock_stage1_output()

# Develop Phase 2 functions
source("R/stage2_dppp_diagnosis.R")
result <- diagnose_dppp_status(validated_data, ...)

# Test Phase 2
source("tests/test_stage2.R")
test_file("tests/test_stage2.R")
```

---

## Common Development Commands

### Setup

```r
# Install required packages
install.packages(c("arrow", "dplyr", "ggplot2", "gridExtra",
                   "jsonlite", "tidyr", "viridis", "scales",
                   "prospectr", "testthat"))
```

### Running Tests

```r
# Run specific phase tests
library(testthat)
source("tests/test_stage1.R")
test_file("tests/test_stage1.R")

# Run all tests
test_dir("tests/")
```

### Development Workflow

```r
# 1. Read phase development guide
# docs/phases/PHASE2_DPPP_DIAGNOSIS.md

# 2. Create mock input data
source("tests/mocks/mock_stage1_output.R")
input_data <- create_mock_stage1_output()

# 3. Implement phase functions
source("R/stage2_dppp_diagnosis.R")

# 4. Test implementation
source("tests/test_stage2.R")
test_file("tests/test_stage2.R")

# 5. Create mock output for next phase
source("tests/mocks/mock_stage2_output.R")
mock_output <- create_mock_stage2_output()
saveRDS(mock_output, "tests/fixtures/stage2_output.rds")
```

---

## Key Technical Details

### DPPP Formula

```r
# Spectronaut standard
DPPP = (1.7 × FWHM_seconds) / cycle_time_seconds

# 1.7 factor: Chromatographic peak width = 1.7 × FWHM
```

### DPPP Targets by Mode

- **Quant Mode (DPPP 7.0)**: Optimal for quantification accuracy (default, preferred)
- **ID Mode (DPPP 1.5)**: Optimal for maximum precursor identification
- **Balanced Mode (DPPP 4.0)**: Compromise between ID and Quant

### Cycle Time Calculation

```r
# Instrument-dependent
if (instrument_type == "astral") {
  # Parallel acquisition: MS2 during MS1
  cycle_time <- max(MS1_time, n_windows * MS2_time)
} else {
  # Sequential acquisition: MS1 then MS2
  cycle_time <- MS1_time + (n_windows * MS2_time)
}
```

### Instrument Configurations

**Thermo Astral**:
- Max scan rate: 50 Hz (optimized: 100 Hz)
- MS1 time: 0.1 sec
- MS2 time: 0.015 sec/window
- Acquisition: Parallel
- Minimum window width: 2 Da (narrow-DIA)

**Thermo Orbitrap Exploris**:
- Max scan rate: 25 Hz (optimized: 40 Hz)
- MS1 time: 0.05 sec
- MS2 time: 0.02 sec/window
- Acquisition: Sequential

**Traditional Orbitrap**:
- Max scan rate: 8 Hz (optimized: 12 Hz)
- MS1 time: 0.1 sec
- MS2 time: 0.08 sec/window
- Acquisition: Sequential

---

## Module Integration Points

### Stage 1 → Stage 2

**Output from Stage 1**:
```r
ValidatedData <- structure(
  list(
    data = tibble(RT.Start, Precursor.Mz, FWHM, ...),
    metadata = list(n_precursors, rt_range, mz_range, fwhm_stats),
    validation_status = list(all_passed, quality_score, warnings)
  ),
  class = c("ValidatedData", "list")
)
```

### Stage 2 → Stage 3A

**Output from Stage 2**:
```r
DiagnosisResult <- structure(
  list(
    current_state = list(dppp_distribution, dppp_stats, satisfaction_ratio),
    recommendation = list(optimal_scan_time, expected_window_count),
    instrument_constraints = list(instrument_type, max_scan_rate, is_feasible)
  ),
  class = c("DiagnosisResult", "list")
)
```

### Stage 3A → 3B → 3C → 3D

**Output from Stage 3D**:
```r
WindowGenerationResult <- structure(
  list(
    windows = tibble(
      window_id, rt_segment_id, mz_start, mz_end,
      window_width, n_precursors
    ),
    statistics = list(total_windows, mean_precursors_per_window, cv_precursors),
    coverage_analysis = list(coverage_ratio, uncovered_regions)
  ),
  class = c("WindowGenerationResult", "list")
)
```

### Stage 3D → Stage 4

**Stage 4 Input**: All previous stage outputs

**Stage 4 Output**:
```r
VisualizationResult <- structure(
  list(
    plots = list(dppp_density, rt_window_size, ..., dppp_achievement_heatmap),
    report_files = list(pdf_report, method_file, individual_plots),
    summary_statistics = list(optimization_metrics, performance_metrics)
  ),
  class = c("VisualizationResult", "list")
)
```

---

## Existing Code to Leverage

### ✅ Already Implemented (Reuse)

1. **RT Binning** (`R/rt_segmentation.R`):
   - `segment_rt_by_time_unit()` - Time-based binning
   - `segment_rt_by_time_breaks()` - Explicit breakpoints
   - **Use in Phase 3B**: Create wrapper function

2. **Variable Window Generation** (`R/window_generator.R`):
   - `generate_windows_from_boundaries()` - Density-based windows
   - Largest Remainder Method for exact window count
   - **Use in Phase 3D**: Integrate as Variable mode

3. **DynamicDIA Smoothing** (`R/dynamicDIA.R` + `R/mz_boundaries.R`):
   - Savitzky-Golay, Moving Average, Gaussian smoothing
   - `compute_smooth_mz_boundaries()` - RT-dependent m/z ranges
   - **Use in Phase 3C**: Integrate as Smoothing strategy

4. **Data Loading** (`R/data_loader.R`):
   - `load_diann_data()` - Parquet/TSV/CSV loading
   - **Use in Phase 1**: Integrate into validation pipeline

5. **DPPP Calculator** (`R/dppp_calculator.R`):
   - Basic DPPP calculation
   - **Use in Phase 2**: Enhance with satisfaction ratio

6. **Visualization** (`R/visualizer.R`):
   - Basic plotting functions
   - **Use in Phase 4**: Expand with 8 required plots

### 🔴 Need to Implement (New)

1. **Phase 1**: Complete data validation framework
2. **Phase 2**: DPPP diagnosis and scan_time recommendation
3. **Phase 3A**: Window count determination with feasibility checks
4. **Phase 3B**: Wrapper integration for RT binning
5. **Phase 3C**: 4-strategy m/z range optimization framework
6. **Phase 3D**: Fixed and Overlapped window modes
7. **Phase 4**: Comprehensive visualization and reporting

---

## Testing Strategy

### Unit Testing

Each phase has dedicated test files:
```r
tests/
├── test_stage1.R    # Data validation tests
├── test_stage2.R    # DPPP diagnosis tests
├── test_stage3a.R   # Window count tests
├── test_stage3b.R   # RT binning integration tests
├── test_stage3c.R   # m/z range optimization tests
├── test_stage3d.R   # Window generation tests
└── test_stage4.R    # Visualization tests
```

### Mock Data

Each phase provides mock output for downstream development:
```r
# Example: Phase 2 mock
source("tests/mocks/mock_stage2_output.R")
mock_diagnosis <- create_mock_stage2_output(
  n_precursors = 1000,
  target_dppp = 7.0,
  satisfaction_ratio = 0.85
)
```

### Integration Testing

End-to-end testing with real data:
```r
# Complete pipeline test
source("test_real_data.R")

# Or step-by-step
data <- load_diann_data("report.parquet")
validated <- validate_data(data)
diagnosis <- diagnose_dppp_status(validated, ...)
windows <- generate_isolation_windows(diagnosis, ...)
viz <- generate_visualizations(windows, ...)
```

---

## Documentation Quick Reference

- **Development Guide**: `DEVELOPMENT.md` - Overall project structure and progress
- **Product Requirements**: `docs/PRD.md` - Functional requirements (Korean)
- **System Architecture**: `docs/ARCHITECTURE.md` - Technical design details
- **API Specification**: `docs/API_SPECIFICATION.md` - Module I/O contracts

**Phase-Specific Guides**:
- **Phase 1**: `docs/phases/PHASE1_DATA_VALIDATION.md`
- **Phase 2**: `docs/phases/PHASE2_DPPP_DIAGNOSIS.md`
- **Phase 3A**: `docs/phases/PHASE3A_WINDOW_COUNT.md`
- **Phase 3B**: `docs/phases/PHASE3B_RT_BINNING.md`
- **Phase 3C**: `docs/phases/PHASE3C_MZ_RANGE.md`
- **Phase 3D**: `docs/phases/PHASE3D_WINDOW_GENERATION.md`
- **Phase 4**: `docs/phases/PHASE4_VISUALIZATION.md`

---

## Development Best Practices

### Function Naming Convention

- `load_*`: Data loading
- `validate_*`: Data validation
- `calculate_*`: Mathematical computations
- `analyze_*`: Analysis functions
- `diagnose_*`: Diagnostic functions
- `segment_*`: RT segmentation
- `optimize_*`: Optimization algorithms
- `generate_*`: Window/plot generation
- `compare_*`: Comparison functions
- `export_*`: File export

### Error Handling

- Early validation with informative messages
- Graceful fallbacks for optional features
- Comprehensive logging
- Clear warning messages for constraint violations

### Code Style

- Use tidyverse conventions (dplyr, ggplot2)
- Functional programming style
- Clear input/output contracts
- roxygen2 documentation for all exported functions

---

## Getting Help

### For Users

- Check `README.md` for usage instructions
- See `docs/PRD.md` for feature descriptions
- Review example configurations in `examples/`

### For Developers

- Read `DEVELOPMENT.md` for project structure
- Follow phase-specific guides in `docs/phases/`
- Use mock data from `tests/mocks/` for independent development
- Refer to `docs/API_SPECIFICATION.md` for module interfaces

### For Claude Code

When working on this project:
1. **Start with the phase guide**: Read the relevant `docs/phases/PHASE[N]_*.md` file
2. **Use mock data**: Load mock inputs from `tests/mocks/` for development
3. **Follow API specs**: Ensure output matches `docs/API_SPECIFICATION.md`
4. **Write tests**: Create unit tests in `tests/test_stage[N].R`
5. **Update docs**: Keep DEVELOPMENT.md progress tracking current

---

**Version**: 2.0 (4-Stage Architecture)
**Last Updated**: 2025-10-13
**Status**: Active Development
