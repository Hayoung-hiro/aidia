# Geometric CV Guide for DIA Window Optimizer

**Document Version**: 1.0
**Date**: 2025-11-08
**Purpose**: Correct CV calculation for DIA proteomics data quality control

---

## 📚 Background: Why Geometric CV?

### The Problem with Standard CV

Mass spectrometry intensity data has unique statistical properties:

1. **Original intensity distribution**: Log-normal (not normal)
2. **After log transformation**: Approximately normal
3. **Implication**: Choice of CV formula depends on data transformation

### Two CV Formulas

#### Formula 1: Base CV (for original intensity)
```
Base CV = σ / μ

where:
  σ = standard deviation of original intensity
  μ = mean of original intensity
```

**Use when**: Working with **non-transformed** intensity values

#### Formula 2: Geometric CV (for log-transformed intensity)
```
Geometric CV = √(e^(σ²) - 1)

where:
  σ = standard deviation of log-transformed intensity
  e = Euler's number (≈2.718)
```

**Use when**: Working with **log-transformed** intensity values

---

## ⚠️ Critical Error to Avoid

**WRONG** ❌: Applying Base CV formula to log-transformed data

```r
# WRONG - DO NOT DO THIS!
log_intensity <- log(intensity)
wrong_cv <- sd(log_intensity) / mean(log_intensity)
# → Produces artificially low CV (14× underestimation!)
```

**Impact of error**:
- 75% of proteins show CV < 0.75% (artificially low)
- Real CV is 14× higher on average
- Misleading quality assessment

**RIGHT** ✅: Match formula to data transformation

```r
# Option A: Base CV on original data
base_cv <- sd(intensity) / mean(intensity)

# Option B: Geometric CV on log-transformed data
log_intensity <- log(intensity)
sigma_log <- sd(log_intensity)
geometric_cv <- sqrt(exp(sigma_log^2) - 1)

# Result: Both methods give similar median CV (when correct!)
```

---

## 🎯 Application to DIA Window Optimization

### Our Context: Technical Study

DIA window optimization is a **technical/methodological study**:
- Goal: Assess **instrument performance** and **method quality**
- Need: Evaluate **true technical variation** without normalization
- Approach: Use **original intensity** or **Geometric CV on log data**

### Data Characteristics in Stage 1

**Input**: DIA-NN report with technical replicates
- Multiple runs of same sample
- RT, m/z, FWHM, Precursor.Quantity columns
- **No normalization applied** (raw DIA-NN output)

**Key measurements**:
- **RT (Retention Time)**: Already in linear scale (minutes)
- **FWHM (Peak width)**: Already in linear scale (minutes)
- **Precursor.Quantity**: Log-normal distributed (intensity)

---

## 📊 Implementation Strategy for Stage 1

### 1. Replicate Aggregation (Consensus Dataset)

**Method**: Median-based consensus (robust to outliers)

```r
# For each precursor measured across N runs:
consensus_rt <- median(c(RT_run1, RT_run2, RT_run3))
consensus_fwhm <- median(c(FWHM_run1, FWHM_run2, FWHM_run3))
consensus_intensity <- median(c(Int_run1, Int_run2, Int_run3))
```

**Why median?**
- Robust to outlier runs
- Less sensitive to extreme values
- Suitable for small N (N=2-5 typical)

### 2. CV Calculation for Each Metric

#### A. RT and FWHM: Base CV (linear scale)

```r
# RT CV (retention time variation)
rt_values <- c(RT_run1, RT_run2, RT_run3)
rt_cv_percent <- (sd(rt_values) / mean(rt_values)) * 100

# FWHM CV (peak width variation)
fwhm_values <- c(FWHM_run1, FWHM_run2, FWHM_run3)
fwhm_cv_percent <- (sd(fwhm_values) / mean(fwhm_values)) * 100
```

**Interpretation**:
- RT CV < 5%: Excellent chromatographic reproducibility
- RT CV 5-10%: Good reproducibility
- RT CV > 10%: Poor reproducibility (investigate)

- FWHM CV < 15%: Excellent peak shape consistency
- FWHM CV 15-25%: Acceptable
- FWHM CV > 25%: Poor consistency (QC flag)

#### B. Intensity: Geometric CV (log-normal data)

```r
# Intensity CV (signal variation)
intensity_values <- c(Int_run1, Int_run2, Int_run3)

# Method 1: Base CV on original intensity
base_cv <- sd(intensity_values) / mean(intensity_values) * 100

# Method 2: Geometric CV on log-transformed
log_intensity <- log(intensity_values)
sigma_log <- sd(log_intensity)
geometric_cv <- sqrt(exp(sigma_log^2) - 1) * 100

# Both methods should give similar results (when correct)
```

**Note**: In DIA window optimization, we primarily use **RT** and **FWHM** for window design, so intensity CV is **optional** (for QC reporting only).

### 3. Quality Filtering Thresholds

Based on replicate CV, filter out low-quality precursors:

```r
# QC filters for consensus dataset
qc_passed <- (
  n_replicates >= 2 &                # At least 2 replicates
  rt_cv <= 10 &                      # RT variation ≤ 10%
  fwhm_cv <= 20 &                    # FWHM variation ≤ 20%
  (intensity_cv <= 30 | is.na(intensity_cv))  # Optional intensity check
)
```

**Rationale**:
- High CV → poor reproducibility → unreliable for window design
- Filtering improves downstream window quality
- Retains only robust, reproducible precursors

---

## 🔬 Implementation Functions

### Core Function: Calculate Geometric CV

```r
#' Calculate Geometric CV from log-transformed data
#'
#' @param values Numeric vector (can be original or log-transformed)
#' @param is_log Logical, TRUE if values are already log-transformed
#' @return Geometric CV as percentage
#'
#' @details
#' Geometric CV is appropriate for log-normally distributed data (e.g., MS intensity).
#' Formula: CV = sqrt(exp(σ²) - 1) * 100
#' where σ is the standard deviation of log-transformed values.
#'
#' @references
#' - Coefficient of Variation in Mass Spectrometry (DOI: 10.1021/acs.jproteome.4c00461)
#'
#' @examples
#' # Intensity data (log-normal)
#' intensities <- c(1e5, 1.2e5, 9e4)
#' cv <- calculate_geometric_cv(intensities, is_log = FALSE)
#'
#' # Already log-transformed
#' log_intensities <- log(intensities)
#' cv <- calculate_geometric_cv(log_intensities, is_log = TRUE)
calculate_geometric_cv <- function(values, is_log = FALSE) {

  # Remove NA values
  values <- values[!is.na(values)]

  if (length(values) < 2) {
    return(NA_real_)
  }

  # Transform to log scale if needed
  if (!is_log) {
    # Check for non-positive values
    if (any(values <= 0)) {
      warning("Non-positive values detected. Removing before log transformation.")
      values <- values[values > 0]
    }

    if (length(values) < 2) {
      return(NA_real_)
    }

    log_values <- log(values)
  } else {
    log_values <- values
  }

  # Calculate standard deviation of log-transformed values
  sigma_log <- sd(log_values, na.rm = TRUE)

  # Geometric CV formula
  geometric_cv <- sqrt(exp(sigma_log^2) - 1) * 100

  return(geometric_cv)
}
```

### Core Function: Calculate Base CV

```r
#' Calculate Base (Standard) CV
#'
#' @param values Numeric vector in linear scale
#' @return Base CV as percentage
#'
#' @details
#' Base CV = (σ / μ) * 100
#' Use for normally distributed data (e.g., RT, FWHM in DIA).
#'
#' @examples
#' # RT values (minutes)
#' rt_values <- c(15.2, 15.3, 15.1)
#' cv <- calculate_base_cv(rt_values)
calculate_base_cv <- function(values) {

  # Remove NA values
  values <- values[!is.na(values)]

  if (length(values) < 2) {
    return(NA_real_)
  }

  mean_val <- mean(values, na.rm = TRUE)

  if (mean_val == 0) {
    return(NA_real_)
  }

  sd_val <- sd(values, na.rm = TRUE)
  base_cv <- (sd_val / mean_val) * 100

  return(base_cv)
}
```

### Replicate Aggregation with CV Calculation

```r
#' Aggregate technical replicates with proper CV calculation
#'
#' @param data Data frame with Run column and measurements
#' @param min_replicates Minimum replicates required (default: 2)
#' @param max_rt_cv Maximum RT CV% for QC (default: 10)
#' @param max_fwhm_cv Maximum FWHM CV% for QC (default: 20)
#' @param max_intensity_cv Maximum intensity CV% for QC (default: 30, optional)
#'
#' @return List with consensus data and QC report
aggregate_replicates_with_cv <- function(
  data,
  min_replicates = 2,
  max_rt_cv = 10,
  max_fwhm_cv = 20,
  max_intensity_cv = 30
) {

  # Check for Run column
  if (!"Run" %in% names(data)) {
    return(list(
      data = data,
      qc_report = list(message = "No Run column - single run data")
    ))
  }

  n_runs <- length(unique(data$Run))

  if (n_runs == 1) {
    return(list(
      data = data,
      qc_report = list(message = "Single run detected")
    ))
  }

  cat(sprintf("\n📊 Aggregating %d technical replicates...\n", n_runs))

  # Aggregate by precursor
  data_consensus <- data %>%
    group_by(Precursor.Id) %>%
    summarise(
      # Consensus values (median - robust to outliers)
      RT.Start = median(RT.Start, na.rm = TRUE),
      RT.Stop = median(RT.Stop, na.rm = TRUE),
      Precursor.Mz = median(Precursor.Mz, na.rm = TRUE),
      FWHM = median(FWHM, na.rm = TRUE),

      # Base CV for linear-scale metrics
      RT_CV = calculate_base_cv(RT.Start),
      FWHM_CV = calculate_base_cv(FWHM),
      Mz_CV = calculate_base_cv(Precursor.Mz),

      # Geometric CV for intensity (if available)
      Intensity_CV = if ("Precursor.Quantity" %in% names(data)) {
        calculate_geometric_cv(Precursor.Quantity, is_log = FALSE)
      } else {
        NA_real_
      },

      # Replication info
      n_replicates = n(),

      .groups = "drop"
    )

  # Quality filtering
  data_filtered <- data_consensus %>%
    filter(
      n_replicates >= min_replicates,
      (RT_CV <= max_rt_cv | is.na(RT_CV)),
      (FWHM_CV <= max_fwhm_cv | is.na(FWHM_CV))
    )

  # Optional intensity filter (if column exists)
  if ("Intensity_CV" %in% names(data_filtered) && !all(is.na(data_filtered$Intensity_CV))) {
    data_filtered <- data_filtered %>%
      filter(Intensity_CV <= max_intensity_cv | is.na(Intensity_CV))
  }

  # Generate QC report
  qc_report <- list(
    total_runs = n_runs,
    aggregation_method = "median",
    cv_method = list(
      rt_fwhm = "Base CV (σ/μ)",
      intensity = "Geometric CV [sqrt(exp(σ²)-1)]"
    ),

    # Before filtering
    precursors_before = nrow(data_consensus),
    mean_rt_cv_before = mean(data_consensus$RT_CV, na.rm = TRUE),
    mean_fwhm_cv_before = mean(data_consensus$FWHM_CV, na.rm = TRUE),

    # After filtering
    precursors_after = nrow(data_filtered),
    removed_count = nrow(data_consensus) - nrow(data_filtered),
    removed_pct = (1 - nrow(data_filtered) / nrow(data_consensus)) * 100,
    mean_rt_cv_after = mean(data_filtered$RT_CV, na.rm = TRUE),
    mean_fwhm_cv_after = mean(data_filtered$FWHM_CV, na.rm = TRUE),

    # QC thresholds used
    filters = list(
      min_replicates = min_replicates,
      max_rt_cv = max_rt_cv,
      max_fwhm_cv = max_fwhm_cv,
      max_intensity_cv = max_intensity_cv
    )
  )

  # Print summary
  print_replicate_qc_summary(qc_report)

  return(list(
    data = data_filtered,
    qc_report = qc_report
  ))
}
```

---

## 📋 QC Reporting Template

### Stage 1 Validation Report Should Include:

```
═══════════════════════════════════════════════════
Technical Replicate QC Report
═══════════════════════════════════════════════════

Replication Summary:
  • Total runs: 3
  • Aggregation method: median (robust to outliers)
  • CV calculation:
    - RT/FWHM: Base CV (σ/μ) for linear-scale data
    - Intensity: Geometric CV [√(e^σ² - 1)] for log-normal data

Before QC Filtering:
  • Precursors: 7,793
  • Mean RT CV: 4.2%
  • Mean FWHM CV: 12.5%
  • Mean Intensity CV: 18.3% (geometric)

QC Filters Applied:
  • Min replicates: ≥2
  • Max RT CV: ≤10%
  • Max FWHM CV: ≤20%
  • Max Intensity CV: ≤30%

After QC Filtering:
  • Precursors: 7,421 (95.2% retained)
  • Removed: 372 (4.8% failed QC)
  • Mean RT CV: 3.8%
  • Mean FWHM CV: 11.2%
  • Mean Intensity CV: 15.7%

Quality Assessment: ✅ EXCELLENT
  • RT reproducibility: Excellent (CV < 5%)
  • FWHM consistency: Good (CV < 15%)
  • Intensity precision: Good (CV < 20%)

═══════════════════════════════════════════════════
```

---

## 📚 References and Best Practices

### Key References

1. **Geometric CV in Proteomics**:
   - DOI: 10.1021/acs.jproteome.4c00461
   - "Coefficient of Variation in DIA Proteomics"

2. **DIA-NN Best Practices**:
   - Technical studies: Use "High Accuracy" (v1.8) or "legacy (direct)" (v1.9+)
   - No normalization for technical variation assessment

### Reporting Checklist

When reporting DIA window optimization results, include:

- [ ] CV calculation method (Base or Geometric)
- [ ] Data transformation (log or linear scale)
- [ ] Normalization status (none for technical studies)
- [ ] Software parameters (DIA-NN quantification strategy)
- [ ] QC thresholds (max CV% values)
- [ ] Number of precursors before/after QC
- [ ] Mean CV for each metric (RT, FWHM, Intensity)

### Common Pitfalls to Avoid

1. ❌ Mixing CV formulas and data scales
2. ❌ Applying Base CV to log-transformed data
3. ❌ Using mean instead of median for outlier-prone data
4. ❌ Not documenting CV calculation method
5. ❌ Ignoring technical variation in method validation

---

## 🎯 Summary

**For DIA Window Optimization (Technical Study):**

| Metric | Scale | CV Formula | Threshold |
|--------|-------|------------|-----------|
| **RT** | Linear (minutes) | Base CV = σ/μ | ≤ 10% |
| **FWHM** | Linear (minutes) | Base CV = σ/μ | ≤ 20% |
| **m/z** | Linear (Da) | Base CV = σ/μ | ≤ 5 ppm |
| **Intensity** | Log-normal | Geometric CV = √(e^σ² - 1) | ≤ 30% |

**Consensus Strategy:**
- Aggregation: Median (robust to outliers)
- CV calculation: Metric-appropriate formula
- QC filtering: Remove high-CV precursors
- Reporting: Transparent documentation

**Critical Principle:**
> "Match the CV formula to the data distribution. Base CV for linear-scale metrics (RT, FWHM), Geometric CV for log-normal metrics (intensity)."

---

**Document Status**: ✅ Ready for Implementation
**Next Step**: Integrate into `R/stage1_data_validation.R`
