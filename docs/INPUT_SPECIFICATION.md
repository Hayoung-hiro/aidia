# AIDIA Input Specification

**Version**: 1.0
**Date**: 2026-02-06
**Status**: Reference Standard

This document defines the minimum required data elements for AIDIA window optimization. It serves as the reference specification for implementing format adapters for different mass spectrometry search engines (MaxQuant, Spectronaut, FragPipe, etc.).

---

## 1. Minimum Required Columns (3 Core)

AIDIA requires exactly three data elements for window optimization:

| Internal Name | Data Type | Unit | Description | Computational Role |
|--------------|-----------|------|-------------|--------------------|
| `RT.Start` | numeric | minutes | Precursor apex retention time | RT bin assignment, window scheduling |
| `Precursor.Mz` | numeric | Da | Precursor ion m/z value | m/z range optimization, window boundary calculation |
| `FWHM` | numeric | minutes | Chromatographic peak full width at half maximum | DPPP calculation (cycle time requirement) |

**Critical Notes**:
- These three columns are sufficient for all Stage 1-4 pipeline operations
- All other columns are optional metadata for user reference or quality control
- Column names must match exactly (case-sensitive)

---

## 2. Recommended Columns (2 Additional)

These columns enhance functionality but are not required:

| Internal Name | Data Type | Purpose | Used In |
|--------------|-----------|---------|---------|
| `Precursor.Id` | character | Unique precursor identifier | Technical replicate consensus grouping (`create_consensus_dataset()`) |
| `Protein.Group` | character | Protein group annotation | User reference, export metadata |

**When to include**:
- `Precursor.Id`: Required for multi-file replicate consensus mode
- `Protein.Group`: Recommended for traceability in export files

---

## 3. Optional Columns

| Internal Name | Data Type | Purpose | When Needed |
|--------------|-----------|---------|-------------|
| `Precursor.Quantity` | numeric | Intensity values | Geometric CV filtering in replicate consensus (`create_consensus_dataset()`) |
| `Run` | character | Run/file identifier | Technical replicate detection, multi-file processing |
| `Precursor.Charge` | integer | Charge state | User metadata (not used computationally) |
| `Modified.Sequence` | character | Peptide sequence | User metadata (not used computationally) |

**Quality Filtering Columns** (tool-specific):
- DIA-NN: `Q.Value`, `PG.Q.Value`, `GG.Q.Value` (applied before pipeline)
- MaxQuant: `PEP` (posterior error probability)
- Spectronaut: `EG.Qvalue`
- FragPipe: `Expectation`

**Important**: Quality filtering is performed by format adapters before data enters the pipeline. The pipeline itself does not filter by quality scores.

---

## 4. Column Name Mapping Table

How different search engines map to AIDIA internal names:

| AIDIA Internal | DIA-NN | MaxQuant (evidence.txt) | Spectronaut | FragPipe (psm.tsv) |
|---------------|--------|------------------------|-------------|---------------------|
| `RT.Start` | `RT.Start` | `Retention time` | `EG.ApexRT` | `Retention` |
| `Precursor.Mz` | `Precursor.Mz` | `m/z` | `FG.PrecMz` | `Observed M/Z` |
| `FWHM` | `FWHM` (v2.2+) | `Retention length` (sec → min) | `EG.PeakWidth` | N/A (must estimate) |
| `Precursor.Id` | `Precursor.Id` | `Modified sequence` + `Charge` | `EG.PrecursorId` | `Peptide` + `Charge` |
| `Protein.Group` | `Protein.Group` | `Protein group IDs` | `PG.ProteinGroups` | `Protein` |
| `Precursor.Quantity` | `Precursor.Quantity` | `Intensity` | `FG.Quantity` | `Intensity` |
| `Run` | `Run` | `Raw file` | `R.FileName` | `Spectrum File` |

**Special Cases**:
- **MaxQuant**: `Retention length` is in seconds → divide by 60 to convert to minutes
- **FragPipe**: Does not report per-precursor FWHM → requires external estimation or fixed default value
- **Precursor.Id composition**: Some tools require concatenating multiple columns (e.g., sequence + charge)

---

## 5. Unit Conventions

All format adapters must adhere to these unit standards:

| Measurement | Unit | Notes |
|-------------|------|-------|
| Retention Time (RT) | **minutes** | Convert from seconds if necessary (divide by 60) |
| FWHM | **minutes** | Convert from seconds if necessary (divide by 60) |
| m/z | **Da (Daltons)** | Universal standard, no conversion needed |
| Intensity | dimensionless | No unit requirement (only used for CV ratio calculations) |
| Cycle Time | **seconds** | Internal calculations only (not in input data) |

**Common Conversion Errors**:
- MaxQuant `Retention length` is in seconds (not minutes)
- Some tools report RT in seconds (e.g., mzML files)
- Always verify units before mapping

---

## 6. Known Limitations

### Legacy Artifacts
- **`RT.Stop`**: Currently required by `data_loader.R` but never used computationally
  - To be removed in future refactoring
  - Workaround: Set `RT.Stop = RT.Start + FWHM` for compatibility

### Tool-Specific Challenges

| Tool | Issue | Adapter Solution |
|------|-------|------------------|
| **FragPipe** | No per-precursor FWHM | Estimate from RT distribution or use fixed default (e.g., 0.5 min) |
| **MaxQuant** | Time units in seconds | Convert `Retention time` and `Retention length` to minutes |
| **mzML** | Raw spectra format | Requires peak picking and chromatographic peak detection |
| **Skyline** | Variable export formats | Support multiple export templates |

### Quality Filtering Strategy
- **Current implementation**: DIA-NN-specific Q-value filtering in `data_loader.R`
- **Future architecture**: Move quality filtering to format-specific adapters
- **Reason**: Each tool has different confidence metrics (Q-value, PEP, Expectation)

---

## 7. Format Adapter Architecture

### Design Pattern

```
               ┌──────────────────┐
               │  Raw Input       │
               │ (Tool-specific)  │
               │ - DIA-NN parquet │
               │ - MaxQuant txt   │
               │ - Spectronaut    │
               │ - FragPipe TSV   │
               └────────┬─────────┘
                        │
               ┌────────▼─────────┐
               │ Format Adapter   │  ← One per tool
               │                  │
               │ 1. Read data     │
               │ 2. Map columns   │
               │ 3. Convert units │
               │ 4. Filter quality│
               │ 5. Validate      │
               └────────┬─────────┘
                        │
          ┌─────────────▼──────────────┐
          │   AIDIA Internal Format    │
          │                            │
          │ Required:                  │
          │  - RT.Start (min)          │
          │  - Precursor.Mz (Da)       │
          │  - FWHM (min)              │
          │                            │
          │ Optional:                  │
          │  - Precursor.Id            │
          │  - Protein.Group           │
          │  - Precursor.Quantity      │
          │  - Run                     │
          └─────────────┬──────────────┘
                        │
               ┌────────▼─────────┐
               │  AIDIA Pipeline  │
               │                  │
               │ Stage 1: Validate│
               │ Stage 2: Plan    │
               │ Stage 3: Optimize│
               │ Stage 4: Visualize│
               └──────────────────┘
```

### Adapter Responsibilities

Each format adapter must implement:

1. **Column Mapping**: Tool-specific names → AIDIA internal names
2. **Unit Conversion**: Ensure RT and FWHM are in minutes
3. **Quality Filtering**: Apply tool-specific confidence thresholds
4. **Data Validation**: Verify required columns exist and have valid values
5. **Error Handling**: Informative messages for missing/invalid data

### Reference Implementation (DIA-NN)

Current implementation in `R/data_loader.R` serves as reference:

```r
# Example adapter structure (pseudocode)
load_diann_data <- function(file_path, qvalue_threshold = 0.01) {
  # 1. Read raw data
  raw_data <- arrow::read_parquet(file_path)

  # 2. Quality filtering (tool-specific)
  filtered_data <- raw_data %>%
    filter(Q.Value <= qvalue_threshold)

  # 3. Column mapping (DIA-NN already uses AIDIA names)
  mapped_data <- filtered_data %>%
    select(
      RT.Start,           # Already in minutes
      Precursor.Mz,       # Already in Da
      FWHM,               # Already in minutes
      Precursor.Id,
      Protein.Group,
      Precursor.Quantity,
      Run
    )

  # 4. Validation
  validate_required_columns(mapped_data)

  return(mapped_data)
}
```

---

## 8. Validation Requirements

All format adapters must validate:

### Required Column Checks
- All three core columns exist: `RT.Start`, `Precursor.Mz`, `FWHM`
- No NA/NULL values in core columns
- Numeric types for core columns

### Value Range Checks
- `RT.Start` > 0 (positive retention times)
- `Precursor.Mz` > 0 (positive m/z values)
- `FWHM` > 0 (positive peak widths)
- Reasonable ranges:
  - RT: typically 0-200 minutes
  - m/z: typically 300-2000 Da
  - FWHM: typically 0.1-5 minutes

### Data Quality Warnings
- RT values in seconds (>300 suggests seconds not minutes)
- FWHM values too large (>10 minutes suggests unit error)
- Missing optional columns (informational only)

---

## 9. Future Adapter Implementations

### Priority Queue

1. **MaxQuant** (evidence.txt)
   - High demand, well-documented format
   - Unit conversion required (seconds → minutes)
   - Combine `Modified sequence` + `Charge` for `Precursor.Id`

2. **Spectronaut**
   - Common DIA tool, direct competitor to DIA-NN
   - Column mapping straightforward
   - Check time units (typically minutes)

3. **FragPipe** (psm.tsv or combined_ion.tsv)
   - Growing DIA support
   - FWHM estimation required (not reported)
   - Consider using fixed FWHM or RT-based estimation

4. **mzML/mzXML** (raw spectra)
   - Low priority (requires peak picking)
   - Consider third-party tools for feature extraction
   - Complex implementation

### Testing Strategy

For each new adapter:
1. Obtain reference dataset from tool
2. Verify column mapping with tool documentation
3. Test unit conversions with known values
4. Run through AIDIA pipeline (Stages 1-4)
5. Compare results with DIA-NN equivalent dataset (if available)

---

## 10. Appendix: Example Data

### Minimum Valid Input (TSV format)

```tsv
RT.Start	Precursor.Mz	FWHM
15.2	524.2815	0.35
15.3	524.2815	0.38
45.7	612.3142	0.42
45.8	612.3142	0.40
```

### Full Recommended Input

```tsv
RT.Start	Precursor.Mz	FWHM	Precursor.Id	Protein.Group	Precursor.Quantity	Run
15.2	524.2815	0.35	PEPTIDE_2	P12345	1.2e6	sample1
15.3	524.2815	0.38	PEPTIDE_2	P12345	1.1e6	sample2
45.7	612.3142	0.42	PEPTIDE_5	P67890	8.5e5	sample1
45.8	612.3142	0.40	PEPTIDE_5	P67890	9.2e5	sample2
```

---

## References

- **Current Implementation**: `R/data_loader.R` (DIA-NN adapter)
- **Column Usage Analysis**: `docs/COLUMN_REQUIREMENTS.md`
- **Architecture Overview**: `docs/ARCHITECTURE.md`
- **Replicate Handling**: `docs/GEOMETRIC_CV_GUIDE.md`

---

**Document Owner**: AIDIA Development Team
**Last Updated**: 2026-02-06
**Next Review**: Upon first new adapter implementation
