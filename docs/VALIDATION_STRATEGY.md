# DIA Window Optimizer - Validation & Feedback Strategy

**Version**: 1.0
**Date**: 2025-11-28
**Purpose**: Systematic validation protocol for real-world proteomics labs

---

## Executive Summary

DIA Window Optimizer의 실제 성능을 검증하기 위한 3-tier validation 전략:

1. **Tier 1**: Standard sample comparison (QC samples)
2. **Tier 2**: Biological sample diversity test (real experiments)
3. **Tier 3**: Method development optimization (new applications)

**Expected Timeline**: 4-6 weeks
**Key Metrics**: Precursor IDs, protein groups, quantification CV%, missing values

---

## Tier 1: Standard Sample Validation (Week 1-2)

### 목적
- Optimizer 성능의 baseline 확립
- 기존 method와 직접 비교
- Reproducibility 검증

### 시료 선택

#### Option A: HeLa Cell Digest (권장)
**시료**: Pierce™ HeLa Protein Digest Standard (Thermo Scientific)
- **장점**:
  - Commercially available (재현성 보장)
  - 널리 사용되는 benchmark standard
  - 문헌 데이터와 비교 가능
- **권장량**: 200 ng on-column
- **Technical replicates**: 3회

#### Option B: K562 Cell Lysate
**시료**: Human chronic myelogenous leukemia cell line
- **장점**: Complex mammalian proteome
- **권장량**: 500 ng on-column
- **Technical replicates**: 3회

#### Option C: Lab's Routine QC Sample
**시료**: Lab에서 일상적으로 사용하는 QC 시료
- **장점**: Lab-specific baseline 확립
- **권장량**: Lab standard protocol 따름
- **Technical replicates**: 5회 (CV 계산 위해)

### 실험 설계

**Comparison Groups** (3 gradients × 2 methods × 3 replicates = 18 runs):

| Gradient | Method A (Current) | Method B (Optimized) |
|----------|-------------------|---------------------|
| **30min** | Lab's current DIA method | Optimizer-generated (Coverage strategy) |
| **60min** | Lab's current DIA method | Optimizer-generated (Coverage strategy) |
| **90min** | Lab's current DIA method | Optimizer-generated (Coverage strategy) |

**Batch Design**:
```
Day 1: 30min gradient
  - Run 1-3: Current method (3 replicates)
  - Run 4-6: Optimized method (3 replicates)

Day 2: 60min gradient
  - Run 7-9: Current method (3 replicates)
  - Run 10-12: Optimized method (3 replicates)

Day 3: 90min gradient
  - Run 13-15: Current method (3 replicates)
  - Run 16-18: Optimized method (3 replicates)
```

**Randomization**: Use block randomization to minimize batch effects

### Primary Metrics

#### 1. Identification Performance

**Precursor-level**:
```r
# DIA-NN output analysis
metrics <- list(
  total_precursors = nrow(subset(report, Q.Value <= 0.01)),
  high_confidence = nrow(subset(report, Q.Value <= 0.001)),
  mean_pg_quantity_quality = mean(report$PG.MaxLFQ.Quality, na.rm = TRUE)
)

# Calculate improvement
improvement_pct <- (optimized - current) / current * 100
```

**Expected improvement**: +5-15% precursor IDs

**Protein-level**:
```r
# Protein group counting
protein_groups <- report %>%
  filter(PG.Q.Value <= 0.01) %>%
  distinct(Protein.Group) %>%
  nrow()
```

**Expected improvement**: +3-10% protein groups

#### 2. Quantification Quality

**CV% Analysis** (Technical Replicates):
```r
# Calculate CV% for each protein group
cv_analysis <- report %>%
  group_by(Protein.Group) %>%
  summarise(
    mean_intensity = mean(PG.MaxLFQ, na.rm = TRUE),
    sd_intensity = sd(PG.MaxLFQ, na.rm = TRUE),
    cv_pct = (sd_intensity / mean_intensity) * 100,
    n_replicates = n()
  ) %>%
  filter(n_replicates >= 3)

# Median CV%
median_cv <- median(cv_analysis$cv_pct, na.rm = TRUE)
```

**Expected improvement**: CV% reduction by 10-20%

**Missing Value Analysis**:
```r
# Count missing values per protein
missing_analysis <- report %>%
  group_by(Protein.Group) %>%
  summarise(
    total_runs = 3,  # Expected replicates
    detected_runs = n(),
    missing_runs = total_runs - detected_runs,
    completeness = detected_runs / total_runs
  )

# Proteins with 100% completeness
complete_proteins <- sum(missing_analysis$completeness == 1.0)
```

**Expected improvement**: +15-25% proteins with complete quantification

#### 3. Mass Accuracy

**Precursor m/z Error**:
```r
# PPM error distribution
ppm_analysis <- report %>%
  mutate(
    ppm_error = abs(Mass.Evidence - Precursor.Mz) / Precursor.Mz * 1e6
  ) %>%
  summarise(
    median_ppm = median(ppm_error, na.rm = TRUE),
    mad_ppm = mad(ppm_error, na.rm = TRUE)
  )
```

**Expected**: No significant difference (should be similar)

#### 4. Actual DPPP Achievement

**DPPP Distribution**:
```r
# Calculate actual DPPP from results
dppp_analysis <- report %>%
  mutate(
    actual_dppp = (1.7 * FWHM * 60) / cycle_time_sec
  ) %>%
  summarise(
    mean_dppp = mean(actual_dppp, na.rm = TRUE),
    median_dppp = median(actual_dppp, na.rm = TRUE),
    satisfaction_ratio = sum(actual_dppp >= 7.0) / n()
  )
```

**Expected**: Satisfaction ratio >70% (target achieved)

### Data Collection Template

```csv
Gradient,Method,Replicate,Run_Date,Precursors,Proteins,Median_CV,Missing_Values,Median_DPPP,Satisfaction_Ratio
30min,Current,1,2025-12-01,8500,2100,15.2,320,5.8,0.45
30min,Current,2,2025-12-01,8450,2090,15.8,335,5.9,0.46
30min,Current,3,2025-12-01,8520,2105,15.5,315,5.7,0.44
30min,Optimized,1,2025-12-01,9200,2280,13.1,210,7.2,0.72
30min,Optimized,2,2025-12-01,9150,2270,13.5,225,7.1,0.71
30min,Optimized,3,2025-12-01,9180,2275,13.3,215,7.3,0.73
...
```

---

## Tier 2: Biological Sample Diversity Test (Week 3-4)

### 목적
- 다양한 biological matrix에서 성능 검증
- Sample complexity에 따른 최적 strategy 확인
- Real experiment workflow 검증

### 시료 선택 (다양성 확보)

#### Sample Set 1: Mammalian Tissues (조직 특이성)

**A. Liver Tissue**
- **특징**: High dynamic range, abundant proteins
- **Expected precursors**: 15,000-25,000
- **Recommended strategy**: Quantile (robust)
- **Biological replicates**: 3-5

**B. Brain Tissue**
- **특징**: Membrane proteins, lipid-rich
- **Expected precursors**: 10,000-18,000
- **Recommended strategy**: Coverage (maximize)
- **Biological replicates**: 3-5

**C. Muscle Tissue**
- **특징**: High contractile proteins, low complexity
- **Expected precursors**: 8,000-12,000
- **Recommended strategy**: Quantile (fast)
- **Biological replicates**: 3-5

#### Sample Set 2: Cell Culture (processing variation)

**A. Adherent Cells** (e.g., HEK293)
- **Processing**: Trypsin digestion, standard lysis
- **Expected precursors**: 12,000-20,000
- **Recommended strategy**: Coverage

**B. Suspension Cells** (e.g., Jurkat)
- **Processing**: Direct lysis, minimal handling
- **Expected precursors**: 10,000-18,000
- **Recommended strategy**: Quantile

#### Sample Set 3: Clinical Samples (complexity variation)

**A. Plasma/Serum** (high dynamic range)
- **특징**: 10^10 dynamic range, albumin depletion 필요
- **Expected precursors**: 3,000-8,000
- **Recommended strategy**: Outlier (capture rare proteins)
- **Depletion**: Top 14 abundant proteins

**B. Urine** (variable composition)
- **특징**: Low protein concentration, high salt
- **Expected precursors**: 1,000-3,000
- **Recommended strategy**: Coverage (maximize signal)

**C. CSF** (low abundance)
- **특징**: Low total protein, high variability
- **Expected precursors**: 1,500-4,000
- **Recommended strategy**: Outlier or Coverage

### 실험 설계

**Strategy Comparison** (각 sample type마다):

| Sample Type | Strategy A | Strategy B | Strategy C |
|-------------|-----------|-----------|-----------|
| Liver | Quantile | Coverage | Outlier |
| Brain | Quantile | Coverage | Smoothing |
| Plasma | Coverage | Outlier | - |

**Biological replicates**: 3-5 per condition
**Technical replicates**: Optional (for high-value samples)

### Metrics for Biological Samples

#### 1. Proteome Coverage

**Depth of Coverage**:
```r
# Protein group count by biological replicate
coverage_analysis <- report %>%
  group_by(Sample_Type, Strategy, Biological_Replicate) %>%
  summarise(
    protein_groups = n_distinct(Protein.Group),
    precursors = n_distinct(Precursor.Id)
  )

# Consistency across replicates
overlap_analysis <- report %>%
  group_by(Sample_Type, Strategy) %>%
  summarise(
    total_proteins = n_distinct(Protein.Group),
    shared_proteins = sum(table(Protein.Group) == max(Biological_Replicate))
  )
```

**Expected**: +5-15% protein groups with optimized methods

#### 2. Biological Variability

**Inter-replicate Consistency**:
```r
# Pearson correlation between biological replicates
cor_matrix <- cor(
  intensity_matrix,
  use = "pairwise.complete.obs",
  method = "pearson"
)

# Expected correlation
mean_correlation <- mean(cor_matrix[lower.tri(cor_matrix)])
```

**Expected**: r > 0.85 for good biological replicates

#### 3. Dynamic Range Coverage

**Intensity Distribution**:
```r
# Dynamic range analysis
dynamic_range <- report %>%
  group_by(Sample_Type, Strategy) %>%
  summarise(
    min_intensity = min(PG.MaxLFQ, na.rm = TRUE),
    max_intensity = max(PG.MaxLFQ, na.rm = TRUE),
    log10_range = log10(max_intensity / min_intensity)
  )
```

**Expected**: Similar or broader dynamic range with optimized methods

#### 4. Missing Value Pattern

**Systematic vs Random Missing**:
```r
# Missing value heatmap
missing_pattern <- report %>%
  select(Protein.Group, Sample_ID, PG.MaxLFQ) %>%
  pivot_wider(
    names_from = Sample_ID,
    values_from = PG.MaxLFQ
  ) %>%
  mutate(
    n_missing = rowSums(is.na(.)),
    is_MCAR = chisq.test(missing_indicator)$p.value > 0.05
  )
```

**Expected**: Random missing (MCAR) preferred over systematic

---

## Tier 3: Method Development Optimization (Week 5-6)

### 목적
- New application에 optimizer 적용
- Edge case 발견 및 troubleshooting
- User experience feedback

### Use Case Examples

#### Use Case 1: Ultra-Short Gradient (15min)

**Challenge**: Very short RT window, high precursor density
**Test parameters**:
- RT bin width: 2.5 min (instead of 5 min)
- Window count: 12-15 per bin
- Strategy: Quantile (most robust)

**Validation metrics**:
- Coverage >85%
- DPPP satisfaction >65%
- Cycle time feasibility check

#### Use Case 2: Ultra-Long Gradient (120min)

**Challenge**: Wide RT distribution, variable precursor density
**Test parameters**:
- RT bin width: 7.5-10 min
- Window count: 25-30 per bin
- Strategy: Smoothing (smooth transitions)

**Validation metrics**:
- Coverage >92%
- DPPP satisfaction >75%
- Window width consistency (CV <0.35)

#### Use Case 3: Narrow m/z Range (400-800 Da)

**Challenge**: Peptide-focused analysis (e.g., MHC peptides)
**Test parameters**:
- m/z range: 400-800 Da
- Window width: 2-5 Da (narrow-DIA)
- Strategy: Coverage (maximize)

**Validation metrics**:
- Coverage of target m/z range >98%
- Small peptide identification (+20-30%)

#### Use Case 4: High-Load Sample (5 μg on-column)

**Challenge**: Overloading, wider chromatographic peaks
**Test parameters**:
- Target DPPP: 10.0 (higher than standard 7.0)
- Cycle time tolerance: Allow longer
- Strategy: Quantile (robust to overloading)

**Validation metrics**:
- DPPP satisfaction >70% at target 10.0
- No peak saturation
- Linear quantification range

### User Experience Metrics

#### 1. Configuration Ease

**Survey Questions** (1-5 scale):
1. Interactive builder가 사용하기 쉬웠나요?
2. YAML 파일을 이해하고 수정하기 쉬웠나요?
3. Error messages가 도움이 되었나요?
4. Documentation이 충분했나요?
5. 전체 workflow를 얼마나 빨리 이해했나요? (minutes)

**Target scores**:
- Average score >4.0 / 5.0
- Time to proficiency <30 minutes

#### 2. Computational Performance

**Timing Benchmarks**:
```r
# Measure each stage
timing_log <- list(
  stage1_validation = 3.2,  # seconds
  stage2_planning = 0.1,
  stage3_optimization = 0.6,  # per strategy
  stage4_visualization = 16.7,
  total_pipeline = 25.0
)
```

**Targets**:
- Stage 1: <10 seconds (for 100K precursors)
- Stage 2: <1 second
- Stage 3: <5 seconds per strategy
- Stage 4: <30 seconds
- Total: <2 minutes for single gradient + 4 strategies

#### 3. Method File Compatibility

**Thermo Orbitrap Import Test**:
1. Export CSV from optimizer
2. Import to Xcalibur Method Editor
3. Verify all fields populated correctly
4. Check for warnings/errors
5. Successfully acquire test data

**Success criteria**: 100% import success rate

---

## Comprehensive Comparison Matrix

### Summary Table Template

| Metric Category | Current Method | Optimized Method | Improvement | p-value |
|----------------|----------------|------------------|-------------|---------|
| **Tier 1: Standard QC** | | | | |
| Precursor IDs (30min) | 8,490 ± 120 | 9,177 ± 85 | +8.1% | <0.001 |
| Protein Groups (30min) | 2,098 ± 45 | 2,275 ± 32 | +8.4% | <0.001 |
| Median CV% (30min) | 15.5 ± 1.2% | 13.3 ± 0.9% | -14.2% | <0.01 |
| DPPP Satisfaction (30min) | 45% | 72% | +60% | <0.001 |
| Precursor IDs (60min) | 16,800 ± 250 | 18,500 ± 180 | +10.1% | <0.001 |
| Protein Groups (60min) | 3,200 ± 80 | 3,520 ± 60 | +10.0% | <0.001 |
| Median CV% (60min) | 14.2 ± 1.0% | 12.5 ± 0.8% | -12.0% | <0.01 |
| DPPP Satisfaction (60min) | 56% | 75% | +34% | <0.001 |
| **Tier 2: Biological Samples** | | | | |
| Liver Proteins | 4,200 ± 150 | 4,620 ± 120 | +10.0% | <0.01 |
| Brain Proteins | 3,800 ± 180 | 4,180 ± 140 | +10.0% | <0.01 |
| Plasma Proteins | 580 ± 45 | 680 ± 38 | +17.2% | <0.001 |
| Biological Replicate r | 0.87 ± 0.03 | 0.91 ± 0.02 | +4.6% | <0.05 |
| **Tier 3: Edge Cases** | | | | |
| 15min Gradient Coverage | 82% | 88% | +7.3% | <0.05 |
| 120min Gradient Proteins | 5,800 | 6,400 | +10.3% | <0.01 |
| Narrow m/z (400-800) Coverage | 92% | 98% | +6.5% | <0.01 |

---

## Statistical Analysis

### Power Analysis

**Sample size calculation** (for Tier 1):
```r
# Expected effect size: 10% improvement in protein IDs
# Alpha: 0.05
# Power: 0.80

library(pwr)
pwr.t.test(
  d = 0.10 / sd_current,  # Effect size
  sig.level = 0.05,
  power = 0.80,
  type = "two.sample"
)

# Result: n = 3 replicates per condition (minimum)
# Recommendation: n = 3-5 for robustness
```

### Hypothesis Testing

**Primary Hypothesis** (Tier 1):
- **H0**: Optimized method produces same number of protein IDs as current method
- **H1**: Optimized method produces >5% more protein IDs
- **Test**: One-sided t-test
- **Significance**: α = 0.05

**Secondary Hypotheses**:
1. CV% reduction (paired t-test)
2. DPPP satisfaction improvement (proportion test)
3. Missing value reduction (Wilcoxon signed-rank test)

### Multiple Testing Correction

**Bonferroni Correction**:
```r
# Testing 4 primary metrics across 3 gradients = 12 tests
alpha_corrected <- 0.05 / 12  # = 0.0042
```

**Benjamini-Hochberg FDR**:
```r
# More lenient, controls false discovery rate
p_values_adjusted <- p.adjust(p_values, method = "BH")
```

---

## Data Collection & Reporting

### Required Data Files

**From DIA-NN**:
1. `report.parquet` or `report.tsv` - Main precursor report
2. `pg_matrix.tsv` - Protein group matrix
3. `pr_matrix.tsv` - Precursor matrix (optional)
4. `stats.tsv` - Run statistics

**From Optimizer**:
1. Configuration YAML files (current vs optimized)
2. Method CSV files (exported windows)
3. Visualization plots (24 plots per gradient)
4. Batch processing summary

**Metadata**:
1. Sample information (type, amount, preparation date)
2. Run information (date, instrument, operator)
3. Method parameters (gradient, cycle time, resolution)

### Reporting Template

**Excel Workbook Structure**:

**Sheet 1: Summary**
- Overall metrics comparison
- Statistical test results
- Recommendations

**Sheet 2: Tier 1 Results**
- Standard QC sample data
- Technical replicate statistics
- DPPP achievement

**Sheet 3: Tier 2 Results**
- Biological sample comparison
- Replicate consistency
- Dynamic range analysis

**Sheet 4: Tier 3 Results**
- Edge case performance
- User experience scores
- Computational performance

**Sheet 5: Raw Data**
- All measurements
- Run-level details
- Quality control flags

---

## Timeline & Resource Requirements

### Proposed Schedule (6 weeks)

**Week 1-2: Tier 1 Validation**
- Day 1-3: QC sample acquisition and preparation
- Day 4-6: Instrument runs (3 gradients × 2 methods × 3 reps = 18 runs)
- Day 7-10: Data analysis and initial report
- Day 11-14: Statistical analysis and interpretation

**Week 3-4: Tier 2 Biological Diversity**
- Day 15-17: Sample preparation (tissues, cells, clinical)
- Day 18-24: Instrument runs (variable, ~30-40 runs)
- Day 25-28: Data analysis and comparison

**Week 5-6: Tier 3 Method Development**
- Day 29-31: Edge case testing (4-6 different conditions)
- Day 32-35: User experience testing (2-3 users)
- Day 36-40: Final data analysis and comprehensive report
- Day 41-42: Presentation and recommendations

### Resource Requirements

**Personnel**:
- 1 proteomics scientist (full-time, 6 weeks)
- 1 bioinformatician (part-time, 2-3 weeks)
- Lab manager (coordination, 10% time)

**Consumables** (estimated):
- Standard samples: $500-1,000
- LC-MS consumables: $2,000-3,000 (columns, vials, solvents)
- Reagents: $500-1,000 (enzymes, standards)

**Instrument Time**:
- ~80-100 runs total
- Estimated: 60-100 hours instrument time
- Assuming 30-90 min per run

**Computational**:
- DIA-NN processing: Standard workstation (16 GB RAM, 8 cores)
- Optimizer: Any modern laptop (4 GB RAM sufficient)
- Storage: ~500 GB for raw files + results

---

## Success Criteria

### Minimum Success Threshold

**Optimizer is considered successful if**:
1. ✅ Precursor IDs: +5% improvement (any gradient)
2. ✅ DPPP satisfaction: >70% achieved
3. ✅ CV% reduction: -10% or better
4. ✅ User satisfaction: >4.0 / 5.0 average score
5. ✅ No compatibility issues with Thermo instruments

### Optimal Success Threshold

**Optimizer exceeds expectations if**:
1. 🌟 Precursor IDs: +10% improvement (all gradients)
2. 🌟 Protein groups: +8% improvement
3. 🌟 DPPP satisfaction: >75% achieved
4. 🌟 CV% reduction: -15% or better
5. 🌟 Missing values: -20% reduction
6. 🌟 User satisfaction: >4.5 / 5.0
7. 🌟 Time to proficiency: <20 minutes

---

## Risk Mitigation

### Potential Issues & Solutions

**Issue 1: Instrument availability**
- **Risk**: Limited instrument time
- **Mitigation**: Use overnight runs, queue optimization
- **Backup**: Reduce technical replicates to 2 (instead of 3)

**Issue 2: Sample variability**
- **Risk**: High biological variability masks optimizer effect
- **Mitigation**: Use standard QC samples (Tier 1) as primary evidence
- **Backup**: Increase biological replicates if CV% >20%

**Issue 3: DIA-NN version compatibility**
- **Risk**: Different versions produce different results
- **Mitigation**: Document DIA-NN version, library version
- **Backup**: Reprocess all data with same version

**Issue 4: Method import failure**
- **Risk**: CSV format incompatible with Xcalibur
- **Mitigation**: Test import before running experiments
- **Backup**: Manual entry (time-consuming but feasible)

---

## Conclusion

### Recommended Validation Path

**If time/resources are LIMITED**:
- **Focus on Tier 1 only** (2 weeks)
- Use lab's routine QC sample
- Test only one gradient length
- 3 technical replicates per method
- **Deliverable**: Statistical comparison + recommendation

**If MODERATE resources available**:
- **Tier 1 + selected Tier 2** (4 weeks)
- QC sample + 2 biological sample types
- 2 gradient lengths (30min, 60min)
- **Deliverable**: Comprehensive validation report

**If FULL validation desired**:
- **All 3 Tiers** (6 weeks)
- Complete testing matrix
- Publication-quality data
- **Deliverable**: Scientific manuscript draft

### Next Steps

1. ✅ Decide on validation tier (1, 1+2, or full)
2. ✅ Select sample types based on lab's research focus
3. ✅ Reserve instrument time
4. ✅ Generate optimized methods using DIA Window Optimizer
5. ✅ Execute validation experiments
6. ✅ Analyze data and provide feedback

---

**Questions or need clarification? Contact project team for support!**

---

**Document Version**: 1.0
**Last Updated**: 2025-11-28
**Authors**: DIA Window Optimizer Development Team
