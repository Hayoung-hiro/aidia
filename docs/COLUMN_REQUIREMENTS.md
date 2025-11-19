# Column Requirements Analysis
# DIA Window Optimizer v2.0

**Purpose**: Document essential columns for memory-efficient ValidatedData objects

**Last Updated**: 2025-11-19
**Version**: 2.0

---

## 🎯 Design Goals

1. **Memory Efficiency**: Remove unnecessary columns from ValidatedData
2. **Flexibility**: Support diverse data formats (PTM-specific, different platforms)
3. **Extensibility**: Easy to add custom columns for future workflows
4. **Backward Compatibility**: Graceful handling of missing optional columns

---

## 📊 Column Usage by Stage

### Stage 1: Data Validation

**Input**: DIA-NN report (full columns)
**Purpose**: Load, validate, and create consensus

| Column | Type | Usage | Required |
|--------|------|-------|----------|
| `Run` | chr | Replicate detection | No (auto-detect) |
| `Precursor.Id` | chr | Unique precursor identifier | Yes |
| `RT.Start` | num | Retention time (minutes) | **Yes** |
| `Precursor.Mz` | num | m/z value (Da) | **Yes** |
| `FWHM` | num | Peak width (minutes) | **Yes** |
| `Precursor.Quantity` | num | Intensity for CV filtering | No (QC only) |
| `Q.Value` | num | DIA-NN quality filter | No (optional QC) |
| `PG.MaxLFQ` | num | MaxLFQ quantification | No (not used) |
| `Protein.Names` | chr | Protein annotation | No (not used) |

**After Stage 1 Consensus**:
- Added: `n_replicates`, `RT_CV_pct`, `FWHM_CV_pct`, `Intensity_CV_pct`

---

### Stage 2: Optimization Planning

**Input**: ValidatedData from Stage 1
**Purpose**: DPPP diagnosis and window count determination

| Column | Type | Usage | Required |
|--------|------|-------|----------|
| `FWHM` | num | DPPP calculation | **Yes** |

**Calculation**: `DPPP = (1.7 × FWHM_sec) / cycle_time`

**NOT USED**:
- RT, Precursor.Mz, Precursor.Quantity, CV columns

---

### Stage 3: Window Optimization

**Input**: ValidatedData + OptimizationPlan
**Purpose**: Generate RT-dependent isolation windows

| Column | Type | Usage | Required |
|--------|------|-------|----------|
| `RT.Start` | num | RT binning, segment assignment | **Yes** |
| `Precursor.Mz` | num | m/z range optimization | **Yes** |

**Algorithms**:
- RT binning: Uses `RT.Start` for time-based segmentation
- m/z optimization: Uses `Precursor.Mz` for range calculation
- Window generation: Uses both for precursor-window assignment

**NOT USED**:
- FWHM, Precursor.Quantity, CV columns

---

### Stage 4: Visualization

**Input**: ValidatedData + OptimizationPlan + OptimizedWindows
**Purpose**: Generate diagnostic plots and reports

| Column | Type | Usage | Required |
|--------|------|-------|----------|
| `RT.Start` | num | RT distribution plots | **Yes** |
| `Precursor.Mz` | num | m/z distribution plots | **Yes** |
| `FWHM` | num | DPPP density plot | **Yes** |

**Plots Using Each Column**:
- FWHM: Plot 1 (DPPP density), Plot 2 (DPPP vs RT)
- RT: Plot 3 (RT allocation), Plot 4 (window size vs RT)
- Mz: Plot 5 (m/z coverage), Plot 6 (precursor distribution)

---

## ✅ Essential Columns Summary

### **Core Pipeline (Stages 1-4)**

| Column | Stage 1 | Stage 2 | Stage 3 | Stage 4 | **Essential** |
|--------|---------|---------|---------|---------|---------------|
| `Precursor.Id` | ✅ | ❌ | ❌ | ❌ | **Yes** (tracking) |
| `RT.Start` | ✅ | ❌ | ✅ | ✅ | **Yes** |
| `Precursor.Mz` | ✅ | ❌ | ✅ | ✅ | **Yes** |
| `FWHM` | ✅ | ✅ | ❌ | ✅ | **Yes** |

### **Optional Columns**

| Column | Purpose | When Required |
|--------|---------|---------------|
| `Run` | Replicate detection | Multi-run datasets |
| `Precursor.Quantity` | Intensity CV filtering | QC filtering enabled |
| `n_replicates` | Replicate metadata | After consensus |
| `RT_CV_pct` | QC reporting | After consensus |
| `FWHM_CV_pct` | QC reporting | After consensus |
| `Intensity_CV_pct` | QC filtering | After consensus with intensity |

### **Never Used (Can Remove)**

| Column | Reason |
|--------|--------|
| `Q.Value` | Only for Stage 1 filtering (not passed downstream) |
| `PG.MaxLFQ` | Not used in window optimization |
| `Protein.Names` | Not used in window optimization |
| `Protein.Ids` | Not used in window optimization |
| `Genes` | Not used in window optimization |
| `Stripped.Sequence` | Not used in window optimization |
| `Modified.Sequence` | Not used in window optimization |
| `Precursor.Charge` | Not used in current pipeline |

---

## 🔧 Implementation Strategy

### 1. Minimal Essential Set

**Always Keep** (4 columns):
```r
essential_columns <- c(
  "Precursor.Id",  # Unique identifier
  "RT.Start",      # Retention time (Stage 3, 4)
  "Precursor.Mz",  # m/z value (Stage 3, 4)
  "FWHM"           # Peak width (Stage 2, 4)
)
```

### 2. Conditional Columns

**Keep if Present**:
```r
qc_columns <- c(
  "n_replicates",      # After consensus
  "RT_CV_pct",         # QC reporting
  "FWHM_CV_pct",       # QC reporting
  "Intensity_CV_pct"   # QC filtering
)
```

### 3. Custom Extensions

**User-Configurable**:
```r
# config/optimization_config.json
{
  "column_selection": {
    "mode": "minimal",  # or "standard", "full", "custom"
    "additional_columns": [
      "Precursor.Charge",  # For charge-specific analysis
      "Modified.Sequence"  # For PTM-specific workflows
    ]
  }
}
```

---

## 📐 Memory Impact Estimation

### Example Dataset: 50,000 precursors

**Full DIA-NN Output** (~40 columns):
```
50,000 rows × 40 columns × 8 bytes = ~16 MB
```

**Essential Only** (4 columns):
```
50,000 rows × 4 columns × 8 bytes = ~1.6 MB
```

**With QC Columns** (8 columns):
```
50,000 rows × 8 columns × 8 bytes = ~3.2 MB
```

**Memory Savings**: ~80% reduction (16 MB → 3.2 MB)

---

## 🚀 Use Cases

### Use Case 1: Standard DIA Workflow

**Columns**: `Precursor.Id`, `RT.Start`, `Precursor.Mz`, `FWHM`
**Memory**: Minimal (~1.6 MB for 50K precursors)
**Support**: All Stages 1-4

### Use Case 2: QC-Enabled Workflow

**Columns**: Essential + `n_replicates`, `*_CV_pct`
**Memory**: ~3.2 MB for 50K precursors
**Support**: Full QC reporting

### Use Case 3: PTM-Specific Workflow

**Columns**: Essential + `Modified.Sequence`, `Precursor.Charge`
**Memory**: ~2.4 MB for 50K precursors
**Support**: Future PTM-specific m/z optimization

### Use Case 4: Charge State Analysis

**Columns**: Essential + `Precursor.Charge`
**Memory**: ~2.0 MB for 50K precursors
**Support**: Charge-dependent window design

---

## 🔬 Platform-Specific Extensions

### Thermo Orbitrap (DIA-NN Output)
- **Essential**: `RT.Start`, `Precursor.Mz`, `FWHM`
- **Optional**: `Precursor.Quantity` (for CV filtering)

### Bruker timsTOF (DIA-NN Output)
- **Essential**: `RT.Start`, `Precursor.Mz`, `FWHM`
- **Future**: `IM` (ion mobility) for 4D-DIA window design

### Sciex TripleTOF (DIA-NN Output)
- **Essential**: `RT.Start`, `Precursor.Mz`, `FWHM`
- **Standard**: Same as Orbitrap

### Waters Synapt (Custom Format)
- **Essential**: Map platform-specific RT/m/z columns
- **Future**: Support custom column mapping

---

## 📝 Implementation Notes

### Backward Compatibility

**Missing Optional Columns**:
```r
# Graceful handling
if ("Precursor.Quantity" %in% colnames(data)) {
  # Enable intensity CV filtering
} else {
  # Skip intensity CV filtering
  warning("Precursor.Quantity not found - skipping intensity CV filtering")
}
```

### Forward Compatibility

**Custom Column Support**:
```r
# Allow user-specified columns
config$column_selection$additional_columns <- c(
  "Precursor.Charge",
  "IM"  # Ion mobility for timsTOF
)
```

---

## 🎯 Recommended Defaults

### Default Mode: `"standard"`

**Includes**:
- Essential: `Precursor.Id`, `RT.Start`, `Precursor.Mz`, `FWHM`
- QC: `n_replicates`, `*_CV_pct` (if present after consensus)
- Memory: ~3-5 MB for 50K precursors

### Memory-Optimized Mode: `"minimal"`

**Includes**:
- Essential only: 4 columns
- Memory: ~1.6 MB for 50K precursors
- Trade-off: No QC reporting in downstream stages

### Full Mode: `"full"`

**Includes**:
- All columns from Stage 1 output
- Memory: ~8-16 MB for 50K precursors
- Use case: Debugging, custom analysis

---

**Version**: 2.0
**Last Updated**: 2025-11-19
**Authors**: DIA Window Optimizer Team
