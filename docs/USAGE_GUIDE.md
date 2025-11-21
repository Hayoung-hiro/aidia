# DIA Window Optimizer - User Guide

**Version**: 2.1 (Architecture Refactored)
**Date**: 2025-11-20
**Status**: Production Ready

---

## 📋 Table of Contents

1. [Quick Start](#quick-start)
2. [Complete Pipeline](#complete-pipeline)
3. [Stage-by-Stage Usage](#stage-by-stage-usage)
4. [Multi-Strategy Workflow](#multi-strategy-workflow)
5. [Export Options](#export-options)
6. [Advanced Usage](#advanced-usage)
7. [Troubleshooting](#troubleshooting)

---

## 🚀 Quick Start

### Minimal Example (Single Strategy)

```r
# Load modules
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

# Run pipeline
validated <- create_validated_dataset("data/60min_report.parquet")
plan <- plan_optimization(validated, current_cycle_time = 3.5,
                          instrument_preset = "astral", target_dppp = 7.0)
windows <- optimize_windows(validated, plan, rt_bin_width_min = 5,
                            mz_strategy = "smoothing", window_mode = "variable")

# Export method file
export_windows_to_csv(windows, "output/method.csv", validated, plan)

# Generate visualizations
viz <- generate_visualizations(validated, plan, windows,
                                output_dir = "output/")
```

**Output**:
- `output/method.csv` (22-column Thermo format)
- `output/optimization_report.pdf` (24 plots)

---

## 📊 Complete Pipeline

### Full Workflow with All 4 Strategies

```r
library(dplyr)
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

# ═══════════════════════════════════════════════════════════════
# Stage 1: Data Validation
# ═══════════════════════════════════════════════════════════════

validated <- create_validated_dataset(
  input_file = "data/90min_report.parquet",
  replicate_handling = "consensus",  # Optional: for technical replicates
  min_precursors = 100
)

cat(sprintf("✓ Loaded %d precursors\n", nrow(validated$data)))
cat(sprintf("✓ RT range: %.1f - %.1f min\n",
            validated$metadata$rt_range[1],
            validated$metadata$rt_range[2]))

# ═══════════════════════════════════════════════════════════════
# Stage 2: Optimization Planning
# ═══════════════════════════════════════════════════════════════

plan <- plan_optimization(
  validated_data = validated,
  current_cycle_time = 3.5,        # Current cycle time (seconds)
  instrument_preset = "astral",    # "astral", "exploris", "orbitrap"
  target_dppp = 7.0,               # Quant mode (7.0) or ID mode (1.5)
  scan_time_tolerance = 0.1
)

cat(sprintf("✓ Target DPPP: %.1f\n", plan$target_dppp))
cat(sprintf("✓ Required cycle time: %.2f sec\n", plan$required_cycle_time_sec))
cat(sprintf("✓ Recommended windows: %d\n", plan$recommended_n_windows))

# ═══════════════════════════════════════════════════════════════
# Stage 3: Window Optimization (All 4 Strategies)
# ═══════════════════════════════════════════════════════════════

strategies <- c("quantile", "coverage", "outlier", "smoothing")
windows_list <- list()

for (strategy in strategies) {
  cat(sprintf("\nOptimizing with %s strategy...\n", strategy))

  windows_list[[strategy]] <- optimize_windows(
    validated_data = validated,
    optimization_plan = plan,
    rt_bin_width_min = 5,          # RT bin width (minutes)
    mz_strategy = strategy,         # quantile, coverage, outlier, smoothing
    window_mode = "variable",       # variable (recommended) or fixed
    n_windows_per_bin = NULL,       # Auto-calculate from plan
    target_coverage = 0.95,         # For coverage strategy
    quantile_lower = 0.05,          # For quantile strategy (P5)
    quantile_upper = 0.95,          # For quantile strategy (P95)
    outlier_threshold = 3.0,        # For outlier strategy (3σ)
    smoothing_window = 3,           # For smoothing strategy
    polynomial_order = 2            # For smoothing strategy
  )

  cat(sprintf("✓ Generated %d windows (%.1f%% coverage)\n",
              nrow(windows_list[[strategy]]$windows),
              windows_list[[strategy]]$statistics$coverage_percentage))
}

# ═══════════════════════════════════════════════════════════════
# Stage 3B: Export Method Files (All Strategies)
# ═══════════════════════════════════════════════════════════════

method_files <- export_method_files(
  windows_list = windows_list,
  output_dir = "output/90min_results",
  validated_data = validated,
  optimization_plan = plan,
  strategies = c("quantile", "coverage", "outlier", "smoothing"),  # All 4
  instrument_type = plan$instrument$preset,
  normalized_agc_target = 100
)

cat("\n✓ Exported method files:\n")
for (strategy in names(method_files)) {
  cat(sprintf("  - %s\n", basename(method_files[[strategy]])))
}

# ═══════════════════════════════════════════════════════════════
# Stage 4: Visualization (Plots Only)
# ═══════════════════════════════════════════════════════════════

viz <- generate_visualizations(
  validated_data = validated,
  optimization_plan = plan,
  optimized_windows = windows_list[["smoothing"]],  # Primary strategy
  windows_list = windows_list,                      # All 4 for comparison
  output_dir = "output/90min_results",
  create_pdf_report = TRUE,
  create_individual_plots = TRUE,                   # Export PNG files
  dpi = 300
)

cat(sprintf("\n✓ Generated %d plots\n", length(viz$plots)))
cat(sprintf("✓ PDF report: %s\n", basename(viz$report_files$pdf_report)))
```

**Output Structure**:
```
output/90min_results/
├── method_quantile.csv      (22 cols, 1220 windows)
├── method_coverage.csv      (22 cols, 1252 windows)
├── method_outlier.csv       (22 cols, 1257 windows)
├── method_smoothing.csv     (22 cols, 1216 windows)
├── optimization_report.pdf  (24 plots)
└── plot*.png (24 files)     (300 DPI)
```

---

## 🔧 Stage-by-Stage Usage

### Stage 1: Data Validation

**Basic Usage**:
```r
validated <- create_validated_dataset("data/report.parquet")
```

**With Technical Replicates** (3 runs):
```r
validated <- create_validated_dataset(
  input_file = "data/30min_report.parquet",
  replicate_handling = "consensus",  # "representative", "average", "consensus", "none"
  cv_threshold = 0.30                # Filter replicates with CV > 30%
)
```

**Output**:
```r
# ValidatedData object
validated$data              # tibble: RT.Start, Precursor.Mz, FWHM, ...
validated$metadata          # List: n_precursors, rt_range, mz_range, fwhm_stats
validated$validation_status # List: all_passed, quality_score, warnings
```

### Stage 2: Optimization Planning

**Quant Mode** (DPPP 7.0, recommended):
```r
plan <- plan_optimization(
  validated,
  current_cycle_time = 3.5,
  instrument_preset = "astral",
  target_dppp = 7.0
)
```

**ID Mode** (DPPP 1.5, for discovery):
```r
plan <- plan_optimization(
  validated,
  current_cycle_time = 3.5,
  instrument_preset = "exploris",
  target_dppp = 1.5
)
```

**Output**:
```r
# OptimizationPlan object
plan$target_dppp                    # 7.0
plan$required_cycle_time_sec        # 1.8 (calculated)
plan$recommended_n_windows          # 659 (calculated)
plan$instrument                     # List: name, preset, ms1_time, ms2_time
plan$feasibility                    # List: is_feasible, max_scan_rate
```

### Stage 3: Window Optimization

**Strategy Comparison**:

| Strategy | Algorithm | Use Case | Coverage | Speed |
|----------|-----------|----------|----------|-------|
| **Quantile** | P5-P95 percentiles | Routine, robust | ~89% | ⚡⚡⚡ Fast |
| **Coverage** | Min range for 95% | Discovery, comprehensive | ~94% | ⚡⚡ Medium |
| **Outlier** | Mean ± 3σ | High-throughput, inclusive | ~99% | ⚡⚡ Medium |
| **Smoothing** | Savitzky-Golay | Publication, smooth transitions | ~88% | ⚡ Slower |

**Example: Quantile Strategy**
```r
windows <- optimize_windows(
  validated, plan,
  rt_bin_width_min = 5,
  mz_strategy = "quantile",
  window_mode = "variable",
  quantile_lower = 0.05,  # P5
  quantile_upper = 0.95   # P95
)
```

**Example: Coverage Strategy**
```r
windows <- optimize_windows(
  validated, plan,
  rt_bin_width_min = 5,
  mz_strategy = "coverage",
  window_mode = "variable",
  target_coverage = 0.95  # 95% coverage
)
```

**Example: Smoothing Strategy**
```r
windows <- optimize_windows(
  validated, plan,
  rt_bin_width_min = 5,
  mz_strategy = "smoothing",
  window_mode = "variable",
  smoothing_window = 3,       # ±3 bins
  polynomial_order = 2        # Quadratic
)
```

**Output**:
```r
# OptimizedWindows object
windows$windows                     # tibble: window_id, rt_start, rt_end, mz_start, mz_end, ...
windows$statistics                  # List: coverage_percentage, mean_precursors_per_window, ...
windows$parameters                  # List: mz_strategy, window_mode, rt_bin_width_min
windows$rt_binning                  # List: n_bins, rt_breaks
```

### Stage 4: Visualization

**Basic (PDF only)**:
```r
viz <- generate_visualizations(
  validated, plan, windows,
  output_dir = "output/",
  create_pdf_report = TRUE,
  create_individual_plots = FALSE
)
```

**With Individual PNG Files**:
```r
viz <- generate_visualizations(
  validated, plan, windows,
  output_dir = "output/",
  create_pdf_report = TRUE,
  create_individual_plots = TRUE,
  dpi = 300
)
```

**Multi-Strategy Comparison**:
```r
viz <- generate_visualizations(
  validated, plan,
  optimized_windows = windows_list[["smoothing"]],  # Primary
  windows_list = windows_list,                      # All 4 for comparison plots
  output_dir = "output/",
  create_individual_plots = TRUE
)
```

**Output**:
```r
# VisualizationResult object
viz$plots                           # List: 24 ggplot objects
viz$report_files$pdf_report         # Path to PDF report
viz$summary_statistics              # List: optimization metrics
```

**24 Plot Suite**:
1. **Plot 1A/1B**: DPPP Distribution (Simple & Enhanced)
2. **Plot 2**: RT × m/z Density Heatmap
3. **Plot 2B**: RT Histogram (Continuous & 5-min binned)
4. **Plot 3**: m/z Density Overlay by RT Segment
5. **Plot 4 (A-D)**: m/z Excluded Regions (4 strategies)
6. **Plot 4E**: m/z Width All Strategies Comparison
7. **Plot 5**: Coverage Map 2×2 Grid (4 strategies)
8. **Plot 6**: Satisfaction vs Cycle Time Trade-off
9. **Plot 7 (×4)**: Window Width Distribution (4 strategies)
10. **Plot 7B (×4)**: Window Index Width Bars (4 strategies)
11. **Plot 8A**: Ridge Plot - Strategy Width Comparison
12. **Plot 8B**: Box Plot - Statistical Summary
13. **Plot 8C**: CDF - Cumulative Distribution

---

## 🎯 Multi-Strategy Workflow

### Why Use Multiple Strategies?

Different strategies optimize for different goals:

- **Quantile**: Fast, robust, balanced coverage
- **Coverage**: Maximum coverage, wider m/z range
- **Outlier**: Maximum inclusivity, removes only extreme outliers
- **Smoothing**: Smooth RT transitions, publication-quality

### Workflow: Generate & Compare All 4

```r
# 1. Generate all strategies
strategies <- c("quantile", "coverage", "outlier", "smoothing")
windows_list <- list()

for (strategy in strategies) {
  windows_list[[strategy]] <- optimize_windows(
    validated, plan,
    rt_bin_width_min = 5,
    mz_strategy = strategy,
    window_mode = "variable"
  )
}

# 2. Export all method files
method_files <- export_method_files(
  windows_list, "output/", validated, plan
)

# 3. Compare strategies visually
viz <- generate_visualizations(
  validated, plan,
  optimized_windows = windows_list[["smoothing"]],
  windows_list = windows_list,  # Enables comparison plots
  output_dir = "output/"
)
```

### Strategy Selection Guide

**For Routine Analysis**:
```r
# Use Quantile (fast, reliable)
windows <- optimize_windows(validated, plan, mz_strategy = "quantile")
export_windows_to_csv(windows, "method_routine.csv", validated, plan)
```

**For Discovery/Comprehensive Coverage**:
```r
# Use Coverage (maximum coverage)
windows <- optimize_windows(validated, plan, mz_strategy = "coverage", target_coverage = 0.98)
export_windows_to_csv(windows, "method_discovery.csv", validated, plan)
```

**For Publication/High-Quality Data**:
```r
# Use Smoothing (smooth transitions)
windows <- optimize_windows(validated, plan, mz_strategy = "smoothing")
export_windows_to_csv(windows, "method_publication.csv", validated, plan)
```

---

## 📤 Export Options

### Option 1: Single Strategy Export

```r
# Export one strategy
export_windows_to_csv(
  optimized_windows = windows,
  output_file = "output/method.csv",
  validated_data = validated,
  optimization_plan = plan,
  instrument_type = "astral",
  normalized_agc_target = 100
)
```

### Option 2: Multi-Strategy Export (Default)

```r
# Export all 4 strategies at once
method_files <- export_method_files(
  windows_list = windows_list,
  output_dir = "output/",
  validated_data = validated,
  optimization_plan = plan
  # strategies defaults to c("quantile", "coverage", "outlier", "smoothing")
)
```

**Output**:
```
output/
├── method_quantile.csv
├── method_coverage.csv
├── method_outlier.csv
└── method_smoothing.csv
```

### Option 3: Selective Export

```r
# Export only specific strategies
method_files <- export_method_files(
  windows_list,
  "output/",
  validated, plan,
  strategies = c("smoothing", "coverage")  # Only 2 strategies
)
```

**Output**:
```
output/
├── method_smoothing.csv
└── method_coverage.csv
```

### Method File Format (22 Columns)

All method files use the **Thermo Xcalibur 22-column format**:

| Column | Description | Example |
|--------|-------------|---------|
| Compound | Compound name (empty for DIA) | "" |
| Formula | Chemical formula (empty) | "" |
| Adduct | Adduct type | "(no adduct)" |
| m/z | Center m/z | 465.5 |
| z | Charge state (assumed 2+) | 1 |
| t start (min) | RT window start | 11.2 |
| t stop (min) | RT window end | 16.2 |
| Isolation Window (m/z) | Window width | 6.3 |
| Normalized AGC Target (%) | AGC target | 100 |
| Start (m/z) | m/z range start | 462.4 |
| End (m/z) | m/z range end | 468.7 |
| Window_ID | Window index | 1 |
| RT_Segment_ID | RT bin index | 1 |
| RT_Center | RT center | 13.7 |
| RT_Width | RT bin width | 5 |
| N_Precursors | Precursor count | 8 |
| Overlap_Prev | Overlap with previous | 0 |
| Overlap_Next | Overlap with next | 0 |
| Instrument | Instrument name | "astral" |
| Generation_Method | Strategy used | "smoothing" |
| Window_Type | Window mode | "variable" |
| Recommended_Cycle_Time_Sec | Cycle time | 1.2 |

**Import to Thermo Xcalibur**:
1. Open Xcalibur Method Editor
2. File → Import → Select `method_{strategy}.csv`
3. Verify window parameters
4. Save method

---

## 🔬 Advanced Usage

### Custom RT Binning

```r
# Shorter RT bins (higher resolution)
windows <- optimize_windows(
  validated, plan,
  rt_bin_width_min = 2,  # 2-minute bins instead of 5
  mz_strategy = "smoothing"
)
```

### Custom Coverage Target

```r
# Very high coverage
windows <- optimize_windows(
  validated, plan,
  mz_strategy = "coverage",
  target_coverage = 0.98  # 98% instead of 95%
)
```

### Fixed Window Mode

```r
# Equal-width windows (not recommended)
windows <- optimize_windows(
  validated, plan,
  mz_strategy = "quantile",
  window_mode = "fixed"
)
```

### Manual Window Count

```r
# Override auto-calculation
windows <- optimize_windows(
  validated, plan,
  mz_strategy = "smoothing",
  n_windows_per_bin = 40  # Force 40 windows per RT bin
)
```

---

## 🔍 Troubleshooting

### Issue 1: "Not enough RT bins for smoothing"

**Cause**: RT bins (n=2) < smoothing window (n=3)

**Solution**:
```r
# Option A: Reduce smoothing window
windows <- optimize_windows(validated, plan,
                            mz_strategy = "smoothing",
                            smoothing_window = 1)

# Option B: Use narrower RT bins
windows <- optimize_windows(validated, plan,
                            rt_bin_width_min = 3,  # Narrower bins
                            mz_strategy = "smoothing")

# Option C: Use different strategy
windows <- optimize_windows(validated, plan, mz_strategy = "quantile")
```

### Issue 2: Low Coverage (<80%)

**Causes**: Narrow m/z ranges, aggressive filtering

**Solution**:
```r
# Use Coverage strategy
windows <- optimize_windows(validated, plan,
                            mz_strategy = "coverage",
                            target_coverage = 0.98)

# Or use Outlier strategy (most inclusive)
windows <- optimize_windows(validated, plan,
                            mz_strategy = "outlier",
                            outlier_threshold = 3.5)  # More inclusive
```

### Issue 3: Too Many Windows (>1500)

**Causes**: Many RT bins, high windows per bin

**Solution**:
```r
# Option A: Wider RT bins
windows <- optimize_windows(validated, plan, rt_bin_width_min = 10)

# Option B: Manual window count
windows <- optimize_windows(validated, plan, n_windows_per_bin = 30)
```

### Issue 4: Method File Not Compatible with Instrument

**Cause**: Wrong instrument type

**Solution**:
```r
# Specify correct instrument
export_windows_to_csv(
  windows, "method.csv", validated, plan,
  instrument_type = "exploris"  # Match your instrument
)
```

---

## 📚 Quick Reference

### Key Functions

| Function | Purpose | Stage |
|----------|---------|-------|
| `create_validated_dataset()` | Load & validate data | Stage 1 |
| `plan_optimization()` | Calculate optimal parameters | Stage 2 |
| `optimize_windows()` | Generate isolation windows | Stage 3 |
| `export_windows_to_csv()` | Export single strategy | Stage 3 |
| `export_method_files()` | Export all strategies | Stage 3 |
| `generate_visualizations()` | Create plots & reports | Stage 4 |

### Recommended Parameters

| Parameter | Recommended | Range | Notes |
|-----------|-------------|-------|-------|
| `target_dppp` | 7.0 | 1.5-10.0 | 7.0=Quant, 1.5=ID |
| `rt_bin_width_min` | 5 | 2-10 | Narrower = higher resolution |
| `mz_strategy` | "smoothing" | 4 options | Smoothing for publication |
| `window_mode` | "variable" | fixed/variable | Variable recommended |
| `target_coverage` | 0.95 | 0.90-0.99 | For coverage strategy |
| `outlier_threshold` | 3.0 | 2.0-4.0 | For outlier strategy |

---

## 📖 Example Workflows

### Workflow 1: Quick Analysis (30min gradient)

```r
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

validated <- create_validated_dataset("data/30min_report.parquet")
plan <- plan_optimization(validated, 3.5, "astral", 7.0)
windows <- optimize_windows(validated, plan, 5, "quantile", "variable")
export_windows_to_csv(windows, "output/method.csv", validated, plan)
viz <- generate_visualizations(validated, plan, windows, "output/")
```

### Workflow 2: Comprehensive Analysis (All Strategies)

```r
# Full script in "Complete Pipeline" section above
```

### Workflow 3: Batch Processing (Multiple Datasets)

```r
datasets <- c("30min", "60min", "90min")

for (name in datasets) {
  validated <- create_validated_dataset(sprintf("data/%s_report.parquet", name))
  plan <- plan_optimization(validated, 3.5, "astral", 7.0)

  # Generate all strategies
  windows_list <- list()
  for (strategy in c("quantile", "coverage", "outlier", "smoothing")) {
    windows_list[[strategy]] <- optimize_windows(validated, plan, 5, strategy, "variable")
  }

  # Export & visualize
  output_dir <- sprintf("output/%s", name)
  export_method_files(windows_list, output_dir, validated, plan)
  viz <- generate_visualizations(validated, plan, windows_list[["smoothing"]],
                                  windows_list, output_dir, create_individual_plots = TRUE)
}
```

---

**Last Updated**: 2025-11-20
**Version**: 2.1
**Architecture**: Refactored (Phase 1 Complete)
