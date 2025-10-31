# Production-Ready Scripts Guide

**Version**: 2.1 (JSON Configuration System + Refactored Architecture)
**Last Updated**: 2025-10-29
**Status**: ✅ Production-Ready

---

## 🎯 Quick Start

### Main Entry Point

```r
# Production batch processing
source("run_with_config.R")
run_optimization("config/optimization_config.json")
```

This will generate:
- **3 input files** × **4 m/z strategies** × **2 window modes** = **24 CSV files**
- Complete method files for Thermo Orbitrap programming
- 22-column format including Recommended_Cycle_Time_Sec

---

## 📋 Production Scripts (4 Files in Root)

### 1. `run_with_config.R` ✅ MAIN ENTRY POINT

**Purpose**: Batch processing with JSON configuration

**Usage**:
```r
source("run_with_config.R")
run_optimization("config/optimization_config.json")
```

**Features**:
- Processes multiple DIA-NN files
- Applies all m/z strategies and window modes
- Generates batch summary CSV
- Full error handling and logging

**Output**: 24 CSV files + 1 summary

---

### 2. `validate_config.R` - Configuration Validator

**Purpose**: Validate JSON configuration before running

**Usage**:
```r
source("validate_config.R")
result <- validate_config_file("config/optimization_config.json")

if (result$valid) {
  cat("✅ Configuration is valid\n")
} else {
  cat("❌ Errors found:\n")
  print(result$errors)
}
```

**Checks**:
- Required fields present
- Valid value ranges
- File existence
- Instrument preset validity
- Logical consistency

---

### 3. `configure_pipeline.R` - Interactive Setup

**Purpose**: Interactive configuration file generator

**Usage**:
```r
source("configure_pipeline.R")
create_config_interactive()
```

**Features**:
- Guided setup with prompts
- Validates input in real-time
- Generates ready-to-use JSON config
- Lists available presets

---

### 4. `test_refactoring_quick.R` - Quick Smoke Test

**Purpose**: Fast verification of core functionality

**Usage**:
```r
source("test_refactoring_quick.R")
# Runs automatically, outputs to results_refactoring_quicktest/
```

**Tests**:
- Single file processing
- JSON config loading
- All 4 stages execution
- 22-column CSV generation

**Output**: 1 CSV file + console verification

---

## 🏗️ Core Modules (15 Files in R/)

### Stage 1: Data Validation
- `stage1_data_validation.R` - Main Stage 1 module
- `data_loader.R` - DIA-NN file loading (Parquet/TSV/CSV)
- `raw_metadata_extractor_improved.R` - Optional raw file metadata

### Stage 2: Optimization Planning
- `stage2_optimization_planning.R` - **Refactored v2.1**
  - Integrates DPPP diagnosis + window count
  - Reads max_windows from instruments.json
  - Calculates required cycle time

### Stage 3: Window Optimization
- `stage3_window_optimization.R` - **Refactored v2.1**
  - 4 m/z strategies: quantile, smoothing, outlier, coverage
  - 2 window modes: fixed, variable
  - Generates complete 22-column CSV

### Stage 4: Visualization & Reporting
- `stage4_visualization.R` - Plots and PDF reports

### Supporting Modules
- `dppp_calculator.R` - DPPP calculation engine
- `rt_segmentation.R` - Time-based RT binning
- `window_generator.R` - Variable window generation (Largest Remainder Method)
- `dynamicDIA.R` - Savitzky-Golay smoothing
- `method_writer.R` - CSV export
- `utils_common.R` - Common utilities

### Configuration System
- `config_loader.R` - JSON config loader & validator
- `instrument_utils.R` - Instrument management
- `visualizer.R` - Plotting helpers

---

## ⚙️ Configuration Files (9 Files in config/)

### Hardware Specifications (Immutable)
- `instruments.json` - **9 instrument presets**
  - Includes max_windows (hardware limit)
  - Thermo: Astral, Orbitrap, Exploris, Fusion Lumos
  - Bruker: TimsTOF, TimsTOF Pro
  - SCIEX: 7600
  - Waters: SYNAPT
  - Custom

### User Configuration (Mutable)
- `optimization_config.json` - Main user config
- `test_config.json` - Quick test config
- `optimization_config_template.json` - Template with comments

### Presets (4 Files)
- `presets/quant_mode_85pct.json` - DPPP 7.0, 85% satisfaction
- `presets/id_mode_70pct.json` - DPPP 1.5, 70% satisfaction
- `presets/fusion_lumos_standard.json` - Fusion Lumos specific
- `presets/astral_narrow_dia.json` - Astral narrow-DIA

---

## 🔄 Typical Workflow

### 1. Prepare Data
```bash
# Ensure DIA-NN output files are ready
data/
├── 30min_report.parquet
├── 60min_report.parquet
└── 90min_report.parquet
```

### 2. Configure
```r
# Option A: Use preset
cp config/presets/quant_mode_85pct.json config/my_config.json

# Option B: Create interactively
source("configure_pipeline.R")
create_config_interactive()

# Option C: Edit template
cp config/optimization_config_template.json config/my_config.json
# Edit my_config.json
```

### 3. Validate
```r
source("validate_config.R")
validate_config_file("config/my_config.json")
```

### 4. Run
```r
source("run_with_config.R")
run_optimization("config/my_config.json")
```

### 5. Results
```
results_my_project/
├── 30min_quantile_fixed_thermo.csv
├── 30min_quantile_variable_thermo.csv
├── 30min_smoothing_fixed_thermo.csv
├── ... (24 CSV files total)
└── batch_processing_summary.csv
```

---

## 📊 Output Format (22 Columns)

### Thermo-Compatible CSV

**Columns 1-11**: Thermo standard format
- Compound, Formula, Adduct, m/z, z
- t start (min), t stop (min)
- Isolation Window (m/z)
- Normalized AGC Target (%)
- Start (m/z), End (m/z)

**Columns 12-22**: Metadata & recommendations
- Window_ID, RT_Segment_ID, RT_Center, RT_Width
- N_Precursors, Overlap_Prev, Overlap_Next
- Instrument, Generation_Method, Window_Type
- **Recommended_Cycle_Time_Sec** (NEW in v2.1)

---

## ✅ Production Quality Checklist

Before deploying:

- ✅ All core modules in R/ folder (15 files)
- ✅ JSON configuration system (9 config files)
- ✅ Main entry point (run_with_config.R)
- ✅ Validation tools (validate_config.R)
- ✅ Quick smoke test passes
- ✅ Documentation up-to-date

---

## 🚫 What's NOT Production-Ready

**Avoid using**:
- Files in `scripts/` - Development/analysis only
- Files in `tests/development/` - Active development
- Files in `archive/` - Deprecated code

**Use instead**:
- Root folder: 4 production entry points
- R/ folder: 15 production modules
- config/ folder: 9 configuration files

---

## 📚 Documentation

- **DEVELOPMENT.md** - Development guide and phase status
- **CLAUDE.md** - Claude Code guidance
- **REFACTORING_SUMMARY.md** - v2.1 refactoring details
- **CLEANUP_SUMMARY.md** - Cleanup and organization history
- **PRODUCTION_SCRIPTS_ANALYSIS.md** - Script classification
- **CHANGELOG_2025-10-29.md** - Recent changes

---

## 🆘 Troubleshooting

### Config validation fails
```r
source("validate_config.R")
result <- validate_config_file("config/my_config.json")
print(result$errors)  # See specific errors
```

### Missing dependencies
```r
install.packages(c("arrow", "dplyr", "ggplot2", "gridExtra",
                   "jsonlite", "tidyr", "viridis", "scales",
                   "prospectr", "testthat"))
```

### Quick test
```r
source("test_refactoring_quick.R")
# Should generate 1 CSV in results_refactoring_quicktest/
```

---

**Version**: 2.1
**Status**: ✅ Production-Ready
**Total Production Files**: 28 (4 entry points + 15 modules + 9 configs)
