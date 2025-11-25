# Interactive Configuration Builder Guide

## Overview

The **Interactive Configuration Builder** (`scripts/config_builder.R`) is a user-friendly tool that creates YAML/JSON configuration files through a step-by-step Q&A interface.

**Key Features**:
- ✅ **No dependencies**: Uses base R only (no additional packages required)
- ✅ **Auto-detection**: Automatically finds parquet files in data directory
- ✅ **Input validation**: Real-time validation with helpful error messages
- ✅ **Smart defaults**: Sensible defaults for all parameters
- ✅ **Immediate execution**: Option to run optimization pipeline after config creation
- ✅ **Flexible output**: Supports both YAML and JSON formats

---

## Quick Start

### 1. Launch Interactive Builder

```r
# From R console
source("scripts/config_builder.R")

# Create YAML configuration (recommended)
config <- run_config_builder(format = "yaml")

# Or create JSON configuration
config <- run_config_builder(format = "json")

# Create and run immediately
config <- run_config_builder(format = "yaml", run_immediately = TRUE)
```

### 2. Follow the Prompts

The builder will guide you through **9 sections**:

1. **Project Metadata** - Project name, date, analyst
2. **Input Data** - Parquet files, cycle time, replicate handling
3. **Instrument** - Preset selection (Fusion Lumos, Astral, etc.)
4. **DPPP Parameters** - Target mode (Quant 7.0, ID 1.5, Custom)
5. **Scan Settings** - Load factor, warning thresholds
6. **RT Binning** - Time bin width (default: 5 min)
7. **m/z Strategies** - Quantile, Smoothing, Outlier, Coverage
8. **Window Generation** - Variable, Fixed, or Both modes
9. **Output Options** - Directory, plots, summary report

### 3. Review and Save

The builder will:
- Display configuration summary
- Save to specified file path
- Optionally run optimization immediately

---

## Usage Examples

### Example 1: Standard Quant Mode (70% Satisfaction)

```r
source("scripts/config_builder.R")
run_config_builder(format = "yaml")

# User inputs:
# - Project name: Fusion_Lumos_Quant_70pct
# - Data directory: data (auto-detects 30min/60min/90min_report.parquet)
# - Instrument: [1] fusion_lumos
# - DPPP mode: [1] Quant Mode (7.0)
# - Target satisfaction: 0.70
# - Strategies: all
# - Window mode: [1] variable
# - Run now? n

# Output: config/config_Fusion_Lumos_Quant_70pct.yaml
```

**Generated YAML**:
```yaml
project_metadata:
  project_name: "Fusion_Lumos_Quant_70pct"
  date: "2025-11-17"
  analyst: "user"
  description: ""

input_data:
  input_files:
    - "data/30min_report.parquet"
    - "data/60min_report.parquet"
    - "data/90min_report.parquet"
  current_cycle_time: null
  enable_replicate_consensus: true
  min_replicates: 1
  max_intensity_cv_percent: 30

instrument:
  preset: "fusion_lumos"
  custom_settings: null

dppp_parameters:
  target_dppp: 7.0
  target_satisfaction: 0.70
  dppp_tolerance: 0.0

scan_settings:
  load_factor: 0.8
  ms1_scans_per_cycle: null
  warning_threshold_windows: 5

rt_binning:
  rt_bin_width_min: 5.0

mz_optimization:
  strategies:
    - "quantile"
    - "smoothing"
    - "outlier"
    - "coverage"
  quantile_lower: 0.05
  quantile_upper: 0.95
  target_coverage: 0.95
  outlier_threshold: 3.0
  smoothing_window: 3
  polynomial_order: 2

window_generation:
  modes:
    - "variable"
  min_width_da: 2
  max_width_da: 80
  overlap_percentage: 0

output:
  output_dir: "results"
  include_summary: true
  include_plots: true
```

### Example 2: ID Mode for Maximum Precursor Identification

```r
source("scripts/config_builder.R")
run_config_builder(format = "yaml")

# User inputs:
# - Project name: Astral_ID_Mode_85pct
# - Instrument: [5] astral
# - DPPP mode: [2] ID Mode (1.5)
# - Target satisfaction: 0.85
# - Strategies: 1,2 (quantile, smoothing)
# - Window mode: [3] both
```

**Key Differences**:
- `target_dppp: 1.5` (more precursors per window)
- `target_satisfaction: 0.85` (higher threshold)
- `strategies: ["quantile", "smoothing"]` (subset)
- `modes: ["variable", "fixed"]` (both modes)

### Example 3: Quick Test Run (No Plots)

```r
source("scripts/config_builder.R")
run_config_builder(format = "yaml", run_immediately = TRUE)

# User inputs:
# - Accept all defaults (press Enter)
# - Generate visualizations? n
# - Run now? y (or already set via run_immediately = TRUE)
```

**Benefits**:
- Fast execution (skip 24 plots generation)
- Quick validation of settings
- Immediate feedback on window optimization

---

## Input Validation

The builder validates all inputs in real-time:

### Numeric Validation

```
RT bin width (minutes) [default: 5.0]: abc
  ⚠️  Please enter a valid number

RT bin width (minutes) [default: 5.0]: 0.5
  ⚠️  Must be >= 1.0

RT bin width (minutes) [default: 5.0]: 5.0
✅ Accepted
```

### File Validation

```
  Found 3 parquet file(s):
    [1] 30min_report.parquet
    [2] 60min_report.parquet
    [3] 90min_report.parquet

Use all detected files? [default: y]: y
✅ Using 3 files
```

### Choice Validation

```
Select DPPP mode [default: 1]: 5
  ⚠️  Invalid choice. Enter 1-4

Select DPPP mode [default: 1]: 1
✅ Quant Mode (7.0) selected
```

---

## Default Values

The builder provides sensible defaults based on best practices:

| Parameter | Default | Rationale |
|-----------|---------|-----------|
| **Target DPPP** | 7.0 | Optimal quantification accuracy |
| **Target Satisfaction** | 0.70 | 70% precursors meet target DPPP |
| **Load Factor** | 0.8 | 80% instrument capacity utilization |
| **RT Bin Width** | 5.0 min | Balance between adaptivity and stability |
| **m/z Strategies** | All 4 | Comprehensive comparison |
| **Window Mode** | Variable | Density-adaptive (recommended) |
| **Min Width** | 2 Da | Narrow-DIA compatible (Astral) |
| **Max Width** | 80 Da | Prevent excessively wide windows |
| **Include Plots** | Yes | Full visualization suite |

**Quick Start Tip**: Press Enter repeatedly to accept all defaults for standard Quant mode optimization.

---

## Advanced Features

### 1. Custom Cycle Time

```
Auto-estimate cycle time from gradient length? [default: y]: n
Current cycle time (seconds) [default: 1.5]: 2.0
```

**When to use**:
- Known cycle time from existing method
- Benchmarking different cycle times
- Fixed instrument configuration

### 2. Technical Replicate Consensus

```
Enable technical replicate consensus? [default: y]: y
```

**What it does**:
- Auto-detects multiple runs from `Run` column
- Computes median FWHM across replicates
- Filters by intensity CV% (default: 30%)
- Improves robustness of window optimization

**See**: [docs/GEOMETRIC_CV_GUIDE.md](GEOMETRIC_CV_GUIDE.md) for CV calculation details

### 3. Multiple m/z Strategies

```
Select strategies: all
```

**Generates**:
- 4 strategies × 1 mode = 4 method files per gradient
- Comparative plots (Plot 8: Ridge/Box/CDF)
- Batch processing summary table

**Strategy Comparison**:
- **Quantile**: Fast, robust (14-16 Da)
- **Smoothing**: Smooth RT boundaries (15-17 Da)
- **Outlier**: Maximum coverage (18-20 Da, 97%)
- **Coverage**: Balanced (17 Da, 95%)

### 4. Output Customization

```
Output directory [default: results]: custom_output
Generate visualizations (24 plots)? [default: y]: y
Generate summary report? [default: y]: y
```

**Output Structure**:
```
custom_output/
├── 30min/
│   ├── quantile_variable_method.csv
│   ├── smoothing_variable_method.csv
│   ├── outlier_variable_method.csv
│   ├── coverage_variable_method.csv
│   ├── plot01_dppp_density_distribution.png
│   ├── plot02_rt_window_allocation.png
│   ├── ... (24 plots total)
│   └── optimization_report.pdf
├── 60min/ (same structure)
├── 90min/ (same structure)
└── batch_processing_summary.csv
```

---

## Troubleshooting

### Issue: No parquet files found

```
⚠️  No parquet files found in directory
```

**Solution**:
1. Check data directory path
2. Ensure files have `.parquet` extension
3. Manually enter file paths when prompted

### Issue: jsonlite package not found (JSON format)

```
Error: jsonlite package required for JSON export
```

**Solution**:
```r
install.packages("jsonlite")
# Or use YAML format instead
run_config_builder(format = "yaml")
```

### Issue: Configuration validation fails

**Check**:
- DPPP range: 1.0 - 15.0
- Satisfaction ratio: 0.5 - 0.95
- RT bin width: 1.0 - 30.0 min
- Window width: min < max

---

## YAML vs JSON

### YAML (Recommended)

**Pros**:
- ✅ Human-readable, clean syntax
- ✅ No dependencies (base R implementation)
- ✅ Comments supported
- ✅ Standard for configuration files

**Cons**:
- ⚠️ Indentation-sensitive

**Use when**: Default choice for all users

### JSON

**Pros**:
- ✅ Strict validation
- ✅ Wide tool support
- ✅ Machine-readable

**Cons**:
- ⚠️ Requires `jsonlite` package
- ⚠️ Verbose syntax (brackets, quotes)
- ⚠️ No comments

**Use when**: Integration with JSON-based tools

---

## Running Optimization from Config

### Method 1: During Builder Session

```r
run_config_builder(format = "yaml", run_immediately = TRUE)
# Pipeline starts automatically after config creation
```

### Method 2: Later Execution

```r
source("run_with_config.R")
results <- run_optimization("config/my_config.yaml")
```

### Method 3: Batch Processing

```r
# Create multiple configs
configs <- c(
  "config/quant_70pct.yaml",
  "config/quant_85pct.yaml",
  "config/id_mode.yaml"
)

# Run all
source("run_with_config.R")
for (cfg in configs) {
  cat(sprintf("\nProcessing: %s\n", cfg))
  results <- run_optimization(cfg)
}
```

---

## Integration with Main Pipeline

The config builder creates files compatible with:

1. **run_with_config.R** - JSON/YAML-based batch processing
2. **main.R** - Standard pipeline (can extract parameters)
3. **Custom scripts** - Use config list programmatically

**Example**:
```r
# Build config
source("scripts/config_builder.R")
config <- run_config_builder(format = "yaml")

# Extract parameters for main.R
source("main.R")
results <- run_complete_pipeline(
  data_dir = dirname(config$input_data$input_files[1]),
  instrument_preset = config$instrument$preset,
  target_dppp = config$dppp_parameters$target_dppp,
  target_satisfaction = config$dppp_parameters$target_satisfaction,
  mz_strategies = config$mz_optimization$strategies,
  window_mode = config$window_generation$modes[1],
  create_plots = config$output$include_plots
)
```

---

## Best Practices

### 1. Start with Defaults

For first-time users:
```r
source("scripts/config_builder.R")
run_config_builder()
# Press Enter repeatedly to accept defaults
```

### 2. Save Configurations

Keep config files for reproducibility:
```
config/
├── production/
│   ├── quant_70pct.yaml
│   └── id_85pct.yaml
├── testing/
│   └── quick_test.yaml
└── archive/
    └── 2025-11-17_fusion_lumos.yaml
```

### 3. Document Custom Settings

Add descriptive project names and descriptions:
```
Project name: Fusion_Lumos_Narrow_DIA_2Da_Quant_70pct
Description: Narrow-DIA method for Fusion Lumos with 2 Da windows
```

### 4. Version Control

Track configuration files in Git:
```bash
git add config/production/*.yaml
git commit -m "Add production DIA optimization configs"
```

---

## Future Enhancements

Planned features for next version:

- 🔮 **Preset templates**: Load pre-configured settings for common use cases
- 🔮 **Batch mode**: Create multiple configs via CSV input
- 🔮 **GUI integration**: Link to Shiny app for visual workflow
- 🔮 **Config validation**: Pre-flight checks before optimization
- 🔮 **Parameter recommendations**: AI-suggested settings based on data characteristics

---

## Support

For issues or questions:
1. Check this guide and [CLAUDE.md](../CLAUDE.md)
2. Review example configs in `config/` directory
3. Run with verbose output for debugging
4. Open GitHub issue with config file and error message

---

**Version**: 1.0
**Last Updated**: 2025-11-17
**Status**: Production Ready
