# DIA Window Optimizer - Full Workflow Guide

Complete guide for using the 4-stage DIA window optimization pipeline.

---

## Quick Start

### 1. Using the Comprehensive Pipeline (Module 3D Only)

**Current approach** - Fastest for generating windows with pre-configured settings:

```r
source("run_comprehensive_pipeline.R")
```

**What it does:**
- Directly uses Module 3D window generation
- Pre-configured RT binning and m/z ranges
- Generates 8 combinations per dataset (4 strategies × 2 modes)
- **Best for:** Quick method generation, batch processing

**Limitations:**
- No DPPP diagnosis
- No custom RT binning
- No visualization reports

---

### 2. Using the Full 4-Stage Pipeline

**New approach** - Complete workflow with all diagnostic features:

```r
source("run_full_pipeline.R")
```

**What it does:**
- **Stage 1:** Data validation with quality checks
- **Stage 2:** DPPP diagnosis and cycle time optimization
- **Stage 3A-D:** Window count determination → RT binning → m/z optimization → Window generation
- **Stage 4:** Comprehensive visualization and reporting

**Best for:**
- Exploratory analysis
- Understanding current DPPP status
- Custom optimization requirements
- Publication-quality reports

---

## Architecture Comparison

### Comprehensive Pipeline (run_comprehensive_pipeline.R)

```
Input: DIA-NN Parquet
         ↓
    [Module 3D]
    - Pre-configured RT bins
    - Pre-configured m/z ranges
    - Direct window generation
         ↓
Output: CSV method files
```

**Pros:**
- ✅ Fast execution
- ✅ Simple configuration
- ✅ Batch processing ready
- ✅ Tested with 9 datasets

**Cons:**
- ❌ No DPPP diagnosis
- ❌ Fixed RT binning strategy
- ❌ No visualization reports
- ❌ Limited customization

---

### Full Pipeline (run_full_pipeline.R)

```
Input: DIA-NN Parquet
         ↓
    [Stage 1: Data Validation]
    - Load and validate data
    - Quality filtering
    - Optional raw metadata
         ↓
    [Stage 2: DPPP Diagnosis]
    - Current DPPP distribution
    - Cycle time optimization
    - Satisfaction analysis
         ↓
    [Stage 3A: Window Count]
    - Calculate optimal window count
    - Instrument feasibility check
         ↓
    [Stage 3B: RT Binning]
    - Time-based or custom breakpoints
    - Flexible binning strategies
         ↓
    [Stage 3C: m/z Range Optimization]
    - 4 strategies: quantile, smoothing, outlier, coverage
    - RT-dependent m/z ranges
         ↓
    [Stage 3D: Window Generation]
    - Fixed, Variable, or Overlapped modes
    - Density-based allocation
         ↓
    [Stage 4: Visualization & Reporting]
    - 8 diagnostic plots
    - PDF report
    - Method files (Thermo + Legacy)
         ↓
Output: Complete analysis package
```

**Pros:**
- ✅ Complete diagnostic workflow
- ✅ DPPP status analysis
- ✅ Flexible configuration
- ✅ Comprehensive reporting
- ✅ Publication-quality plots

**Cons:**
- ❌ Slower execution
- ❌ More complex configuration
- ❌ Requires all stage modules

---

## Configuration Guide

### Comprehensive Pipeline Settings

```r
# run_comprehensive_pipeline.R

# Gradient-specific (auto-detected from filename)
GRADIENT_CONFIG <- list(
  "30min" = list(
    cycle_time = 1.2,
    max_windows = 21,      # Windows PER segment
    rt_segments = 3,
    target_dppp = 7.0
  )
)

# m/z strategies (batch processing)
STRATEGIES <- c("quantile", "smoothing", "outlier", "coverage")

# Window modes (batch processing)
MODES <- c("fixed", "variable")

# Window constraints
MIN_WIDTH_DA <- 10
MAX_WIDTH_DA <- 80
OVERLAP_PERCENT <- 0.02
```

**To modify:**
1. Edit `GRADIENT_CONFIG` for your gradient settings
2. Change `STRATEGIES` or `MODES` to process specific combinations
3. Adjust `MIN_WIDTH_DA` / `MAX_WIDTH_DA` for instrument constraints

---

### Full Pipeline Settings

```r
# run_full_pipeline.R

# Instrument configuration
INSTRUMENT_TYPE <- "astral"  # "astral", "exploris", "traditional"

# DPPP parameters
TARGET_DPPP <- 7.0
TARGET_SATISFACTION <- 0.85

# RT binning
RT_BINNING_MODE <- "time_unit"  # or "time_breaks"
RT_TIME_UNIT <- 5.0  # minutes per bin

# m/z strategy (single selection)
MZ_STRATEGY <- "smoothing"  # "quantile", "smoothing", "outlier", "coverage"

# Window generation
WINDOW_MODE <- "variable"  # "fixed", "variable", "overlapped"
MIN_WIDTH_DA <- 10
MAX_WIDTH_DA <- 80
OVERLAP_PERCENT <- 0.02
```

**To modify:**
1. Change `INSTRUMENT_TYPE` to match your instrument
2. Adjust `TARGET_DPPP` and `TARGET_SATISFACTION` for optimization goals
3. Set `RT_BINNING_MODE` to "time_breaks" for custom RT segments:
   ```r
   RT_BINNING_MODE <- "time_breaks"
   RT_TIME_BREAKS <- c(0, 15, 30, 45, 60)  # Custom breakpoints
   ```
4. Select single `MZ_STRATEGY` and `WINDOW_MODE` for focused analysis

---

## Usage Examples

### Example 1: Quick Method Generation (Comprehensive Pipeline)

**Use case:** Generate methods for all 9 datasets with smoothing strategy

```r
# 1. Edit run_comprehensive_pipeline.R
DEFAULT_STRATEGY <- "smoothing"
DEFAULT_MODE <- "variable"

# 2. Run pipeline
source("run_comprehensive_pipeline.R")

# 3. Results in results_comprehensive/
#    - 30min_report_01_smoothing_variable_thermo.csv
#    - 30min_report_01_smoothing_variable_legacy.csv
#    - ... (72 files total)
```

**Output:** 72 CSV files (9 datasets × 4 strategies × 2 modes)

---

### Example 2: Full Diagnostic Analysis

**Use case:** Understand DPPP status and optimize for target satisfaction

```r
# 1. Configure run_full_pipeline.R
INPUT_FILE <- "data/30min_report_01.parquet"
INSTRUMENT_TYPE <- "astral"
TARGET_DPPP <- 7.0
TARGET_SATISFACTION <- 0.85
MZ_STRATEGY <- "smoothing"
WINDOW_MODE <- "variable"

# 2. Run full pipeline
source("run_full_pipeline.R")

# 3. Results in results_full_pipeline/
#    - dppp_density_plot.png
#    - rt_window_allocation.png
#    - ... (8 plots)
#    - comprehensive_report.pdf
#    - method_file_thermo.csv
#    - method_file_legacy.csv
```

**Output:** Complete analysis package with diagnostic plots and reports

---

### Example 3: Technical Replicate Integration

**Use case:** Combine 3 technical replicates into unified methods

```r
# 1. Edit run_integrated_pipeline.R
DEFAULT_STRATEGY <- "smoothing"
DEFAULT_MODE <- "variable"

# 2. Run integration
source("run_integrated_pipeline.R")

# 3. Results in results_integrated/
#    - 30min_integrated_smoothing_variable_thermo.csv
#    - 60min_integrated_smoothing_variable_thermo.csv
#    - 90min_integrated_smoothing_variable_thermo.csv
```

**Output:** 6 CSV files (3 gradients × 2 formats)

---

### Example 4: Custom RT Segments

**Use case:** Use custom RT breakpoints for specific chromatography

```r
# Full pipeline with custom breakpoints
result <- run_full_pipeline(
  input_file = "data/90min_report_01.parquet",
  instrument_type = "astral",
  rt_binning_mode = "time_breaks",
  rt_time_breaks = c(0, 20, 40, 60, 80),  # Custom breakpoints
  mz_strategy = "smoothing",
  window_mode = "variable",
  output_dir = "results_custom_rt"
)
```

---

### Example 5: Strategy Comparison

**Use case:** Compare all m/z strategies to find optimal approach

```r
# Use example_full_workflow.R Example 5
source("example_full_workflow.R")

# Automatically generates:
# - 8 method combinations (4 strategies × 2 modes)
# - Comparison summary CSV
# - Side-by-side performance metrics
```

---

## When to Use Which Pipeline?

### Use **Comprehensive Pipeline** when:

✅ You need **quick method generation**
✅ You have **pre-validated settings**
✅ You want to **batch process multiple datasets**
✅ You need **CSV method files only**
✅ You're confident in your RT binning strategy

**Example use cases:**
- Routine method generation for established protocols
- High-throughput processing of multiple samples
- Quick iteration on window generation parameters
- Production deployment with validated settings

---

### Use **Full Pipeline** when:

✅ You need **DPPP diagnosis**
✅ You want to **understand current status**
✅ You need **custom RT binning**
✅ You require **visualization reports**
✅ You're **exploring optimization strategies**
✅ You need **publication-quality figures**

**Example use cases:**
- Initial method development and optimization
- Troubleshooting sub-optimal DPPP performance
- Comparing different optimization strategies
- Creating comprehensive analysis reports
- Publication preparation with diagnostic plots

---

## Output File Comparison

### Comprehensive Pipeline Outputs

```
results_comprehensive/
├── 30min_report_01_quantile_fixed_thermo.csv
├── 30min_report_01_quantile_fixed_legacy.csv
├── 30min_report_01_quantile_variable_thermo.csv
├── 30min_report_01_quantile_variable_legacy.csv
├── 30min_report_01_smoothing_fixed_thermo.csv
├── 30min_report_01_smoothing_fixed_legacy.csv
├── 30min_report_01_smoothing_variable_thermo.csv
├── 30min_report_01_smoothing_variable_legacy.csv
├── ... (same for outlier and coverage strategies)
└── comprehensive_results_summary.csv
```

**Total:** 72 method files + 1 summary CSV

---

### Full Pipeline Outputs

```
results_full_pipeline/
├── plots/
│   ├── 01_dppp_density.png
│   ├── 02_rt_window_allocation.png
│   ├── 03_window_width_distribution.png
│   ├── 04_mz_coverage_heatmap.png
│   ├── 05_precursor_distribution.png
│   ├── 06_window_efficiency.png
│   ├── 07_cycle_time_analysis.png
│   └── 08_dppp_achievement_heatmap.png
│
├── reports/
│   ├── comprehensive_report.pdf
│   └── summary_statistics.csv
│
└── methods/
    ├── method_thermo_fusion_lumos.csv
    └── method_legacy_format.csv
```

**Total:** 8 plots + 1 PDF report + 2 method files + 1 summary CSV

---

### Integrated Pipeline Outputs

```
results_integrated/
├── 30min_integrated_smoothing_variable_thermo.csv
├── 30min_integrated_smoothing_variable_legacy.csv
├── 60min_integrated_smoothing_variable_thermo.csv
├── 60min_integrated_smoothing_variable_legacy.csv
├── 90min_integrated_smoothing_variable_thermo.csv
├── 90min_integrated_smoothing_variable_legacy.csv
└── integrated_methods_summary.csv
```

**Total:** 6 method files + 1 summary CSV

---

## Command Reference

### Run Comprehensive Pipeline
```bash
cd /d/Projects/dia_window_optimizer
Rscript run_comprehensive_pipeline.R
```

### Run Full Pipeline
```bash
Rscript run_full_pipeline.R
```

### Run Integrated Pipeline
```bash
Rscript run_integrated_pipeline.R
```

### Run Examples
```bash
Rscript example_full_workflow.R
```

---

## Troubleshooting

### Issue 1: Module not found

**Error:** `Error in source("R/stage1_data_validation.R") : cannot open file`

**Solution:**
```r
# Check if all stage modules exist
file.exists("R/stage1_data_validation.R")
file.exists("R/stage2_dppp_diagnosis.R")
file.exists("R/stage3_window_optimization/module3a_window_count.R")
file.exists("R/stage3_window_optimization/module3b_rt_binning.R")
file.exists("R/stage3_window_optimization/module3c_mz_range_optimization.R")
file.exists("R/stage3_window_optimization/module3d_window_generation.R")
file.exists("R/stage4_visualization.R")

# If any FALSE, check DEVELOPMENT.md for development status
```

---

### Issue 2: Window count mismatch

**Error:** Expected 63 windows, got 21

**Solution:**
```r
# Check per_bin_mode setting in window_config
window_config <- list(
  window_mode = "variable",
  total_windows = 21,
  per_bin_mode = TRUE,  # Must be TRUE for NEW ARCHITECTURE
  min_width_da = 10,
  max_width_da = 80,
  overlap = 0.02
)

# per_bin_mode = TRUE → 21 windows PER segment (21 × 3 = 63 total)
# per_bin_mode = FALSE → 21 windows TOTAL (21 / 3 = 7 per segment)
```

---

### Issue 3: Missing required columns

**Error:** `Required column 'FWHM' not found in data`

**Solution:**
```r
# Check DIA-NN output columns
data <- arrow::read_parquet("data/30min_report_01.parquet")
colnames(data)

# Required columns: RT.Start, Precursor.Mz, FWHM
# If missing, check DIA-NN version and export settings
```

---

## Performance Tips

### Tip 1: Use Comprehensive Pipeline for Batch Processing

**Fast:**
```r
source("run_comprehensive_pipeline.R")  # Processes 9 datasets in ~2 minutes
```

**Slow:**
```r
for (file in parquet_files) {
  source("run_full_pipeline.R")  # ~5 minutes per dataset
}
```

---

### Tip 2: Disable Visualization for Speed

**In Full Pipeline:**
```r
# Comment out Stage 4 if only need method files
# stage4_result <- generate_visualizations(...)

# Saves ~30% execution time
```

---

### Tip 3: Use Parallel Processing for Multiple Files

```r
library(parallel)

files <- list.files("data", pattern = "\\.parquet$", full.names = TRUE)

results <- mclapply(files, function(file) {
  run_full_pipeline(
    input_file = file,
    output_dir = sprintf("results_%s", basename(file))
  )
}, mc.cores = 4)  # Use 4 CPU cores
```

---

## Next Steps

1. **Start with Comprehensive Pipeline** for quick testing
2. **Switch to Full Pipeline** for detailed analysis
3. **Use Integrated Pipeline** for technical replicate consolidation
4. **Refer to DEVELOPMENT.md** for implementation status
5. **Check docs/phases/** for detailed module documentation

---

## Summary Table

| Feature | Comprehensive | Full | Integrated |
|---------|--------------|------|------------|
| **Speed** | ⚡⚡⚡ Fast | 🐢 Slower | ⚡⚡ Medium |
| **DPPP Diagnosis** | ❌ No | ✅ Yes | ❌ No |
| **Custom RT Binning** | ❌ No | ✅ Yes | ❌ No |
| **Visualization** | ❌ No | ✅ Yes | ❌ No |
| **Batch Processing** | ✅ Yes | ⚠️ Manual | ✅ Yes |
| **Technical Replicates** | ❌ No | ❌ No | ✅ Yes |
| **Best For** | Production | Exploration | Integration |

---

**Version:** 1.0
**Last Updated:** 2025-10-24
**Status:** Active
