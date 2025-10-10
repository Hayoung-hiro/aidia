# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DIA Window Optimizer is an R-based tool for optimizing Data-Independent Acquisition (DIA) isolation windows for mass spectrometry. It implements **sample-specific iterative variable isolation window optimization** using existing DIA-NN results to calculate DPPP distribution and statistics, then generates RT-dependent dynamic window methods based on precursor density through progressive refinement iterations (Raw_input → init_01 → init_02 → ...).

The tool uses the DPPP (Data Points Per Peak) methodology combined with dynamicDIA algorithms for RT-segment-based precursor distribution equalization, specifically designed for the Thermo Fisher Orbitrap family of mass spectrometers, including:

- **Thermo Astral**: Ultra-high speed Orbitrap with parallel acquisition and narrow-DIA capability
- **Thermo Orbitrap Exploris**: Modern Orbitrap series with FAIMS support
- **Traditional Thermo Orbitrap**: High-resolution sequential acquisition systems

While the tool supports other instrument types (TimsTOF, SCIEX, Waters), it is optimized for Orbitrap-specific acquisition patterns and timing constraints.

## Key Features

### Core Capabilities
- **Module 1 - Enhanced DPPP Analysis**: Current distribution analysis with satisfaction ratio calculation and interactive scan_time optimization
- **Module 2 - Time-Based RT Binning**: RT segmentation using time intervals (e.g., 5-minute bins) or explicit breakpoints for consistent temporal resolution
- **Module 3 - DynamicDIA-Driven Density Optimization**: Smoothing-based m/z boundary determination followed by uniform density window allocation
- **Module 4 - User-Parameterized Window Generation**: Flexible window generation with user-specified constraints (n_windows, min/max_width, dynamic mode)
  - Fixed, variable (density-based), and overlapped window types
  - Dynamic vs static m/z range determination

### Iterative Optimization Framework (NEW)
- **Progressive Refinement**: Automatic iteration from Raw_input through init_01, init_02, ... until convergence
- **Smart Parameter Adjustment**: Algorithm-driven suggestions based on DPPP satisfaction, coverage, and balance metrics
- **Version Management**: Complete tracking of iteration history with performance comparison
- **Convergence Detection**: Automatic stopping when DPPP satisfaction > 90%, coverage > 95%, or Δmetrics < 2%
- **Best Iteration Selection**: Automated selection based on weighted composite scoring

## Common Development Commands

### Running the Tool

```bash
# Traditional single optimization
Rscript main.R config.json
Rscript main.R data.parquet astral 1.25

# Interactive R session with iterative workflow
R
source("main.R")

# Single-shot optimization (traditional)
result <- quick_optimize("data.parquet", "astral", 1.25)

# Iterative optimization workflow (new)
source("R/iterative_optimizer.R")
workspace <- initialize_iteration_workspace("my_project", initial_config)
init_01 <- run_iteration("init_01", workspace$initial_config)
init_02 <- run_iteration("init_02", improved_config, previous_results = init_01)
best <- export_best_iteration(list(init_01, init_02))
```

### Required R Packages

Install dependencies before development:
```r
install.packages(c("arrow", "dplyr", "ggplot2", "gridExtra",
                   "jsonlite", "tidyr", "viridis", "scales",
                   "prospectr"))  # prospectr for professional smoothing
```

### Testing

Run test files from the tests/ directory:
```r
source("tests/archive/test_optimization.R")
source("user_verification_script.R")  # User validation tests
```

## Code Architecture

### Enhanced Modular R Structure

The codebase follows a modular architecture with clear separation of concerns:

**Core Module Loading Chain** (main.R):
```r
source("R/data_loader.R")              # Data ingestion and validation
source("R/dppp_calculator.R")          # DPPP calculation engine
source("R/dppp_analyzer_enhanced.R")   # Enhanced DPPP analysis (NEW)
source("R/rt_segmentation.R")          # RT segmentation strategies (NEW)
source("R/optimizer.R")                # Window optimization algorithms
source("R/window_generator.R")         # Interactive window generation (NEW)
source("R/visualizer.R")               # Plot generation and reporting
source("R/iterative_optimizer.R")      # Iterative refinement engine (NEW)
source("R/version_manager.R")          # Version control and tracking (NEW)
source("R/method_writer.R")            # Method file export
source("R/utils.R")                    # Utility functions
source("R/fwhm_analyzer.R")            # FWHM analysis
source("R/dynamicDIA.R")               # DynamicDIA smoothing algorithms
source("config/instruments.R")         # Instrument configurations
```

### Data Flow Architecture

**Traditional Workflow:**
1. **Data Loading**: Parquet/TSV/CSV with automatic column detection
2. **Instrument Configuration**: Presets for different mass spectrometers
3. **DPPP Calculation**: Core formula implementation
4. **Optimization Engine**: RT segment-based window optimization
5. **Analysis & Export**: Method files and comprehensive reporting

**Enhanced Iterative Workflow (NEW):**
1. **Workspace Initialization**: Create iteration directory structure
2. **Iteration Cycle**:
   - Run optimization with current parameters (init_01)
   - Analyze performance metrics (DPPP satisfaction, coverage, balance)
   - Generate smart parameter suggestions
   - Run next iteration with improvements (init_02)
   - Compare iterations and detect convergence
3. **Best Iteration Selection**: Automated selection based on composite scoring
4. **Final Report Generation**: Cross-iteration comparison with comprehensive visualizations

### Iterative Optimization Structure (NEW)

```
project_workspace/
├── Raw_input/
│   ├── diann_output.parquet          # Original DIA-NN data
│   ├── rawfiles/                     # Original raw MS files (optional)
│   └── initial_config.json           # User's initial configuration
├── iterations/
│   ├── init_01/
│   │   ├── analysis_results.rds      # Complete R data structure
│   │   ├── optimized_method.csv      # Window method for instrument
│   │   ├── dppp_report.pdf          # DPPP analysis visualization
│   │   ├── window_layout.pdf        # Window coverage visualization
│   │   ├── iteration_config.json    # Configuration used
│   │   └── performance_metrics.json # Quantitative metrics
│   ├── init_02/
│   │   ├── (same structure)
│   │   └── improvements.json        # Changes from init_01
│   ├── init_03/
│   │   └── ...
│   └── comparison_report.pdf        # Cross-iteration comparison
└── final_output/
    ├── best_method.csv               # Selected optimal method
    └── comprehensive_report.pdf      # Final summary with iteration history
```

### Orbitrap Family Support

The tool is specifically optimized for Thermo Fisher's Orbitrap family with different acquisition patterns:

**Thermo Astral** (`astral`):
- **Parallel Acquisition**: MS2 scans during MS1 acquisition
- **Ultra-High Speed**: Up to 100 Hz scan rate (optimal: 50 Hz)
- **Narrow-DIA Optimized**: Minimum 2 Da window width for narrow-DIA capability
- **Cycle Time**: `max(MS1_time, n_windows × MS2_time)` - limited by MS2 duty cycle
- **Typical DPPP Targets**: 1.0-1.5 for optimal sampling

**Thermo Orbitrap Exploris** (`orbitrap_exploris`):
- **Sequential Acquisition**: Traditional MS1 → MS2 pattern
- **Modern Speed**: Up to 40 Hz scan rate (optimal: 25 Hz)
- **FAIMS Compatible**: Enhanced selectivity with FAIMS integration
- **Cycle Time**: `MS1_time + (n_windows × MS2_time)` - traditional sequential
- **Typical DPPP Targets**: 1.2-2.0 for balanced performance

**Traditional Orbitrap** (`orbitrap`):
- **High Resolution**: Emphasis on mass accuracy over speed
- **Sequential Acquisition**: Classic MS1 → MS2 cycle
- **Lower Speed**: Up to 12 Hz scan rate (optimal: 8 Hz)
- **Cycle Time**: `MS1_time + (n_windows × MS2_time)` - traditional sequential
- **Typical DPPP Targets**: 1.5-3.0 to accommodate longer cycle times

### Key Algorithmic Components

**Enhanced DPPP Analysis (NEW)**:
- **Current Distribution Analysis**: Calculate DPPP from FWHM data with configurable scan_time (default: 2.0 sec)
- **Satisfaction Ratio**: Percentage of precursors meeting target DPPP threshold (within tolerance)
- **Interactive Optimization**: User specifies target DPPP and satisfaction ratio → system recommends optimal scan_time
- **Trade-off Visualization**: scan_time vs window count vs DPPP achievement curves

**Module 2: Time-Based RT Binning**:
- **Time-Unit Binning**: Equal time intervals using `rt_bin_width_min` parameter (e.g., 5-minute bins: 10-15, 15-20, 20-25 min)
- **Explicit Breakpoints**: User-defined RT boundaries via `rt_breaks_min` vector (e.g., c(10, 20, 35, 50) for custom intervals)
- **Temporal Consistency**: Ensures consistent time resolution across gradient, independent of precursor density
- **Purpose**: Groups precursors by retention time for RT-dependent window optimization, NOT for equalizing precursor counts

**DPPP-Based Optimization**: Target DPPP varies by Orbitrap type to balance sampling frequency with instrument capabilities:
- **Astral**: 1.0-1.5 (leverages ultra-high speed parallel acquisition)
- **Exploris**: 1.2-2.0 (balances modern speed with resolution)
- **Traditional**: 1.5-3.0 (accommodates slower sequential cycles)
- Formula: `DPPP = (1.7 × FWHM_seconds) / cycle_time_seconds`

**Spectronaut Standard**: The peak width factor of 1.7 follows Spectronaut's definition where chromatographic peak width = 1.7 × FWHM. This provides more conservative DPPP calculations compared to using FWHM directly.

**Orbitrap-Specific Cycle Time Calculations**:
- **Astral Parallel**: `cycle_time = max(MS1_time, n_windows × MS2_time)`
- **Sequential Orbitraps**: `cycle_time = MS1_time + (n_windows × MS2_time)`
- Astral benefits from parallel MS1/MS2 acquisition, allowing higher window counts without proportional cycle time increases

**Module 3: DynamicDIA-Driven Density Optimization** (3-Step Workflow):

**Step 1: m/z Boundary Determination (Dynamic Mode)**
- **DynamicDIA Smoothing**: Apply Savitzky-Golay, Gaussian, or Moving Average smoothing to determine RT-dependent m/z ranges
- **Smooth Transitions**: Ensures gradient continuity and removes outlier precursors
- **Static Fallback**: Option to use raw data min/max boundaries instead (`dynamic = FALSE`)

**Step 2: Precursor Distribution Analysis**
- **Within-Boundary Analysis**: Analyze precursor density only within smoothed (or raw) m/z boundaries
- **Density Profile**: Generate 1 Da resolution m/z histogram for precise density characterization
- **High/Low Density Identification**: Classify regions by local precursor concentration

**Step 3: Window Allocation for Uniform Density**
- **Goal**: Each window contains similar number of precursors (uniform density)
- **High Density → More Windows**: Narrow windows in crowded regions for better selectivity
- **Low Density → Fewer Windows**: Wide windows in sparse regions for efficiency
- **Constraints**: Respect user-specified `min_width_da` and `max_width_da` limits

**DynamicDIA Integration**:
- **Savitzky-Golay Smoothing**: Polynomial fitting for smooth RT transitions (via prospectr package)
- **Alternative Smoothing Methods**: Moving average and Gaussian smoothing options
- **Optimal Window Placement**: `compute_precursor_locations()` methodology from dynamicDIA
- **RT-Segment Equalization**: Divides RT space into configurable segments and equalizes precursor distribution
- **Smoothing Comparison**: Visualization of raw vs smoothed boundaries with method comparison

**Sample-Specific DPPP Targeting**:
- Analyzes sample-specific precursor distribution patterns
- Calculates optimal DPPP targets for each RT segment
- Adapts to instrument-specific timing constraints
- Maintains consistent data quality across variable window sizes

**Iterative Refinement Algorithm (NEW)**:
- **Smart Parameter Adjustment**:
  - DPPP satisfaction < target → adjust scan_time proportionally
  - High RT bin variance → adjust rt_bin_width_min for better temporal consistency
  - Coverage gaps > 5% → increase window overlap by 20%
  - Low precursors/window < 50 → adjust target DPPP or increase min_width_da
- **Convergence Detection**:
  - Auto-stop when DPPP satisfaction > 90% AND coverage > 95%
  - OR when Δmetrics < 2% between consecutive iterations
- **Performance Metrics**:
  - DPPP satisfaction ratio (% precursors meeting target)
  - Precursor coverage (% precursors within windows)
  - Window count efficiency (precursors per window)
  - Segment balance score (coefficient of variation across segments)
  - Weighted composite score for iteration ranking

### Configuration System

**JSON-based Configuration** (`examples/example_config.json`):
- Supports both file-based and programmatic configuration
- Override parameters via function arguments
- Instrument presets with timing constraints
- Output format flexibility (CSV, TSV, method files)
- Iterative workflow parameters (NEW)

**Runtime Configuration Priority**:
1. Command line parameters override config file
2. Config file overrides defaults
3. Instrument presets provide timing baselines
4. Previous iteration results inform next iteration suggestions (NEW)

**Enhanced Configuration Options (NEW)**:
```json
{
  "proteome_file": "report.parquet",
  "instrument_preset": "astral",
  "target_dppp": 1.25,

  // Module 1: Enhanced DPPP analysis
  "current_scan_time": 2.0,
  "target_dppp_satisfaction": 0.85,

  // Module 2: RT binning (time-based)
  "rt_bin_width_min": 5,              // 5-minute bins (default)
  "rt_breaks_min": null,              // OR explicit: [10, 20, 35, 50, 70]

  // Module 3: DynamicDIA-driven optimization
  "dynamic": true,                    // Use smoothed boundaries (default)
  "smoothing_method": "savgol",       // "savgol", "movav", or "gaussian"
  "smoothing_window_size": 7,
  "polynomial_order": 3,
  "mz_bin_width_da": 1,               // Density analysis resolution (Da)

  // Module 4: Window generation
  "n_windows": 100,                   // Total window count (default)
  "min_width_da": 2,                  // Minimum window width (default: 2 Da)
  "max_width_da": 80,                 // Maximum window width (default: 80 Da)
  "window_type": "variable",          // "fixed", "variable", or "overlapped"
  "overlap_percentage": 0,            // For overlapped type only

  // Iterative optimization
  "enable_iterative_mode": true,
  "max_iterations": 10,
  "convergence_tolerance": 0.02,
  "auto_suggest_improvements": true
}
```

### Enhanced Features

**Raw Metadata Integration**: Optional integration with raw MS files for enhanced FWHM analysis and actual cycle time validation (when `rawfile/` directory present and `enable_raw_metadata: true`)

**Multi-segment FWHM Analysis**: `fwhm_analyzer.R` provides comprehensive FWHM analysis across RT and m/z dimensions for informed optimization decisions

**Validation Framework**: Built-in scan rate validation ensures instrument compatibility and warns when optimization exceeds hardware capabilities

**Iterative Version Control (NEW)**: Complete tracking of optimization history with automated comparison, delta metrics calculation, and best iteration selection

## File Organization Patterns

### Core R Modules (`R/`)
- Single responsibility: each module handles one aspect of the pipeline
- Functional programming style with clear input/output contracts
- Error handling and validation at module boundaries

**New Modules (Iterative Framework)**:
- `dppp_analyzer_enhanced.R`: Enhanced DPPP analysis with satisfaction ratio and scan_time optimization
- `rt_segmentation.R`: Multiple RT segmentation strategies with comparison framework
- `window_generator.R`: Interactive window generation with fixed/variable/overlapped types
- `iterative_optimizer.R`: Iterative refinement engine with smart parameter adjustment
- `version_manager.R`: Iteration versioning, tracking, and comparison

### Configuration (`config/`)
- `instruments.R`: Instrument timing presets and capabilities
- User configurations from raw metadata integration stored here
- Iteration configurations stored in each iteration directory (NEW)

### Output Structure

**Traditional Output**:
- `optimized_windows.csv`: Method file for instrument programming
- `optimization_report.pdf`: Comprehensive analysis plots
- `*_config.json`: Reproducible configuration snapshots
- `plots/`: Individual analysis plots and summaries

**Iterative Output (NEW)**:
- `iterations/init_XX/`: Complete results for each iteration
- `iterations/comparison_report.pdf`: Cross-iteration comparison
- `final_output/best_method.csv`: Selected optimal method
- `final_output/comprehensive_report.pdf`: Iteration history and final summary

### Development Patterns

**Function Naming Convention**:
- `load_*`: Data loading functions
- `calculate_*`: Mathematical computations
- `analyze_*`: Analysis functions (NEW for enhanced modules)
- `segment_*`: RT segmentation functions (NEW)
- `generate_*`: Window generation functions (NEW)
- `optimize_*`: Optimization algorithms
- `run_*`: Iteration execution functions (NEW)
- `compare_*`: Comparison and evaluation functions (NEW)
- `suggest_*`: Parameter suggestion functions (NEW)
- `export_*`: Output generation
- `validate_*`: Data validation
- `visualize_*`: Visualization functions

**Error Handling Strategy**: Early validation with informative error messages, graceful fallbacks for optional features, and comprehensive logging throughout the pipeline.

## Testing Strategy

**Validation Scripts**:
- `user_verification_script.R`: End-to-end validation with known datasets
- `tests/archive/`: Historical test cases for regression testing
- Built-in data validation throughout the pipeline
- Iteration convergence testing (NEW)

**Performance Testing**: Large dataset handling (~1M+ precursors) with memory-efficient parquet processing and progress reporting for long-running optimizations.

## Enhanced Visualization and Analysis

The tool provides comprehensive visualization capabilities through the `visualizer.R` module with support for both single-plot analysis and multi-panel reports:

**Pre-Optimization Analysis Plots**:
- **Precursor Distribution**: Histogram and density plots showing m/z distribution patterns
- **RT Segment Distribution**: Analysis of precursor distribution across retention time segments with strategy comparison (NEW)
- **Current DPPP Distribution**: Visualization of existing DPPP values before optimization with satisfaction ratio (NEW)
- **2D Density Heatmaps**: RT × m/z precursor density visualization for identifying high-density regions

**Enhanced DPPP Analysis Plots (NEW)**:
- **DPPP Distribution Heatmap**: 2D visualization of DPPP values across RT × m/z space
- **DPPP Satisfaction Curve**: Target satisfaction ratio vs scan_time optimization curve
- **Trade-off Analysis**: Multi-dimensional plot showing scan_time vs window count vs DPPP achievement

**RT Binning Visualization (NEW)**:
- **Time-Based Binning**: Visualization of RT bins across retention time gradient
- **Precursor Count Distribution**: Histogram showing precursor counts per RT bin (expected to vary)
- **Temporal Resolution**: RT bin width consistency across gradient

**Post-Optimization Visualization**:
- **Window Layout**: Visual representation of optimized isolation windows across m/z range
- **Coverage Analysis**: Precursor coverage assessment showing window effectiveness with gap highlighting (NEW)
- **Optimization Summary**: Before/after comparison plots with performance metrics
- **RT-Dependent Window Profiles**: Visualization of variable window widths across retention time

**DynamicDIA Smoothing Visualization (NEW)**:
- **Raw vs Smoothed Boundaries**: Comparison of unsmoothed and smoothed RT-dependent m/z ranges
- **Method Comparison**: Side-by-side comparison of savgol, movav, and gaussian smoothing
- **Gradient Continuity**: Visualization of smooth transitions between RT segments

**Iterative Optimization Visualizations (NEW)**:
- **Iteration Comparison**: Multi-panel comparison of DPPP, coverage, window count across iterations
- **Parameter Evolution**: Track how parameters change over iterations (scan_time, window_count, overlap)
- **Improvement Trajectory**: Line plots showing metric improvements with significant improvements annotated
- **Iteration Heatmap Comparison**: Side-by-side DPPP heatmaps highlighting improved regions
- **Final Summary Dashboard**: Comprehensive dashboard with all key visualizations and iteration history

**FWHM Analysis Visualization** (via `fwhm_analyzer.R`):
- **Multi-segment FWHM Analysis**: FWHM distribution across different RT segments
- **RT vs FWHM Correlation Plots**: Identification of RT-dependent FWHM patterns
- **m/z vs FWHM Analysis**: Understanding mass-dependent peak width variations
- **Statistical Summary Plots**: FWHM statistics (mean, median, percentiles) visualization

**Report Generation Features**:
- **Combined PDF Reports**: Multi-panel reports (`optimization_report.pdf`)
- **Individual Plot Export**: Separate PNG/PDF files in `plots/` directory
- **Interactive Plots**: Optional HTML output with zoom and pan capabilities
- **Instrument-Specific Formatting**: Customized plot themes based on instrument type
- **Iteration History Reports**: Cross-iteration comparison with delta metrics (NEW)

**Visualization Libraries**:
- **ggplot2**: Primary plotting framework with customizable themes
- **gridExtra**: Multi-panel plot arrangements and composite reports
- **viridis**: Perceptually uniform color scales for density plots
- **scales**: Professional axis formatting and labeling

## Iterative Optimization Workflow Examples (NEW)

### Basic Iterative Workflow

```r
# === Step 1: Initialize Workspace ===
library(jsonlite)
source("R/iterative_optimizer.R")

workspace <- initialize_iteration_workspace(
  base_dir = "urine_sample_optimization",
  raw_input_config = list(
    diann_file = "report.parquet",
    rawfile_dir = "rawfile/",
    instrument_preset = "astral",
    target_dppp = 1.25,
    rt_bin_width_min = 5,       # 5-minute RT bins
    scan_time = 2.0,
    n_windows = 100,
    min_width_da = 2,
    max_width_da = 80,
    window_type = "variable",
    dynamic = TRUE,
    overlap_percentage = 0,
    target_dppp_satisfaction = 0.85,
    target_coverage = 0.95
  )
)

# === Step 2: Run Initial Iteration ===
init_01 <- run_iteration("init_01", workspace$initial_config)
# Outputs:
# - DPPP satisfaction: 72%
# - Coverage: 89%
# - Windows: 215
# - Segment balance score: 0.28

# === Step 3: Analyze and Get Suggestions ===
performance_01 <- analyze_iteration_performance(
  init_01,
  target_metrics = list(
    dppp_satisfaction = 0.85,
    coverage = 0.95,
    min_precursors_per_window = 50
  )
)

suggestions_02 <- suggest_next_iteration_parameters(init_01, performance_01)
# Auto-suggests:
# - scan_time: 1.82 sec (from 2.0)
# - rt_bin_width_min: 3 (from 5) for finer temporal resolution
# - overlap_percentage: 0.6% (from 0%)
# - reason: "Increase DPPP satisfaction and improve RT bin consistency"

# === Step 4: Run Improved Iteration ===
config_02 <- workspace$initial_config
config_02$scan_time <- suggestions_02$scan_time
config_02$rt_bin_width_min <- suggestions_02$rt_bin_width_min
config_02$overlap_percentage <- suggestions_02$overlap_percentage

init_02 <- run_iteration(
  "init_02",
  config_02,
  previous_results = init_01
)
# Outputs:
# - DPPP satisfaction: 84% (+12%)
# - Coverage: 94% (+5%)
# - Windows: 198 (-17)
# - Segment balance score: 0.15 (improved)

# === Step 5: Continue Until Convergence ===
suggestions_03 <- suggest_next_iteration_parameters(init_02, performance_01)
config_03 <- apply_suggestions(config_02, suggestions_03)
init_03 <- run_iteration("init_03", config_03, previous_results = init_02)

# Check convergence
iterations <- list(init_01, init_02, init_03)
convergence <- detect_convergence(iterations, tolerance = 0.02)

if (convergence$converged) {
  cat("Optimization converged after", length(iterations), "iterations\n")
}

# === Step 6: Compare and Select Best ===
comparison <- compare_iterations(iterations)
print(comparison)
#   Iteration  DPPP_Sat  Coverage  Windows  Balance  Composite_Score
#   init_01    0.72      0.89      215      0.28     0.805
#   init_02    0.84      0.94      198      0.15     0.890
#   init_03    0.88      0.96      205      0.12     0.920  # BEST

best <- export_best_iteration(
  iterations,
  selection_criteria = "weighted_score"  # or "dppp", "coverage", "balanced"
)

# === Step 7: Generate Comprehensive Report ===
create_iteration_report(
  best$results,
  comparison_data = comparison,
  output_file = "final_optimization_report.pdf"
)

cat("\n=== FINAL RESULTS ===\n")
cat(sprintf("Best iteration: %s\n", best$iteration_name))
cat(sprintf("DPPP satisfaction: %.1f%%\n", best$metrics$dppp_satisfaction * 100))
cat(sprintf("Coverage: %.1f%%\n", best$metrics$coverage * 100))
cat(sprintf("Windows: %d\n", best$metrics$n_windows))
cat(sprintf("Method file: %s\n", best$method_file))
```

### Advanced Iterative Configuration

```r
# Custom optimization with density-based segmentation and smoothing
advanced_config <- list(
  proteome_file = "complex_sample.parquet",
  instrument_preset = "astral",
  target_dppp = 1.0,  # Aggressive for high throughput

  # Module 1: Enhanced DPPP analysis
  current_scan_time = 2.0,
  target_dppp_satisfaction = 0.90,  # High target
  dppp_tolerance = 0.1,

  # Module 2: RT binning (time-based)
  rt_bin_width_min = 3,  # 3-minute bins for finer temporal resolution
  # rt_breaks_min = c(10, 20, 35, 50, 70, 110),  # OR explicit breakpoints

  # Module 4: Window generation
  n_windows = 120,
  min_width_da = 2.0,
  max_width_da = 25.0,
  window_type = "variable",
  overlap_percentage = 0,

  # DynamicDIA integration
  smoothing_method = "savgol",
  smoothing_window_size = 7,
  polynomial_order = 3,
  compare_smoothing_methods = TRUE,

  # Iterative optimization settings
  enable_iterative_mode = TRUE,
  max_iterations = 10,
  convergence_tolerance = 0.02,
  auto_suggest_improvements = TRUE,

  # Visualization
  create_plots = TRUE,
  plot_2d_heatmaps = TRUE,
  enable_interactive_plots = TRUE
)

# Run automated iterative optimization
automated_result <- run_automated_iteration_workflow(
  workspace_dir = "automated_optimization",
  initial_config = advanced_config,
  max_iterations = 10,
  stop_on_convergence = TRUE
)

# Access all iteration results
all_iterations <- automated_result$iteration_history
best_iteration <- automated_result$best_iteration
final_report <- automated_result$final_report
```

### Module 2: Time-Based RT Binning Examples

```r
# Time-based RT binning (Module 2)
source("R/rt_segmentation.R")

data <- load_diann_data("report.parquet")

# Option 1: Equal time intervals
rt_bins_5min <- segment_rt_by_time_unit(
  data,
  rt_bin_width_min = 5  # 5-minute bins
)
# Output: 10-15, 15-20, 20-25, ..., 105-110 min

# Option 2: Explicit breakpoints
rt_bins_custom <- segment_rt_by_time_breaks(
  data,
  rt_breaks_min = c(10, 20, 35, 50, 70, 110)
)
# Output: 10-20, 20-35, 35-50, 50-70, 70-110 min
#         (10 min, 15 min, 15 min, 20 min, 40 min intervals)

# Each RT bin will have different precursor counts
# This is CORRECT - we want temporal consistency, not precursor balance
print(rt_bins_5min$stats)
#   RT_bin      RT_start  RT_end  Precursors
#   10-15 min   10.0      15.0    800        # Lower density
#   15-20 min   15.0      20.0    1,500      # Higher density
#   20-25 min   20.0      25.0    1,200      # Medium density
#   ...
```

### DPPP Analysis and Scan Time Optimization

```r
# Enhanced DPPP analysis with scan time optimization
source("R/dppp_analyzer_enhanced.R")

data <- load_diann_data("report.parquet")

# Analyze current DPPP distribution
dppp_analysis <- analyze_dppp_distribution(
  data,
  scan_time = 2.0,  # Current scan time
  target_dppp = 1.25,
  dppp_tolerance = 0.1
)

print(dppp_analysis$summary)
# Current DPPP satisfaction: 72% (target: 85%)
# Mean DPPP: 1.45
# Median DPPP: 1.38
# P25-P75: [1.12, 1.68]

# Calculate optimal scan time for target satisfaction
optimal_scan_time <- calculate_optimal_scan_time(
  data,
  target_dppp = 1.25,
  target_satisfaction_ratio = 0.85,
  scan_time_range = c(1.0, 3.0)
)

print(optimal_scan_time)
# Recommended scan_time: 1.82 sec
# Expected satisfaction: 85.3%
# Expected window count: 198
# Trade-off: -17 windows, +13% satisfaction

# Visualize DPPP analysis
plots <- visualize_dppp_analysis(dppp_analysis, optimal_scan_time)
# - plot_dppp_heatmap: RT × m/z DPPP distribution
# - plot_satisfaction_curve: Satisfaction vs scan_time
# - plot_tradeoff_analysis: Multi-dimensional trade-offs
```

## Sample-Specific Optimization Usage Examples

### Basic Sample-Specific Optimization

```r
# Load sample-specific optimization with density analysis
result <- main_optimization(
  proteome_file = "sample_diann_output.parquet",
  instrument_preset = "astral",
  target_dppp = 1.25,
  fwhm_analysis_enabled = TRUE,
  window_mode = "density_based"
)

# Enable RT-dependent optimization with iterative refinement
result <- quick_optimize(
  proteome_file = "sample_data.parquet",
  instrument = "orbitrap_exploris",
  target_dppp = 1.5,
  rt_bin_width_min = 5,  # 5-minute RT bins
  n_windows = 100,
  dynamic = TRUE,  # Use DynamicDIA smoothed boundaries
  enable_iterative_mode = TRUE
)
```

### Integration with Raw Metadata

```r
# Enable raw metadata integration for enhanced FWHM analysis
# Requires rawfile/ directory with .raw files
enhanced_result <- main_optimization(
  proteome_file = "diann_with_metadata.parquet",
  instrument_preset = "orbitrap_exploris",
  target_dppp = 1.5,

  # Raw metadata integration
  enable_raw_metadata = TRUE,
  use_user_config = TRUE,  # Use config/user_config_final.json if available

  # Enhanced analysis
  fwhm_analysis_enabled = TRUE,
  rt_bin_width_min = 5,  # 5-minute RT bins
  n_windows = 100,
  dynamic = TRUE,  # Use DynamicDIA smoothed boundaries

  create_plots = TRUE
)
```

### Comparative Analysis Across Instruments

```r
# Compare optimization strategies across Orbitrap instruments with iteration
instruments <- c("astral", "orbitrap_exploris", "orbitrap")
dppp_targets <- c(1.25, 1.5, 2.0)
results <- list()

for (i in seq_along(instruments)) {
  workspace <- initialize_iteration_workspace(
    base_dir = paste0("comparison_", instruments[i]),
    raw_input_config = list(
      proteome_file = "benchmark_sample.parquet",
      instrument_preset = instruments[i],
      target_dppp = dppp_targets[i],
      enable_iterative_mode = TRUE,
      max_iterations = 5
    )
  )

  # Run automated iteration workflow
  results[[instruments[i]]] <- run_automated_iteration_workflow(
    workspace_dir = workspace$base_dir,
    initial_config = workspace$initial_config,
    max_iterations = 5
  )
}

# Compare best iterations across instruments
comparison <- data.frame(
  Instrument = instruments,
  Best_Iteration = sapply(results, function(x) x$best_iteration$iteration_name),
  Windows = sapply(results, function(x) x$best_iteration$metrics$n_windows),
  DPPP_Sat = sapply(results, function(x) x$best_iteration$metrics$dppp_satisfaction),
  Coverage = sapply(results, function(x) x$best_iteration$metrics$coverage),
  Iterations = sapply(results, function(x) length(x$iteration_history))
)

print(comparison)
```

### Command-Line Usage Examples

```bash
# Traditional single optimization
Rscript main.R sample_data.parquet astral 1.25

# With configuration file
Rscript main.R config_with_iteration.json

# Iterative optimization (requires R session)
R
source("main.R")
source("R/iterative_optimizer.R")
result <- run_automated_iteration_workflow("my_project", config)
```

### Output Files and Results

Each optimization generates comprehensive results:

**Traditional Output:**
```
# Method files for instrument programming
optimized_windows.csv              # Isolation window method
optimized_windows_astral_config.json  # Configuration snapshot

# Analysis reports
optimization_report.pdf            # Multi-panel visualization
fwhm_analysis_report.pdf          # FWHM analysis plots

# Individual plots directory
plots/
├── precursor_distribution.png
├── rt_segment_analysis.png
├── dppp_distribution_heatmap.png
├── window_layout_visualization.png
├── density_based_boundaries.png
├── rt_dependent_profiles.png
└── optimization_summary.png
```

**Iterative Output (NEW):**
```
project_workspace/
├── Raw_input/
│   └── initial_config.json
├── iterations/
│   ├── init_01/
│   │   ├── analysis_results.rds
│   │   ├── optimized_method.csv
│   │   ├── dppp_report.pdf
│   │   ├── window_layout.pdf
│   │   ├── iteration_config.json
│   │   └── performance_metrics.json
│   ├── init_02/
│   │   ├── (same structure)
│   │   └── improvements.json
│   ├── init_03/
│   └── comparison_report.pdf
└── final_output/
    ├── best_method.csv
    ├── comprehensive_report.pdf
    ├── iteration_history.xlsx
    └── parameter_evolution.png
```

## Performance Notes

- **Large datasets**: Use parquet format for optimal performance
- **Memory usage**: ~1-2 GB RAM for 1M+ precursors
- **Processing time**:
  - Single optimization: ~1-2 minutes for typical proteome datasets
  - Iterative workflow: ~5-15 minutes for 3-5 iterations (depends on convergence)
- **Visualization**: Can take additional time for large datasets
- **Iterative overhead**: Each iteration adds ~2-3 minutes for performance analysis and suggestion generation

## Key Technical Details

**DPPP Formula**: `DPPP = (1.7 × FWHM_seconds) / cycle_time_seconds` (Spectronaut standard)

**Cycle Time Calculation**:
- Astral (parallel): `cycle_time = max(MS1_time, n_windows × MS2_time)`
- Orbitrap (sequential): `cycle_time = MS1_time + (n_windows × MS2_time)`

**Window Calculation Formulas**:
- `scans_per_cycle = floor(cycle_time_sec × instrument_speed_hz)`
- `mz_range_per_cycle = int(scans_per_cycle × isolation_width_th)`

**DynamicDIA Integration**:
- Use `R/dynamicDIA.R` functions with `prospectr` package
- Support savgol/movav/gaussian smoothing methods
- Apply smoothing to RT-dependent m/z boundaries for gradient continuity

**Iterative Convergence Criteria**:
- DPPP satisfaction > 90% AND Coverage > 95%
- OR Δmetrics < 2% between consecutive iterations
- OR user manually stops iteration workflow
- OR max_iterations reached

**Performance Metrics**:
- **DPPP satisfaction ratio**: % precursors meeting target DPPP (within tolerance)
- **Precursor coverage**: % precursors within window boundaries
- **Window count efficiency**: Average precursors per window
- **Segment balance score**: Coefficient of variation across RT segments
- **Weighted composite score**: Combined metric for iteration ranking

**Smart Parameter Adjustment**:
- DPPP satisfaction → adjust scan_time proportionally
- High RT bin variance → adjust rt_bin_width_min for better temporal consistency
- Coverage gaps > 5% → increase window overlap by 20%
- Low precursors/window < 50 → adjust target DPPP or increase min_width_da by 10%
