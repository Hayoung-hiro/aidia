# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DIA Window Optimizer is an R-based tool for optimizing Data-Independent Acquisition (DIA) isolation windows for mass spectrometry proteomics. It implements a **4-stage pipeline** using DIA-NN output to:
1. Diagnose current DPPP (Data Points Per Peak) status
2. Recommend optimal scan timing parameters
3. Generate optimized RT-dependent isolation windows

**Target Instruments**: Primarily **Thermo Fisher Orbitrap family** (Astral, Exploris, traditional Orbitrap), with support for TimsTOF, SCIEX, and Waters instruments.

**Key Concept - DPPP**: Data Points Per Peak = (1.7 × FWHM_seconds) / cycle_time_seconds
- Target DPPP 7.0 = Quantification mode (default)
- Target DPPP 1.5 = Identification mode (maximum coverage)

**Instrument Timing Models**:
- **Parallel** (Astral, TimsTOF): cycle_time = max(MS1_time, n_windows × MS2_time)
- **Sequential** (Orbitrap): cycle_time = MS1_time + (n_windows × MS2_time)

---

## Architecture Overview

### 4-Stage Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                    4-Stage Pipeline                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  [Stage 1] Data Validation                                  │
│      Input: DIA-NN output (+ Raw files, optional)          │
│      Output: Validated dataset + metadata                   │
│      ↓                                                       │
│  [Stage 2] DPPP Diagnosis                                   │
│      Input: Validated data + user scan_time                │
│      Output: Current status + recommended scan_time         │
│      ↓                                                       │
│  [Stage 3] Window Optimization                              │
│      ├─ [3A] Window Count Determination                    │
│      ├─ [3B] RT Binning (time-based)                       │
│      ├─ [3C] m/z Range Optimization                        │
│      └─ [3D] Window Generation                             │
│      Output: Optimized isolation windows                    │
│      ↓                                                       │
│  [Stage 4] Visualization & Reporting                        │
│      Input: All previous outputs                            │
│      Output: Plots + PDF report + method file              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
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

### Stage 2: DPPP Diagnosis
- **Current DPPP Distribution**: Calculate DPPP from existing FWHM data
- **Satisfaction Ratio**: % of precursors meeting target DPPP ± tolerance
- **Scan Time Recommendation**: Optimize scan_time for next experiment
- **Trade-off Analysis**: scan_time vs window_count vs satisfaction ratio

### Stage 3: Window Optimization

#### 3A: Window Count Determination
- Calculate window count from scan_time and instrument scan rate
- Verify against instrument constraints (scan rate, cycle time)
- Optional raw metadata integration for injection time adjustment

#### 3B: RT Binning (Time-Based)
- **Time-unit binning**: Equal time intervals (e.g., 5-minute bins)
- **Explicit breakpoints**: User-defined RT boundaries
- **Purpose**: Temporal consistency, NOT precursor count equalization

#### 3C: m/z Range Optimization
- **4 Strategies**: Quantile, Smoothing (DynamicDIA), Outlier removal, Coverage-based
- **DynamicDIA Integration**: Savitzky-Golay smoothing for RT-dependent m/z ranges
- **Strategy Comparison**: Evaluate performance of different approaches

#### 3D: Window Generation
- **3 Modes**: Fixed (equal width), Variable (density-based), Overlapped
- **Largest Remainder Method**: Exact window count allocation for Variable mode
- **Uniform Density**: Each window contains similar precursor counts

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

### Development Phases Status

**Overall Progress**: ~60% (3.5/7 phases complete)

| Phase | File | Status | Notes |
|-------|------|--------|-------|
| Phase 1 | `R/stage1_data_validation.R` | ✅ Complete | Tested with real data |
| Phase 2 | `R/stage2_dppp_diagnosis.R` | ✅ Complete | DPPP calculation verified |
| Phase 3A | `R/stage3_window_optimization/module3a_window_count.R` | ✅ Complete | 3-mode override logic |
| Phase 3B | `R/stage3_window_optimization/module3b_rt_binning.R` | ✅ Complete | Wrapper around rt_segmentation.R |
| Phase 3C | `R/stage3_window_optimization/module3c_mz_range_optimization.R` | ✅ Complete | 4 strategies implemented |
| Phase 3D | `R/stage3_window_optimization/module3d_window_generation.R` | ✅ Complete | 3 modes: Fixed/Variable/Overlapped |
| Phase 4 | `R/stage4_visualization.R` | 🟡 Partial | Basic plots exist in visualizer.R |

See [DEVELOPMENT.md](DEVELOPMENT.md) for detailed phase documentation and progress tracking.

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

### Setup and Installation

```r
# Install required packages
install.packages(c("arrow", "dplyr", "ggplot2", "gridExtra",
                   "jsonlite", "tidyr", "viridis", "scales",
                   "prospectr", "testthat"))

# Verify installation
library(arrow)      # For parquet file support
library(dplyr)      # Data manipulation
library(ggplot2)    # Visualization
```

### Running the Pipeline

```r
# Quick test with synthetic data
source("main.R")
result <- main_optimization(config_file = "config/example_config.json")

# Run specific test workflows
source("test_modules_1_2_3.R")           # Test Phases 1-3
source("test_final_workflow.R")          # End-to-end test
source("test_real_data.R")               # Test with actual DIA-NN data
```

### Testing Individual Modules

```r
# Test Stage 1 (Data Validation)
source("R/stage1_data_validation.R")
source("R/data_loader.R")
data <- load_diann_data("path/to/report.parquet")
validated <- validate_diann_data(data)

# Test Stage 2 (DPPP Diagnosis)
source("R/stage2_dppp_diagnosis.R")
diagnosis <- diagnose_dppp_status(
  validated_data = validated,
  current_cycle_time = 2.0,
  target_dppp = 7.5,
  target_satisfaction = 0.7
)

# Test Stage 3A (Window Count)
source("R/stage3_window_optimization/module3a_window_count.R")
source("config/instruments.R")
instrument <- get_instrument_configs()$astral
window_count <- determine_window_count(
  diagnosis = diagnosis,
  instrument_config = instrument,
  user_params = list(window_count_mode = "optimize")
)

# Test using mock data (when upstream stages not ready)
source("tests/mocks/mock_stage1_output.R")
mock_data <- create_mock_stage1_output(n_precursors = 1000)
```

### Interactive Debugging

```r
# Enable debug mode for a specific function
debug(diagnose_dppp_status)
result <- diagnose_dppp_status(...)
undebug(diagnose_dppp_status)

# Step through code with browser()
# Add browser() at any line in your R code, then:
source("R/your_module.R")
result <- your_function(...)  # Will pause at browser() call

# Inspect objects in RStudio
View(validated_data$data)           # Tabular view
str(diagnosis)                      # Structure
summary(diagnosis$current_status)   # Summary stats
```

### Viewing Results

```r
# View optimization results
source("view_results.R")

# Generate and view plots
source("R/visualizer.R")
plot_dppp_density(diagnosis$dppp_distribution)
plot_rt_window_size(windows)

# Examine output files
list.files("output/", pattern = "*.csv")
list.files("output/plots/", pattern = "*.png")
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

Instrument presets are defined in [config/instruments.R](config/instruments.R):

```r
# Access instrument configs
source("config/instruments.R")
configs <- get_instrument_configs()

# Available presets
configs$astral              # Thermo Astral (parallel acquisition)
configs$orbitrap            # Traditional Orbitrap (sequential)
configs$orbitrap_exploris   # Orbitrap Exploris (sequential)
configs$timstof             # Bruker timsTOF (parallel)
configs$timstof_pro         # Bruker timsTOF Pro (parallel)
configs$sciex_7600          # SCIEX 7600 ZenoTOF
configs$waters_synapt       # Waters SYNAPT
```

**Key Instrument Parameters**:
- `ms1_time`: MS1 scan time (ms)
- `ms2_time`: MS2 scan time per window (ms)
- `max_scan_rate`: Maximum hardware scan rate (Hz)
- `cycle_calculation`: "parallel" or "sequential" acquisition
- `min_window_width`: Minimum isolation window width (Da)
- `max_windows`: Maximum number of isolation windows

**Example: Thermo Astral**
```r
astral <- get_instrument_configs()$astral
# ms1_time = 5.0 ms
# ms2_time = 3.0 ms
# max_scan_rate = 100 Hz
# cycle_calculation = "parallel"
# min_window_width = 2.0 Da (narrow-DIA capability)
```

---

## Working with R in This Codebase

### R-Specific Patterns Used

**File Sourcing**: This project uses `source()` to load modules rather than packages
```r
# Always source dependencies in order
source("R/data_loader.R")          # Low-level utilities first
source("R/dppp_calculator.R")
source("R/stage1_data_validation.R")  # Higher-level modules next
```

**S3 Object System**: Custom classes for type safety
```r
# Creating typed objects
validated_data <- structure(
  list(data = df, metadata = meta),
  class = c("ValidatedData", "list")
)

# Type checking
stopifnot(inherits(validated_data, "ValidatedData"))
```

**Tidyverse-style Programming**
```r
# Prefer pipes for clarity
data %>%
  filter(RT.Start >= rt_min) %>%
  mutate(dppp = calculate_dppp(FWHM, cycle_time)) %>%
  group_by(rt_segment) %>%
  summarize(mean_dppp = mean(dppp))
```

### Common Pitfalls

**1. Time Unit Confusion**
- DIA-NN reports RT in **minutes**
- FWHM in **minutes**
- Cycle time calculations use **seconds**
- Instrument configs define times in **milliseconds**

```r
# Always convert explicitly
cycle_time_sec <- cycle_time_ms / 1000
fwhm_sec <- fwhm_min * 60
```

**2. DPPP Direction is Counter-Intuitive**
- Higher DPPP requires **shorter** cycle time (not longer)
- DPPP = (1.7 × FWHM) / cycle_time
- Smaller cycle_time → Higher DPPP → Better quality

**3. Satisfaction Ratio Logic**
- Target DPPP is a **minimum threshold** (no upper limit)
- `dppp >= target` = satisfied (higher is always better)
- 70% satisfaction → use **30th percentile** FWHM (not 70th)
  - Shortest FWHMs are hardest to satisfy
  - `quantile(fwhm, 1 - 0.7)` gives critical FWHM

**4. Scan Rate Calculation**
```r
# WRONG: scan_rate = 1 / cycle_time  (this is cycle frequency)
# RIGHT: scan_rate = n_windows / cycle_time  (MS2 scans per second)
```

### Data Loading Best Practices

```r
# Always check file format and load appropriately
if (grepl("\\.parquet$", file_path)) {
  data <- arrow::read_parquet(file_path)
} else if (grepl("\\.tsv$", file_path)) {
  data <- read.delim(file_path)
} else {
  data <- read.csv(file_path)
}

# Verify required columns exist
required <- c("RT.Start", "Precursor.Mz", "FWHM")
missing <- setdiff(required, colnames(data))
if (length(missing) > 0) {
  stop(sprintf("Missing columns: %s", paste(missing, collapse = ", ")))
}
```

### Output Structure Conventions

All stage functions return a consistent structure:
```r
list(
  # Primary output
  data = main_result,

  # Metadata about the computation
  metadata = list(
    n_items = nrow(main_result),
    computation_time = elapsed,
    parameters_used = params
  ),

  # Status information
  status = list(
    success = TRUE,
    warnings = warning_messages,
    errors = character(0)
  )
)
```

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

## Key Modules and Their Purposes

### Core Pipeline Modules (Completed)

**Stage 1: Data Validation** ([R/stage1_data_validation.R](R/stage1_data_validation.R))
- Load DIA-NN output (Parquet/TSV/CSV)
- Validate required columns and data quality
- Optionally integrate raw file metadata

**Stage 2: DPPP Diagnosis** ([R/stage2_dppp_diagnosis.R](R/stage2_dppp_diagnosis.R))
- Calculate current DPPP distribution
- Compute satisfaction ratio against target
- Recommend optimal cycle time for next experiment

**Stage 3: Window Optimization**
- **3A**: [module3a_window_count.R](R/stage3_window_optimization/module3a_window_count.R) - Determine window count from cycle time
- **3B**: [module3b_rt_binning.R](R/stage3_window_optimization/module3b_rt_binning.R) - Wrapper around rt_segmentation.R for time-based binning
- **3C**: [module3c_mz_range_optimization.R](R/stage3_window_optimization/module3c_mz_range_optimization.R) - 4 strategies (Quantile, Smoothing, Outlier removal, Coverage)
- **3D**: [module3d_window_generation.R](R/stage3_window_optimization/module3d_window_generation.R) - Generate windows (Fixed/Variable/Overlapped)

**Stage 4: Visualization** ([R/visualizer.R](R/visualizer.R) - partial)
- Generate diagnostic plots
- Create PDF reports
- Export method files for instrument programming

### Reusable Utility Modules

**[R/rt_segmentation.R](R/rt_segmentation.R)**: Time-based RT binning algorithms
**[R/window_generator.R](R/window_generator.R)**: Density-based variable window generation
**[R/dynamicDIA.R](R/dynamicDIA.R)**: DynamicDIA smoothing algorithms (Savitzky-Golay, etc.)
**[R/data_loader.R](R/data_loader.R)**: Multi-format data loading (Parquet/TSV/CSV)
**[R/dppp_calculator.R](R/dppp_calculator.R)**: DPPP calculation engine
**[R/method_writer.R](R/method_writer.R)**: Export method files in vendor formats
**[R/utils.R](R/utils.R)**: General utility functions

---

## Testing and Validation

### Available Test Scripts

**Integration Tests** (root directory):
```r
source("test_modules_1_2_3.R")        # Test complete Stages 1-3 pipeline
source("test_final_workflow.R")       # End-to-end workflow test
source("test_real_data.R")            # Validation with actual DIA-NN data
source("test_redesigned_modules.R")   # Test redesigned module architecture
source("test_window_generation.R")    # Window generation algorithms
```

**Analysis Scripts**:
```r
source("analyze_fwhm_simple.R")       # Quick FWHM analysis
source("analyze_fwhm_detailed.R")     # Detailed FWHM distribution
source("dppp_threshold_analysis.R")   # DPPP threshold optimization
source("compare_instruments.R")       # Compare instrument configurations
```

### Mock Data for Independent Development

Mock generators are in `tests/mocks/` (if the directory exists):
```r
# Example pattern for creating mocks
create_mock_stage1_output <- function(n_precursors = 1000) {
  structure(
    list(
      data = tibble(
        RT.Start = runif(n_precursors, 10, 110),
        Precursor.Mz = runif(n_precursors, 400, 900),
        FWHM = rnorm(n_precursors, 0.3, 0.1)
      ),
      metadata = list(
        n_precursors = n_precursors,
        rt_range = c(10, 110),
        mz_range = c(400, 900)
      )
    ),
    class = c("ValidatedData", "list")
  )
}
```

### Verification with Real Data

The project includes test data fixtures in `tests/fixtures/` (if available):
- Example DIA-NN parquet files
- Expected output files for regression testing
- Instrument-specific test cases (Astral, Orbitrap, etc.)

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

### Claude Code Workflow

When working on this project:

1. **Understand the phase**: Read relevant `docs/phases/PHASE[N]_*.md` for detailed specifications
2. **Check instrument config**: Verify instrument parameters in `config/instruments.R`
3. **Use existing modules**: Leverage completed stages and utility functions
4. **Mind the units**: RT/FWHM (minutes), cycle_time (seconds), instrument times (milliseconds)
5. **Follow API contracts**: Ensure output structure matches `docs/API_SPECIFICATION.md`
6. **Test incrementally**: Use test scripts to validate changes
7. **Update documentation**: Keep [DEVELOPMENT.md](DEVELOPMENT.md) current with progress

### Critical Implementation Notes

**DPPP Counter-Intuitive Behavior**:
- Higher target DPPP → Need SHORTER cycle time
- 70% satisfaction → Use 30th percentile (1 - 0.7) of FWHM distribution
- No upper limit on DPPP (≥ target = satisfied)

**Window Count Modes** (Phase 3A):
- `"optimize"`: Auto-calculate from cycle_time and instrument constraints
- `NULL`: Required user-specified window_count
- User-specified: Direct override with feasibility check

**Cycle Time Calculation**:
- Parallel (Astral/TimsTOF): MS1 and MS2 overlap
- Sequential (Orbitrap): MS1 then MS2 sequentially

---

**Version**: 2.0 (4-Stage Architecture)
**Last Updated**: 2025-10-18
**Status**: Core pipeline complete (~60%), visualization in progress
