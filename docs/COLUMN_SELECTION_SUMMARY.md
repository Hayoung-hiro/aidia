# Column Selection - Automatic Memory Optimization
# DIA Window Optimizer v2.0

**Last Updated**: 2025-11-19
**Version**: Simplified Automatic System

---

## 🎯 Overview

**Automatic column selection** reduces memory usage by ~80% with **zero configuration required**.

- **Before**: ~40 columns from DIA-NN output (16 MB for 50K precursors)
- **After**: 5 essential + QC columns (3.2 MB for 50K precursors)
- **Savings**: 80% memory reduction, automatic

---

## ✅ Essential Columns (Always Kept)

| Column | Type | Usage | Alternatives |
|--------|------|-------|--------------|
| **Precursor.Id** | chr | Unique precursor identifier | - |
| **RT.Start** | num | Retention time (minutes) | RT (auto-renamed) |
| **Precursor.Mz** | num | m/z value (Da) | - |
| **FWHM** | num | Peak width (minutes) | - |
| **Protein.Group** | chr | Protein group annotation | Protein.Ids, Protein.Names |

---

## 📊 QC Columns (Kept if Present)

Added after technical replicate consensus in Stage 1:

- `n_replicates` - Number of replicates per precursor
- `RT_CV_pct` - RT coefficient of variation (%)
- `Mz_CV_pct` - m/z coefficient of variation (%)
- `FWHM_CV_pct` - FWHM coefficient of variation (%)
- `Intensity_CV_pct` - Intensity CV (geometric, if Precursor.Quantity present)

---

## 🔧 Implementation

### Automatic Selection (No Configuration)

```r
# Stage 1 automatically applies column selection
validated_data <- create_validated_dataset(
  proteome_file = "report.parquet"
)

# Columns automatically reduced from ~40 to 5-10
# No parameters needed
```

### What Gets Removed

**Removed from DIA-NN output**:
- `Q.Value` - Only for Stage 1 QC filtering
- `PG.MaxLFQ` - Not used in window optimization
- `Protein.Names` - Superseded by Protein.Group
- `Protein.Ids` - Superseded by Protein.Group
- `Genes` - Not used
- `Stripped.Sequence` - Not used
- `Modified.Sequence` - Not used (unless PTM workflow)
- `Precursor.Charge` - Not used (current pipeline)

---

## 📐 Memory Impact

### Example: 50,000 precursors

**DIA-NN Full Output** (~40 columns):
```
50,000 × 40 × 8 bytes = 16 MB
```

**After Automatic Selection** (5 essential + 3 QC):
```
50,000 × 8 × 8 bytes = 3.2 MB
```

**Memory Savings**: 12.8 MB (80% reduction)

---

## 🚀 Usage by Stage

### Stage 1: Data Validation
**Creates**: ValidatedData with 5-10 columns
**Removes**: ~30-35 unused columns automatically

### Stage 2: Optimization Planning
**Uses**: FWHM only (for DPPP calculation)

### Stage 3: Window Optimization
**Uses**: RT.Start, Precursor.Mz (for binning and m/z ranges)

### Stage 4: Visualization
**Uses**: RT.Start, Precursor.Mz, FWHM (for plots)
**Uses**: Protein.Group (for protein-level summaries)

---

## 🔄 Alternative Column Names

### Auto-Renamed Columns

If alternative names are found, they are automatically renamed to standard names:

| Standard | Alternatives |
|----------|--------------|
| RT.Start | RT, Retention.Time, RT_Start |
| Protein.Group | Protein.Ids, Protein.Names |

**Example**:
```r
# Input has "Protein.Names" instead of "Protein.Group"
# → Automatically renamed to "Protein.Group"
# → No user action needed
```

---

## 📝 Design Rationale

### Why RT.Start (not RT)?

**Analysis**: Code base consistently uses `RT.Start` across all stages
- Stage 3: `segment_rt_by_time_unit(data$RT.Start)`
- Stage 4: `plot_rt_distribution(data$RT.Start)`
- DIA-NN standard output column name

**Conclusion**: `RT.Start` is the established standard

### Why Protein.Group?

**User Request**: Enable protein-level identification and tracking
**Usage**: Protein-level summaries, filtering, annotation
**Alternatives**: Auto-detects and renames Protein.Ids or Protein.Names

---

## 🎓 Comparison: Complex vs Simple

### Previous Complex System (Rejected)

```r
# 4 modes, configuration required
column_selection_mode = "standard"  # minimal, standard, full, custom
additional_columns = c("Precursor.Charge")  # For custom mode

# Config file
{
  "column_selection_mode": "standard",
  "additional_columns": ["Modified.Sequence"]
}
```

**Problems**:
- User must understand 4 modes
- Configuration complexity
- 500 lines of code, 47 tests
- YAGNI violation (You Aren't Gonna Need It)

### Current Simple System (Implemented)

```r
# Zero configuration
validated_data <- create_validated_dataset("report.parquet")
# Done - automatic column selection applied
```

**Benefits**:
- Zero configuration
- Same 80% memory savings
- 150 lines of code
- Always works the same way
- Simple to understand and maintain

---

## 🔮 Future Extensions

### PTM-Specific Workflow

**If needed in future**:
```r
# Add Modified.Sequence to ESSENTIAL_COLUMNS
ESSENTIAL_COLUMNS <- c(
  "Precursor.Id", "RT.Start", "Precursor.Mz", "FWHM",
  "Protein.Group", "Modified.Sequence"  # For PTM analysis
)
```

**Change location**: Edit `R/column_selection_simple.R` line 20

### Ion Mobility (timsTOF)

**If needed in future**:
```r
# Add IM column for ion mobility
ESSENTIAL_COLUMNS <- c(
  "Precursor.Id", "RT.Start", "Precursor.Mz", "FWHM",
  "Protein.Group", "IM"  # For timsTOF 4D-DIA
)
```

**When needed**: Actual 4D-DIA window optimization implementation

---

## ✅ Verification

### Check Column Selection Results

```r
# After Stage 1
validated_data <- create_validated_dataset("report.parquet")

# Check metadata
validated_data$metadata$column_selection
# $n_columns_before: 40
# $n_columns_after: 8
# $n_removed: 32
# $columns_kept: c("Precursor.Id", "RT.Start", ...)
```

### Verify Essential Columns

```r
# Check essential columns present
colnames(validated_data$data)
# [1] "Precursor.Id"  "RT.Start"       "Precursor.Mz"
# [4] "FWHM"          "Protein.Group"  "n_replicates"
# [7] "RT_CV_pct"     "FWHM_CV_pct"
```

---

**Version**: 2.0 (Simplified Automatic)
**Last Updated**: 2025-11-19
**Principles Applied**: YAGNI, KISS, Automatic Configuration
