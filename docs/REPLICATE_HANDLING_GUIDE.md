# Technical Replicate Handling Guide
# DIA Window Optimizer v2.0

**Last Updated**: 2025-11-18
**Version**: 2.0
**Status**: Production Ready

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [How Replicate Detection Works](#how-replicate-detection-works)
3. [DIA-NN Output Structure](#dia-nn-output-structure)
4. [Consensus Algorithm](#consensus-algorithm)
5. [Usage Examples](#usage-examples)
6. [Configuration](#configuration)
7. [Quality Control](#quality-control)
8. [Troubleshooting](#troubleshooting)
9. [Scientific Background](#scientific-background)

---

## Overview

### What is Technical Replicate Handling?

Technical replicate handling allows the optimizer to:
- **Auto-detect** multiple runs from DIA-NN output
- **Create consensus** datasets using median-based robust statistics
- **Filter low-quality** precursors using geometric CV thresholds
- **Preserve singletons** to prevent data loss

### When to Use It?

✅ **Use replicate handling when**:
- You have multiple LC-MS runs of the same sample (technical replicates)
- DIA-NN analyzed multiple raw files together
- You want to improve data quality through consensus

❌ **Don't use it when**:
- You have a single run
- You want to analyze runs separately (disable with `enable_replicate_consensus = FALSE`)
- Your data doesn't have a `Run` column

---

## How Replicate Detection Works

### Detection Mechanism

The optimizer uses a **simple and robust** approach:

```r
# Step 1: Check if "Run" column exists
has_run_column <- "Run" %in% colnames(data)

# Step 2: Count unique runs
if (has_run_column) {
  n_runs <- length(unique(data$Run))
} else {
  n_runs <- 1  # Treat as single run
}

# Step 3: Determine replicate type
if (n_runs > 1) {
  # Technical replicates detected
  # → Create consensus dataset
} else {
  # Single run
  # → Use original data
}
```

### Why the "Run" Column?

DIA-NN **automatically creates** a `Run` column when analyzing multiple raw files:

```
# Example DIA-NN command
diann.exe \
  --f "sample_run1.raw" \
  --f "sample_run2.raw" \
  --f "sample_run3.raw" \
  --out "report.parquet"

# Result: report.parquet contains Run column
# Run values: "sample_run1", "sample_run2", "sample_run3"
```

---

## DIA-NN Output Structure

### Standard DIA-NN Report Columns

**Required columns** for window optimization:
- `RT.Start` - Retention time start (minutes)
- `Precursor.Mz` - m/z value (Da)
- `FWHM` - Full width at half maximum (minutes)

**Additional columns** for replicate handling:
- `Run` - Run identifier (file name or custom ID)
- `Precursor.Id` - Unique precursor identifier (required for consensus)
- `Q.Value` - Precursor-level q-value (for quality filtering)
- `PG.Q.Value` - Protein group q-value

### Example Data Structure

#### Single Run (n=1)
```
   RT.Start  Precursor.Mz   FWHM  Precursor.Id         Run
1    10.5        400.5      0.45  PEPTIDE_1      sample.raw
2    20.3        500.2      0.52  PEPTIDE_2      sample.raw
3    30.1        600.8      0.48  PEPTIDE_3      sample.raw
```

#### Three Technical Replicates (n=3)
```
   RT.Start  Precursor.Mz   FWHM  Precursor.Id         Run
1    10.5        400.5      0.45  PEPTIDE_1      sample_run1.raw
2    10.6        400.6      0.47  PEPTIDE_1      sample_run2.raw
3    10.4        400.4      0.46  PEPTIDE_1      sample_run3.raw
4    20.3        500.2      0.52  PEPTIDE_2      sample_run1.raw
5    20.5        500.3      0.55  PEPTIDE_2      sample_run2.raw
6    30.1        600.8      0.48  PEPTIDE_3      sample_run1.raw  # Singleton (only 1 run)
```

**After Consensus**:
```
   RT.Start  Precursor.Mz   FWHM  n_replicates  RT_CV_pct  FWHM_CV_pct
1    10.5        400.5      0.46      3            1.0         2.2
2    20.4        500.25     0.535     2            0.7         2.8
3    30.1        600.8      0.48      1            NA          NA
```

---

## Consensus Algorithm

### Three-Step Process

#### Step 1: Calculate CV% on Original Replicates

For each precursor, calculate geometric CV across all replicate runs:

```r
cv_stats <- data %>%
  group_by(Precursor.Id) %>%
  summarise(
    n_replicates = n(),
    RT_CV_pct = if (n() >= 2) geometric_cv(RT.Start) else NA_real_,
    FWHM_CV_pct = if (n() >= 2) geometric_cv(FWHM) else NA_real_
  )
```

**Geometric CV Formula**:
```r
geometric_cv <- function(x) {
  log_x <- log(x)
  sigma_log <- sd(log_x)
  sqrt(exp(sigma_log^2) - 1) * 100
}
```

**Why Geometric CV?**
See [GEOMETRIC_CV_GUIDE.md](GEOMETRIC_CV_GUIDE.md) for scientific rationale.

---

#### Step 2: Calculate Median Consensus Values

Use **median** (not mean) for robustness to outliers:

```r
consensus_values <- data %>%
  group_by(Precursor.Id) %>%
  summarise(
    RT.Start = median(RT.Start, na.rm = TRUE),
    Precursor.Mz = median(Precursor.Mz, na.rm = TRUE),
    FWHM = median(FWHM, na.rm = TRUE)
  )
```

**Why Median?**
- Robust to single bad runs
- Not affected by outliers
- Standard in proteomics

---

#### Step 3: Filter by CV% Threshold

Remove precursors with high FWHM variability:

```r
filtered <- consensus %>%
  filter(
    n_replicates >= min_replicates,
    (n_replicates == 1 | FWHM_CV_pct <= max_cv_percent)
  )
```

**Key Rule**: **Singletons always kept** (n_replicates == 1)
- Prevents data loss
- CV cannot be calculated for n=1
- Users can filter later if needed

---

## Usage Examples

### Example 1: Basic Usage with 3 Replicates

```r
library(dplyr)
source("R/stage1_data_validation.R")

# Load data with auto-detection
validated <- create_validated_dataset(
  proteome_file = "data/30min_3runs_report.parquet",
  enable_replicate_consensus = TRUE,
  max_cv_percent = 20
)

# Check results
validated$metadata$n_runs                    # 3
validated$metadata$n_precursors_before       # e.g., 15000 (5000 × 3 runs)
validated$metadata$n_precursors_after        # e.g., 4200 (after consensus + CV filter)
validated$metadata$n_singleton               # e.g., 300 (only in 1 run)
validated$metadata$n_replicated              # e.g., 3900 (in ≥2 runs)
validated$metadata$n_filtered_cv             # e.g., 800 (CV% > 20%)
validated$metadata$mean_fwhm_cv_pct          # e.g., 8.5%
```

---

### Example 2: Diagnostic Before Processing

**Use diagnostic script** to analyze your data structure:

```r
source("scripts/diagnostics/diagnose_replicate_detection.R")

# Run diagnostic
result <- diagnose_replicate_structure("data/report.parquet")

# Review output
# - Detects n_runs
# - Shows replicate distribution
# - Estimates CV filtering impact
# - Provides recommendations
```

**Example Output**:
```
╔═══════════════════════════════════════════════════════╗
║   Replicate Detection Diagnostic Report             ║
╚═══════════════════════════════════════════════════════╝

Step 1: Loading data...
✓ Loaded 15000 rows, 25 columns

Step 2: Checking for Run column...
✓ 'Run' column found

Step 3: Analyzing Run structure...
✓ Detected 3 unique run(s)

  Replicate Type: Technical Replicates

Step 4: Analyzing replicate distribution...
  Precursors per run:
    sample_30min_run1.raw: 5200 precursors
    sample_30min_run2.raw: 5100 precursors
    sample_30min_run3.raw: 4700 precursors

Step 6: Analyzing precursor overlap across runs...
  Total unique precursors: 5000
  Singletons (1 run): 300 (6.0%)
  Replicated (≥2 runs): 4700 (94.0%)

  Replicate distribution:
    1 runs: 300 precursors (6.0%)
    2 runs: 800 precursors (16.0%)
    3 runs: 3900 precursors (78.0%)

Step 7: Estimating consensus impact...
  Sample CV statistics (n=100 precursors with ≥2 runs):
    Mean FWHM CV: 8.3%
    Median FWHM CV: 6.5%
    Would filter at CV>20%: 12 (12.0%)
    Would filter at CV>10%: 35 (35.0%)

Step 8: Recommendation
  ✅ Technical replicates detected
  ✅ Consensus creation recommended
  ✅ Expected output: ~5000 unique precursors

  Suggested parameters:
    enable_replicate_consensus = TRUE
    min_replicates = 1  # Include singletons
    max_cv_percent = 20  # Standard threshold
```

---

### Example 3: Single Run (Auto-Detected)

```r
# Single run data - consensus automatically disabled
validated <- create_validated_dataset(
  proteome_file = "data/single_run_report.parquet",
  enable_replicate_consensus = TRUE  # Still enabled, but auto-skipped
)

# Result
validated$metadata$n_runs  # 1
# No CV columns added
# Original data preserved
```

**Console Output**:
```
Step 4: Checking for technical replicates...
✓ Detected 1 run(s)
  → Single run detected - skipping consensus
```

---

### Example 4: Manual Disable

```r
# Keep all runs separate (no consensus)
validated <- create_validated_dataset(
  proteome_file = "data/30min_3runs_report.parquet",
  enable_replicate_consensus = FALSE  # Disabled
)

# Result
validated$metadata$n_runs  # 3
nrow(validated$data)       # 15000 (all rows kept)
# Each run analyzed separately downstream
```

---

### Example 5: Strict CV Filtering

```r
# Use stricter CV threshold
validated <- create_validated_dataset(
  proteome_file = "data/report.parquet",
  enable_replicate_consensus = TRUE,
  max_cv_percent = 10  # Strict (default: 20)
)

# Result: More precursors filtered
# Higher data quality, lower retention
```

---

## Configuration

### Via R Function Arguments

```r
create_validated_dataset(
  proteome_file = "report.parquet",

  # Replicate parameters
  enable_replicate_consensus = TRUE,  # Enable/disable
  min_replicates = 1,                 # Minimum n (usually 1)
  max_cv_percent = 20,                # CV% threshold

  # Other parameters
  apply_quality_filters = TRUE,
  quality_threshold = 0.8
)
```

### Via JSON Configuration File

**File**: `config/optimization_config.json`

```json
{
  "input_data": {
    "input_files": ["data/30min_report.parquet"],

    "enable_replicate_consensus": true,
    "min_replicates": 1,
    "max_cv_percent": 20
  }
}
```

**Load config**:
```r
config <- jsonlite::fromJSON("config/optimization_config.json")

validated <- create_validated_dataset(
  proteome_file = config$input_data$input_files[1],
  enable_replicate_consensus = config$input_data$enable_replicate_consensus,
  max_cv_percent = config$input_data$max_cv_percent
)
```

---

## Quality Control

### Metadata for QC

**Replicate-specific metadata** in `ValidatedData$metadata`:

| Field | Description | Typical Value |
|-------|-------------|---------------|
| `n_runs` | Number of runs detected | 1-10 |
| `n_precursors_before` | Total rows before consensus | 15000 |
| `n_precursors_unique` | Unique precursors | 5000 |
| `n_precursors_after` | After consensus + CV filter | 4200 |
| `n_singleton` | Precursors in 1 run only | 300 (6%) |
| `n_replicated` | Precursors in ≥2 runs | 3900 (78%) |
| `n_filtered_cv` | Filtered by CV threshold | 800 (16%) |
| `mean_rt_cv_pct` | Mean RT CV% | 5-10% |
| `mean_fwhm_cv_pct` | Mean FWHM CV% | 8-12% |

### CV Columns in Consensus Data

**Added columns** when `n_runs > 1`:
- `n_replicates` - Number of runs for this precursor
- `RT_CV_pct` - RT geometric CV%
- `Mz_CV_pct` - m/z geometric CV%
- `FWHM_CV_pct` - FWHM geometric CV%

### QC Recommendations

**Good Quality Indicators**:
- ✅ Mean FWHM CV < 15%
- ✅ Singleton ratio < 10%
- ✅ Replicate ratio (n≥3) > 70%
- ✅ Filtered ratio < 20%

**Warning Signs**:
- ⚠️ Mean FWHM CV > 25% (poor run-to-run consistency)
- ⚠️ Singleton ratio > 30% (poor overlap)
- ⚠️ Filtered ratio > 40% (too much variability)

**Actions**:
- Check LC gradient reproducibility
- Inspect raw file quality
- Consider re-running samples
- Adjust CV threshold if appropriate

---

## Troubleshooting

### Problem 1: "No Run column found"

**Symptom**:
```
Step 4: Checking for technical replicates...
✓ No Run column - treating as single run
```

**Cause**: DIA-NN analyzed single file, or Run column not exported.

**Solutions**:
1. **Check DIA-NN command**: Ensure multiple files analyzed together
2. **Check output format**: Some export formats may drop Run column
3. **Use diagnostic**: Run `diagnose_replicate_structure()` to see available columns

---

### Problem 2: Too Many Precursors Filtered

**Symptom**:
```
✓ Consensus: 15000 → 2000 precursors (filtered 3000 by CV)
```

**Cause**: High CV threshold filtering (60% filtered).

**Solutions**:
1. **Increase CV threshold**: Try `max_cv_percent = 30` or `40`
2. **Check run quality**: Inspect individual runs for problems
3. **Review FWHM distribution**: Use diagnostic script
4. **Accept if appropriate**: Some experiments have high natural variability

---

### Problem 3: Singletons Too High

**Symptom**: `n_singleton / n_precursors_unique > 30%`

**Cause**: Poor precursor overlap between runs.

**Possible Reasons**:
- Different LC gradients
- Different MS settings
- Sample degradation
- Stochastic sampling

**Solutions**:
1. **Check experimental consistency**: Ensure identical LC/MS methods
2. **Inspect raw files**: Look for systematic differences
3. **Adjust DIA-NN parameters**: May improve identification consistency
4. **Accept if expected**: Some biological variability is normal

---

### Problem 4: Consensus Dataset Too Small

**Symptom**: Expected 5000 precursors, got 1000.

**Debug Steps**:
```r
# 1. Run diagnostic
result <- diagnose_replicate_structure("data/report.parquet")
print(result$replicate_info)

# 2. Check filtering
validated <- create_validated_dataset(
  "data/report.parquet",
  max_cv_percent = 100  # Disable CV filtering
)
# How many now? If much higher, CV filtering is the issue.

# 3. Check min_replicates
validated <- create_validated_dataset(
  "data/report.parquet",
  min_replicates = 1  # Include singletons (default)
)
```

---

## Scientific Background

### Why Median Instead of Mean?

**Median properties**:
- ✅ Robust to outliers (one bad run doesn't skew result)
- ✅ Standard in proteomics consensus
- ✅ Works well with log-normal distributions

**Example**:
```r
# Three replicates with one outlier
rt_values <- c(10.0, 10.1, 15.0)  # Third run is bad

mean(rt_values)    # 11.7 (skewed by outlier)
median(rt_values)  # 10.1 (robust - correct value)
```

### Why Geometric CV?

**Reference**: [GEOMETRIC_CV_GUIDE.md](GEOMETRIC_CV_GUIDE.md)

**Key Points**:
- Proteomics data follows **log-normal distribution**
- Base CV on log-transformed data → 14× underestimation
- Geometric CV = `sqrt(exp(sd(log(x))^2) - 1) * 100`
- Provides accurate variability measurement

**Do NOT do this**:
```r
# WRONG - Massive underestimation
log_fwhm <- log(fwhm)
wrong_cv <- sd(log_fwhm) / mean(log_fwhm) * 100  # ❌ Wrong!
```

**Correct approach**:
```r
# CORRECT - Geometric CV
geometric_cv <- function(x) {
  log_x <- log(x)
  sigma_log <- sd(log_x)
  sqrt(exp(sigma_log^2) - 1) * 100  # ✅ Correct!
}
```

### Why FWHM for CV Filtering?

**FWHM = Full Width at Half Maximum**
- Direct indicator of peak quality
- Affected by chromatographic performance
- Correlated with quantification accuracy

**High FWHM CV → Poor run-to-run consistency**:
- Could indicate: LC issues, sample degradation, MS variability
- Filtering improves downstream quality

---

## Advanced Topics

### Custom Replicate Column

**If your data uses a different column name**:

Currently, the code hardcodes `"Run"`. To use a custom column:

```r
# Modify data before processing
data <- read_parquet("report.parquet")

# Rename your custom column to "Run"
data <- data %>%
  rename(Run = YourCustomColumn)

# Save temporarily
write_parquet(data, "temp_report.parquet")

# Process
validated <- create_validated_dataset("temp_report.parquet")
```

**Future enhancement**: Could add `run_column` parameter to `create_validated_dataset()`.

---

### Biological vs Technical Replicates

**Current implementation assumes technical replicates**:
- Same sample, multiple LC-MS runs
- Expect high overlap and low CV

**For biological replicates**:
- Different samples (e.g., different patients)
- Expect lower overlap and higher CV
- **Not recommended** to use consensus
- Analyze separately or use statistical methods

---

## Summary

### Quick Decision Guide

```
Do you have multiple runs?
├─ YES → Check Run column exists?
│         ├─ YES → Enable consensus (default)
│         └─ NO → Add Run column or treat as single run
│
└─ NO → Disable consensus or auto-detected as single run
```

### Default Recommendations

**For most users**:
```r
enable_replicate_consensus = TRUE   # Auto-detect and handle
min_replicates = 1                 # Keep singletons
max_cv_percent = 20                # Standard QC threshold
```

**For high-quality data only**:
```r
max_cv_percent = 10  # Stricter filtering
```

**For exploratory analysis**:
```r
max_cv_percent = 100  # Disable CV filtering
```

---

**Version**: 2.0
**Last Updated**: 2025-11-18
**Authors**: DIA Window Optimizer Team
**License**: MIT
