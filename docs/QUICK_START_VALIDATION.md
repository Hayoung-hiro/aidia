# Quick Start: Validation Experiment Guide

**Time Required**: 1 week (minimal validation)
**Resources**: HeLa digest standard + LC-MS instrument
**Goal**: Quick performance check before full deployment

---

## 🎯 Minimal Validation Protocol

### Day 1: Preparation

**Step 1: Generate Optimized Method**
```r
# Install R and required packages
install.packages(c("arrow", "dplyr", "ggplot2", "yaml"))

# Clone repository
git clone https://github.com/Hayoung-hiro/DIAoptimizer.git
cd DIAoptimizer

# Create configuration using interactive builder
source("scripts/config_builder.R")
run_config_builder()

# Follow prompts:
# - Input your DIA-NN report.parquet file
# - Select gradient length (e.g., 60min)
# - Choose "Coverage" strategy (recommended)
# - Enable plots: Yes
```

**Step 2: Review Generated Method**
- Check `results/[project_name]/` directory
- Find `60min_coverage_variable_thermo.csv`
- Import to Xcalibur Method Editor
- Verify window settings

**Step 3: Prepare Sample**
- **Recommended**: Pierce HeLa Protein Digest Standard
- **Amount**: 200 ng on-column
- **Replicates**: Prepare 6 aliquots (3 current + 3 optimized)

---

### Day 2-3: LC-MS Acquisition

**Batch Design** (6 runs total):
```
Run 1: HeLa_Current_Rep1
Run 2: HeLa_Current_Rep2
Run 3: HeLa_Current_Rep3
Run 4: HeLa_Optimized_Rep1
Run 5: HeLa_Optimized_Rep2
Run 6: HeLa_Optimized_Rep3
```

**Critical Parameters to Record**:
- Actual cycle time (from instrument log)
- Total gradient length
- MS1 resolution
- MS2 resolution
- Number of windows (Current vs Optimized)

---

### Day 4-5: Data Analysis

**Step 1: DIA-NN Processing**
```bash
# Run DIA-NN with same parameters for all files
diann --f *.raw \
      --lib your_library.tsv \
      --out report.parquet \
      --qvalue 0.01 \
      --matrices \
      --temp /tmp \
      --threads 8
```

**Step 2: Quick Comparison**
```r
# Load DIA-NN output
library(arrow)
library(dplyr)

report <- read_parquet("report.parquet")

# Compare precursor counts
comparison <- report %>%
  mutate(Method = ifelse(grepl("Current", File.Name), "Current", "Optimized")) %>%
  group_by(Method) %>%
  summarise(
    Precursors = n_distinct(Precursor.Id),
    Proteins = n_distinct(Protein.Group),
    Mean_Intensity = mean(Precursor.Quantity, na.rm = TRUE)
  )

print(comparison)

# Expected output:
#   Method      Precursors  Proteins  Mean_Intensity
#   Current     16800       3200      2.5e6
#   Optimized   18500       3520      2.7e6
#   Improvement +10.1%      +10.0%    +8.0%
```

**Step 3: CV% Analysis**
```r
# Calculate technical replicate CV%
cv_analysis <- report %>%
  group_by(Method, Protein.Group) %>%
  summarise(
    Mean_Int = mean(PG.MaxLFQ, na.rm = TRUE),
    SD_Int = sd(PG.MaxLFQ, na.rm = TRUE),
    CV_pct = (SD_Int / Mean_Int) * 100,
    n_detected = n()
  ) %>%
  filter(n_detected == 3)  # Only proteins in all 3 replicates

# Median CV% per method
median_cv <- cv_analysis %>%
  group_by(Method) %>%
  summarise(Median_CV = median(CV_pct, na.rm = TRUE))

print(median_cv)

# Expected output:
#   Method      Median_CV
#   Current     14.2%
#   Optimized   12.5%
#   Improvement -12.0%
```

**Step 4: DPPP Verification**
```r
# Calculate actual DPPP from results
dppp_check <- report %>%
  mutate(
    Method = ifelse(grepl("Current", File.Name), "Current", "Optimized"),
    # Cycle time from instrument (need to check log)
    Cycle_Time_Sec = ifelse(Method == "Current", 1.80, 1.35),
    Actual_DPPP = (1.7 * FWHM * 60) / Cycle_Time_Sec
  ) %>%
  group_by(Method) %>%
  summarise(
    Mean_DPPP = mean(Actual_DPPP, na.rm = TRUE),
    Median_DPPP = median(Actual_DPPP, na.rm = TRUE),
    Satisfaction_70pct = sum(Actual_DPPP >= 7.0) / n()
  )

print(dppp_check)

# Expected output:
#   Method      Mean_DPPP  Median_DPPP  Satisfaction_70pct
#   Current     6.8        6.5          0.46 (46%)
#   Optimized   7.5        7.2          0.75 (75%)
```

---

### Day 6-7: Report Generation

**Create Summary Report**:
```r
# Generate comparison plots
library(ggplot2)

# Plot 1: Precursor count comparison
p1 <- ggplot(comparison, aes(x = Method, y = Precursors, fill = Method)) +
  geom_bar(stat = "identity") +
  geom_text(aes(label = Precursors), vjust = -0.5) +
  labs(title = "Precursor Identification",
       y = "Number of Precursors") +
  theme_minimal()

# Plot 2: CV% distribution
p2 <- ggplot(cv_analysis, aes(x = CV_pct, fill = Method)) +
  geom_density(alpha = 0.5) +
  labs(title = "Technical Replicate CV%",
       x = "CV%", y = "Density") +
  theme_minimal()

# Plot 3: DPPP satisfaction
p3 <- ggplot(dppp_check, aes(x = Method, y = Satisfaction_70pct, fill = Method)) +
  geom_bar(stat = "identity") +
  geom_hline(yintercept = 0.70, linetype = "dashed", color = "red") +
  labs(title = "DPPP Target Achievement",
       y = "% Precursors ≥7.0 DPPP") +
  theme_minimal()

# Save plots
ggsave("validation_precursors.png", p1, width = 6, height = 4, dpi = 300)
ggsave("validation_cv.png", p2, width = 6, height = 4, dpi = 300)
ggsave("validation_dppp.png", p3, width = 6, height = 4, dpi = 300)
```

---

## 📊 Decision Criteria

### ✅ Proceed to Full Deployment IF:

1. **Precursor IDs**: ≥5% improvement
   - Example: 16,800 → 17,640+ (+840)

2. **Protein Groups**: ≥3% improvement
   - Example: 3,200 → 3,296+ (+96)

3. **CV% Reduction**: ≥10% reduction
   - Example: 14.2% → 12.8% or better

4. **DPPP Satisfaction**: ≥70% achieved
   - Example: 46% → 70%+ (target met)

5. **No Compatibility Issues**:
   - Method CSV imports successfully
   - All windows within m/z range
   - Cycle time achievable

### ⚠️ Troubleshoot IF:

1. **Improvement <3%**:
   - Check if current method already well-optimized
   - Try different strategy (Outlier instead of Coverage)
   - Verify cycle time setting

2. **CV% Increased**:
   - Check sample preparation consistency
   - Verify replicate injection order
   - Review chromatographic performance

3. **DPPP Satisfaction <60%**:
   - Actual cycle time longer than expected?
   - Check instrument load factor setting
   - Consider reducing window count

---

## 📋 Quick Checklist

**Before Starting**:
- [ ] DIA Window Optimizer installed
- [ ] Sample prepared (200 ng HeLa, 6 aliquots)
- [ ] Instrument time reserved (6 runs)
- [ ] DIA-NN ready for processing
- [ ] Current method documented

**During Experiment**:
- [ ] Random run order (avoid batch effects)
- [ ] Consistent sample volume
- [ ] Record actual cycle times
- [ ] QC checks (pressure, signal intensity)

**After Acquisition**:
- [ ] Raw files backed up
- [ ] DIA-NN processing completed
- [ ] Comparison metrics calculated
- [ ] Plots generated
- [ ] Decision made (deploy or troubleshoot)

---

## 🎓 Example Results Interpretation

### Scenario 1: Clear Win ✅
```
Precursors: 16,800 → 18,500 (+10.1%)
Proteins: 3,200 → 3,520 (+10.0%)
CV%: 14.2% → 12.5% (-12.0%)
DPPP: 46% → 75% (+63% relative improvement)

Decision: Deploy optimized method immediately
```

### Scenario 2: Marginal Improvement ⚠️
```
Precursors: 16,800 → 17,300 (+3.0%)
Proteins: 3,200 → 3,280 (+2.5%)
CV%: 14.2% → 13.8% (-2.8%)
DPPP: 46% → 68% (+48% relative improvement)

Decision: DPPP improved significantly, but IDs marginal
Action: Test on 2-3 biological samples to confirm benefit
```

### Scenario 3: No Improvement ❌
```
Precursors: 16,800 → 16,900 (+0.6%)
Proteins: 3,200 → 3,210 (+0.3%)
CV%: 14.2% → 14.5% (+2.1%)
DPPP: 46% → 48% (+4% relative improvement)

Possible causes:
1. Current method already near-optimal
2. Wrong input data (used optimized data to generate method?)
3. Actual cycle time different from expected
4. Sample quality issues

Action: Troubleshoot or contact support
```

---

## 💡 Tips for Success

### Sample Preparation
✅ **DO**:
- Use commercial standard for first test (reproducible)
- Prepare all replicates from same vial
- Randomize run order
- Use same LC column for all runs

❌ **DON'T**:
- Mix different sample batches
- Run all "Current" first, then "Optimized" (batch effect!)
- Change LC settings between runs
- Skip blank runs between methods

### Data Analysis
✅ **DO**:
- Use same DIA-NN version for all processing
- Same library for all searches
- Document all parameters
- Check raw data quality (TIC, peak widths)

❌ **DON'T**:
- Cherry-pick "best" replicate
- Change FDR thresholds between methods
- Compare different gradient lengths
- Ignore failed injections (re-run instead)

### Troubleshooting
**Problem**: Method import fails
- **Solution**: Check CSV encoding (UTF-8), verify m/z ranges

**Problem**: Cycle time too long
- **Solution**: Reduce window count, increase load factor to 90%

**Problem**: Low DPPP satisfaction
- **Solution**: Verify actual instrument cycle time matches expected

---

## 📞 Support Resources

**Documentation**:
- [Full Validation Strategy](VALIDATION_STRATEGY.md) - Comprehensive 6-week plan
- [Config Builder Guide](CONFIG_BUILDER_GUIDE.md) - Interactive YAML builder
- [YAML Migration Guide](YAML_MIGRATION_GUIDE.md) - Convert existing configs

**Example Data**:
- `data/30min_report.parquet` - Example DIA-NN output
- `config/production_test.yaml` - Example configuration
- `results_production_test/` - Example outputs

**GitHub Issues**:
- Report bugs: https://github.com/Hayoung-hiro/DIAoptimizer/issues
- Feature requests: Same link
- Questions: Use discussion board

---

**Good luck with your validation experiment!** 🚀

If results are positive, proceed to [VALIDATION_STRATEGY.md](VALIDATION_STRATEGY.md) Tier 2 for comprehensive testing.
