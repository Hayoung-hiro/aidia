# DIA Window Optimizer

**Version**: 2.1 (Architecture Refactored)
**Status**: Production Ready
**Last Updated**: 2025-11-20

Advanced R-based tool for optimizing Data-Independent Acquisition (DIA) isolation windows for mass spectrometry. Implements a **streamlined 4-stage pipeline** with comprehensive multi-strategy optimization.

---

## ✨ Key Features

- 🎯 **4 Optimization Strategies**: Quantile, Coverage, Outlier, Smoothing
- 📊 **24-Plot Visualization Suite**: Comprehensive analysis and comparison
- 🔧 **Multi-Instrument Support**: Astral, Exploris, Orbitrap, TimsTOF
- 📁 **22-Column Thermo Format**: Direct import to Xcalibur
- 🧬 **Technical Replicate Handling**: Consensus-based with geometric CV filtering
- ⚡ **High Performance**: Vectorized operations, 50-100× faster matching
- 📈 **DPPP-Based**: Quant mode (7.0) or ID mode (1.5)

---

## 🚀 Quick Start

### Installation

```r
# Install required packages
install.packages(c("arrow", "dplyr", "ggplot2", "gridExtra",
                   "jsonlite", "tidyr", "viridis", "scales",
                   "prospectr", "ggridges"))
```

### Basic Usage (Single Strategy)

```r
# Load modules
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

# Run pipeline
validated <- create_validated_dataset("data/report.parquet")
plan <- plan_optimization(validated, current_cycle_time = 3.5,
                          instrument_preset = "astral", target_dppp = 7.0)
windows <- optimize_windows(validated, plan, rt_bin_width_min = 5,
                            mz_strategy = "smoothing", window_mode = "variable")

# Export method file
export_windows_to_csv(windows, "output/method.csv", validated, plan)

# Generate visualizations
viz <- generate_visualizations(validated, plan, windows, output_dir = "output/")
```

**Output**:
- `output/method.csv` (22-column Thermo format, ready for Xcalibur)
- `output/optimization_report.pdf` (24 plots)

---

## 📋 Complete Workflow (All 4 Strategies)

```r
library(dplyr)
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

# Stage 1: Validate data
validated <- create_validated_dataset("data/90min_report.parquet")

# Stage 2: Plan optimization
plan <- plan_optimization(validated, current_cycle_time = 3.5,
                          instrument_preset = "astral", target_dppp = 7.0)

# Stage 3: Generate windows for all 4 strategies
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

# Export all method files
method_files <- export_method_files(
  windows_list, "output/", validated, plan
)

# Stage 4: Visualize with multi-strategy comparison
viz <- generate_visualizations(
  validated, plan,
  optimized_windows = windows_list[["smoothing"]],
  windows_list = windows_list,  # Enables comparison plots
  output_dir = "output/",
  create_individual_plots = TRUE
)
```

**Output**:
```
output/
├── method_quantile.csv      (184 windows, 89.2% coverage)
├── method_coverage.csv      (185 windows, 94.6% coverage)
├── method_outlier.csv       (185 windows, 99.6% coverage)
├── method_smoothing.csv     (183 windows, 88.3% coverage)
├── optimization_report.pdf  (24 plots)
└── 24 × plot*.png           (300 DPI)
```

---

## 🎯 Optimization Strategies

| Strategy | Algorithm | Use Case | Coverage | Speed |
|----------|-----------|----------|----------|-------|
| **Quantile** | P5-P95 percentiles | Routine, robust | ~89% | ⚡⚡⚡ Fast |
| **Coverage** | Min range for 95% | Discovery, comprehensive | ~94% | ⚡⚡ Medium |
| **Outlier** | Mean ± 3σ | High-throughput, inclusive | ~99% | ⚡⚡ Medium |
| **Smoothing** | Savitzky-Golay | Publication, smooth transitions | ~88% | ⚡ Slower |

### Strategy Selection Guide

**For Routine Analysis**:
```r
windows <- optimize_windows(validated, plan, mz_strategy = "quantile")
```

**For Maximum Coverage**:
```r
windows <- optimize_windows(validated, plan, mz_strategy = "coverage", target_coverage = 0.98)
```

**For Publication/High Quality**:
```r
windows <- optimize_windows(validated, plan, mz_strategy = "smoothing")
```

---

## 🔧 Supported Instruments

| Instrument | Type | MS1 Time | MS2 Time | Scan Rate | Acquisition |
|------------|------|----------|----------|-----------|-------------|
| **Astral** | Orbitrap | 0.1 sec | 0.015 sec | 50-100 Hz | Parallel |
| **Exploris** | Orbitrap | 0.05 sec | 0.02 sec | 25-40 Hz | Sequential |
| **Orbitrap** | Traditional | 0.1 sec | 0.08 sec | 8-12 Hz | Sequential |
| **TimsTOF** | PASEF | 0.01 sec | 0.002 sec | 100 Hz | Parallel |
| **SCIEX** | ZenoTOF | 0.02 sec | 0.01 sec | 50 Hz | Sequential |
| **Waters** | SYNAPT | 0.05 sec | 0.02 sec | 20 Hz | Sequential |

**Usage**:
```r
plan <- plan_optimization(validated, current_cycle_time = 3.5,
                          instrument_preset = "astral",  # or "exploris", "orbitrap"
                          target_dppp = 7.0)
```

---

## 📊 DPPP Targets

**DPPP Formula**: `(1.7 × FWHM) / cycle_time`

| Target DPPP | Mode | Purpose | Window Count |
|-------------|------|---------|--------------|
| **7.0** | Quant | Quantification accuracy (recommended) | More windows |
| **4.0** | Balanced | Compromise | Medium |
| **1.5** | ID | Maximum identification | Fewer windows |

**Usage**:
```r
# Quant mode (recommended)
plan <- plan_optimization(validated, 3.5, "astral", target_dppp = 7.0)

# ID mode (discovery)
plan <- plan_optimization(validated, 3.5, "astral", target_dppp = 1.5)
```

---

## 📈 24-Plot Visualization Suite

### Current vs Optimized
- **Plot 1A/1B**: DPPP Distribution (Simple & Enhanced)

### Data Distribution
- **Plot 2**: RT × m/z Density Heatmap
- **Plot 2B**: RT Histogram (Continuous & 5-min binned)
- **Plot 3**: m/z Density Overlay by RT Segment

### Strategy Comparison
- **Plot 4 (A-D)**: m/z Excluded Regions (4 strategies)
- **Plot 4E**: m/z Width All Strategies Comparison
- **Plot 5**: Coverage Map 2×2 Grid (4 strategies)

### Optimization Quality
- **Plot 6**: Satisfaction vs Cycle Time Trade-off

### Window Characteristics
- **Plot 7 (×4)**: Width Distribution by Strategy
- **Plot 7B (×4)**: Window Index Width Bars by Strategy
- **Plot 8A**: Ridge Plot - Strategy Width Comparison
- **Plot 8B**: Box Plot - Statistical Summary
- **Plot 8C**: CDF - Cumulative Distribution

---

## 📁 Output Files

### Method Files (22-Column Thermo Format)

All method files are compatible with **Thermo Xcalibur** and contain:

1. **Thermo Template**: Compound, Formula, Adduct
2. **Mass Specs**: m/z, z (charge state)
3. **RT Windows**: t start/stop (minutes)
4. **Acquisition**: Isolation Window, AGC Target
5. **m/z Boundaries**: Start/End m/z
6. **Identifiers**: Window_ID, RT_Segment_ID
7. **RT Info**: RT_Center, RT_Width
8. **Quality**: N_Precursors (per window)
9. **Diagnostics**: Overlap_Prev/Next
10. **Metadata**: Instrument, Generation_Method, Window_Type
11. **Timing**: Recommended_Cycle_Time_Sec

**Import to Xcalibur**:
1. Open Method Editor
2. File → Import → Select CSV
3. Verify parameters
4. Save method

---

## 🧬 Technical Replicate Handling

### Automatic Detection & Processing

```r
validated <- create_validated_dataset(
  input_file = "data/30min_report.parquet",
  replicate_handling = "consensus",  # "representative", "average", "consensus", "none"
  cv_threshold = 0.30                # Filter high-variance features
)
```

**Methods**:
- **Representative**: Select best quality run
- **Average**: Arithmetic mean across replicates
- **Consensus**: Median ± geometric CV filtering (recommended)
- **None**: No replicate processing

**Geometric CV**: Correct statistical measure for log-normal proteomics data (see [docs/GEOMETRIC_CV_GUIDE.md](docs/GEOMETRIC_CV_GUIDE.md))

---

## 📚 Documentation

### User Guides
- **[USAGE_GUIDE.md](docs/USAGE_GUIDE.md)**: Comprehensive user guide with examples
- **[PRD.md](docs/PRD.md)**: Product requirements (Korean)
- **[CLAUDE.md](CLAUDE.md)**: Developer guide for Claude Code

### Technical Documentation
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)**: System architecture
- **[SMOOTHING_GLOBAL_VS_LOCAL.md](docs/SMOOTHING_GLOBAL_VS_LOCAL.md)**: Strategy comparison
- **[GEOMETRIC_CV_GUIDE.md](docs/GEOMETRIC_CV_GUIDE.md)**: CV calculation guide
- **[IMPROVEMENT_PLAN.md](IMPROVEMENT_PLAN.md)**: Roadmap and milestones

---

## 🔬 Scientific Background

### DPPP Methodology

Based on:
- **Doellinger et al. (2020)**: MSFragger-DIA quantification
- **Doellinger et al. (2023)**: DPPP optimization for DIA

**Key Insight**: DPPP (Data Points Per Peak) of 7.0 provides optimal quantification accuracy.

### RT-Dependent m/z Optimization

**Problem**: Peptides show RT-dependent m/z distribution

**Solution**: 4 optimization strategies (LOCAL vs GLOBAL)
- **LOCAL** (Quantile, Coverage, Outlier): Bin-specific optimization
- **GLOBAL** (Smoothing): Continuous function across gradient

See [docs/SMOOTHING_GLOBAL_VS_LOCAL.md](docs/SMOOTHING_GLOBAL_VS_LOCAL.md) for details.

---

## 🛠️ Architecture

### Streamlined 4-Stage Pipeline

```
┌─────────────────────────────────────────────────────────┐
│  Stage 1: Data Validation                              │
│    Input: DIA-NN parquet/TSV                           │
│    Output: ValidatedData                               │
│    File: R/stage1_data_validation.R                    │
├─────────────────────────────────────────────────────────┤
│  Stage 2: Optimization Planning                        │
│    Input: ValidatedData + current cycle time           │
│    Output: OptimizationPlan                            │
│    File: R/stage2_optimization_planning.R              │
├─────────────────────────────────────────────────────────┤
│  Stage 3: Window Optimization + Export                 │
│    Input: ValidatedData + OptimizationPlan             │
│    Strategies: quantile, coverage, outlier, smoothing  │
│    Export: export_method_files() for all strategies    │
│    Output: OptimizedWindows + method CSV files         │
│    File: R/stage3_window_optimization.R                │
├─────────────────────────────────────────────────────────┤
│  Stage 4: Visualization (Plots Only)                   │
│    Input: All previous outputs                         │
│    Output: 24 plots + PDF report                       │
│    File: R/stage4_visualization.R                      │
└─────────────────────────────────────────────────────────┘
```

**Design Principles**:
- **Single Responsibility**: Each stage has one clear purpose
- **Stage 3**: Data generation + export
- **Stage 4**: Visualization only (no data export)
- **Modularity**: Stages can be developed/tested independently

---

## ⚡ Performance

### Optimization Highlights

- **50-100× faster** precursor-window matching (vectorized operations)
- **42% code reduction** through refactoring
- **Single function call** for complete optimization
- **Batch export** for all strategies

### Benchmark Results (90min gradient, 27K precursors)

| Operation | Time | Output |
|-----------|------|--------|
| Stage 1: Validation | ~2 sec | ValidatedData |
| Stage 2: Planning | <1 sec | OptimizationPlan |
| Stage 3: Optimization (×4) | ~15 sec | 4 window sets |
| Stage 3: Export (×4) | ~2 sec | 4 method CSV files |
| Stage 4: Visualization | ~25 sec | 24 plots + PDF |
| **Total** | **~45 sec** | Complete analysis |

---

## 📖 Example Workflows

### Workflow 1: Quick Single Strategy

```r
validated <- create_validated_dataset("data/report.parquet")
plan <- plan_optimization(validated, 3.5, "astral", 7.0)
windows <- optimize_windows(validated, plan, 5, "quantile", "variable")
export_windows_to_csv(windows, "output/method.csv", validated, plan)
```

### Workflow 2: Comprehensive Multi-Strategy

```r
# See "Complete Workflow" section above
```

### Workflow 3: Batch Processing

```r
datasets <- c("30min", "60min", "90min")

for (name in datasets) {
  validated <- create_validated_dataset(sprintf("data/%s_report.parquet", name))
  plan <- plan_optimization(validated, 3.5, "astral", 7.0)

  windows_list <- list()
  for (strategy in c("quantile", "coverage", "outlier", "smoothing")) {
    windows_list[[strategy]] <- optimize_windows(validated, plan, 5, strategy, "variable")
  }

  output_dir <- sprintf("output/%s", name)
  export_method_files(windows_list, output_dir, validated, plan)
  viz <- generate_visualizations(validated, plan, windows_list[["smoothing"]],
                                  windows_list, output_dir, create_individual_plots = TRUE)
}
```

---

## 🔍 Troubleshooting

### Common Issues

**Low Coverage (<80%)**:
```r
# Use Coverage strategy
windows <- optimize_windows(validated, plan, mz_strategy = "coverage", target_coverage = 0.98)
```

**Too Many Windows**:
```r
# Wider RT bins
windows <- optimize_windows(validated, plan, rt_bin_width_min = 10)
```

**Smoothing Fails**:
```r
# Not enough RT bins - use different strategy
windows <- optimize_windows(validated, plan, mz_strategy = "quantile")
```

See [docs/USAGE_GUIDE.md](docs/USAGE_GUIDE.md) for detailed troubleshooting.

---

## 🤝 Contributing

This project is under active development. For questions or suggestions:

1. Check [USAGE_GUIDE.md](docs/USAGE_GUIDE.md)
2. Review [ARCHITECTURE.md](docs/ARCHITECTURE.md)
3. See [IMPROVEMENT_PLAN.md](IMPROVEMENT_PLAN.md) for roadmap

---

## 📜 License

This project is provided for research use.

---

## 🙏 Acknowledgments

- **DPPP Methodology**: Doellinger et al. (2020, 2023)
- **DIA-NN**: Demichev et al. (2020)
- **Geometric CV**: Kirkwood (2009)
- **Savitzky-Golay**: Savitzky & Golay (1964)

---

**Version**: 2.1
**Architecture**: Refactored (2025-11-20)
**Status**: Production Ready
