# Domain Concepts - DIA Window Optimization

## Overview

This document explains core concepts and formulas used in DIA window optimization, with emphasis on corrected logic and common misconceptions.

---

## 1. DPPP (Data Points Per Peak)

### Definition

**DPPP** = Number of data points acquired across a chromatographic peak

### Formula

```
DPPP = (Peak Width × 1.7) / Cycle Time

where:
- Peak Width = FWHM (Full Width at Half Maximum) in seconds
- 1.7 factor = Chromatographic peak width ≈ 1.7 × FWHM
- Cycle Time = Time to complete one full MS1 + all MS2 scans (seconds)
```

### Physical Meaning

- **Higher DPPP** = More scans across the peak = Better quantification accuracy
- **Lower DPPP** = Fewer scans across the peak = Poorer quantification

### DPPP Targets

| Mode | Target DPPP | Purpose |
|------|------------|---------|
| **Quant Mode** | ≥ 7.0 | Optimal quantification accuracy (default, preferred) |
| **Balanced Mode** | ≥ 4.0 | Balance between ID and Quant |
| **ID Mode** | ≥ 1.5 | Maximum precursor identification |

---

## 2. Cycle Time

### Definition

**Cycle Time** = Time required to complete one full DIA cycle (1 × MS1 scan + all MS2 window scans)

### Calculation

Depends on **acquisition mode**:

#### Sequential Acquisition (Traditional Orbitrap, Exploris)
```
Cycle Time = MS1_time + (n_windows × MS2_time)

Example (Exploris):
- MS1 time: 50 ms
- MS2 time per window: 20 ms
- Windows: 20

→ Cycle Time = 50 + (20 × 20) = 450 ms = 0.45 sec
```

#### Parallel Acquisition (Astral)
```
Cycle Time = max(MS1_time, n_windows × MS2_time)

Example (Astral):
- MS1 time: 5 ms
- MS2 time per window: 3 ms
- Windows: 20

→ Cycle Time = max(5, 20 × 3) = max(5, 60) = 60 ms = 0.06 sec

Note: MS1 and MS2 run simultaneously, so total time is the maximum of the two
```

### Relationship with DPPP

**Critical Insight**:

```
DPPP ∝ 1 / Cycle Time

Shorter Cycle Time → Higher DPPP → Better Quantification
Longer Cycle Time → Lower DPPP → Poorer Quantification
```

**This is counter-intuitive!**

- To achieve **higher DPPP**, you need **shorter cycle time**
- Shorter cycle time means **fewer windows** (less time for MS2 scans)
- This creates a trade-off between DPPP and coverage

---

## 3. Scan Rate

### Definition

**Scan Rate** = Number of MS2 scans the instrument can perform per second (Hz)

### Formula

```
Scan Rate (Hz) = n_windows / Cycle Time (sec)

NOT: 1 / Cycle Time  ❌ (This is cycle frequency, not scan rate)
```

### Example

```
Cycle Time = 1 sec
Windows = 300

Scan Rate = 300 windows / 1 sec = 300 Hz

This means the instrument must be capable of 300 MS2 scans per second.
```

### Maximum Window Count from Scan Rate

```
max_windows = max_scan_rate × cycle_time × safety_factor

where:
- max_scan_rate: Instrument specification (e.g., Astral = 100 Hz)
- cycle_time: Desired cycle time (sec)
- safety_factor: 0.8 (recommended, don't run at 100% capacity)
```

### Example (Astral)

```
max_scan_rate = 100 Hz
cycle_time = 2.5 sec
safety_factor = 0.8

max_windows = 100 × 2.5 × 0.8 = 200 windows

Without safety factor: 100 × 2.5 = 250 windows (risky!)
```

---

## 4. Window Count vs Coverage Trade-off

### The Fundamental Tension

```
More Windows:
✅ Better m/z coverage (smaller isolation width)
✅ Less co-fragmentation (fewer precursors per window)
❌ Longer cycle time → Lower DPPP → Poorer quantification

Fewer Windows:
✅ Shorter cycle time → Higher DPPP → Better quantification
❌ Poorer m/z coverage (wider isolation width)
❌ More co-fragmentation (more precursors per window)
```

### Solutions to This Trade-off

1. **Adjust Injection Time (MS2 time)**
   - Reduce MS2 time → Fit more windows in same cycle time
   - Increase MS2 time → Better spectrum quality but fewer windows

2. **Variable Window Width**
   - Narrow windows in high-density m/z regions
   - Wide windows in low-density m/z regions
   - Maintains coverage while reducing window count

3. **RT-dependent Window Schemes**
   - More windows during high-precursor RT regions
   - Fewer windows during low-precursor RT regions
   - Optimizes DPPP across the gradient

---

## 5. Satisfaction Ratio

### Definition

**Satisfaction Ratio** = Proportion of precursors achieving target DPPP

### Corrected Logic

**Target DPPP is a MINIMUM threshold**:

```r
# CORRECT ✅
meets_target <- dppp >= target_dppp
# Higher DPPP is better, no upper limit

# WRONG ❌
meets_target <- dppp >= (target - tol) & dppp <= (target + tol)
# Don't penalize high DPPP!
```

### Example

```
Target DPPP: 7.5
Current DPPP distribution: mean = 23.5

CORRECT logic:
- All precursors have DPPP ≥ 7.5
- Satisfaction = 100% ✅

WRONG logic (old):
- Target range [7.2, 7.8] with tolerance 0.3
- No precursors in this narrow range
- Satisfaction = 0% ❌
```

---

## 6. Critical FWHM and Quantile Direction

### The Problem

Given:
- Target: 70% of precursors should have DPPP ≥ 7.5
- FWHM distribution varies (some short, some long)

Question: Which precursors do we need to "rescue"?

### Answer: Short FWHM Precursors

```
DPPP = (1.7 × FWHM) / cycle_time

Short FWHM → Low DPPP (hard to achieve target)
Long FWHM → High DPPP (easy to achieve target)
```

### Critical FWHM Calculation

**70% satisfaction means**:
- Rescue the top 70% (longer FWHM)
- Abandon the bottom 30% (shortest FWHM)

```r
# CORRECT ✅
critical_fwhm <- quantile(fwhm, 1 - target_satisfaction)
# For 70% satisfaction → 30th percentile
# This is the shortest FWHM among the "rescued" 70%

# WRONG ❌
critical_fwhm <- quantile(fwhm, target_satisfaction)
# For 70% satisfaction → 70th percentile
# This represents long FWHM (already have high DPPP!)
```

### Required Cycle Time Calculation

```r
# Find the MAXIMUM cycle time that achieves target DPPP
# for the critical (shortest rescued) FWHM

required_max_cycle_time <- (1.7 * critical_fwhm) / target_dppp
```

### Example

```
FWHM distribution: 10-15 sec (simplified)
Target: DPPP ≥ 7.5 for 70% precursors

Step 1: Find critical FWHM
critical_fwhm = quantile(fwhm, 0.30) = 11.0 sec
(30th percentile = shortest FWHM among top 70%)

Step 2: Calculate required cycle time
required_cycle_time = (1.7 × 11.0) / 7.5 = 2.49 sec

Interpretation:
- If cycle_time ≤ 2.49 sec, the critical FWHM (11.0 sec) will have DPPP ≥ 7.5
- All longer FWHMs will automatically have DPPP ≥ 7.5
- This ensures 70% satisfaction
```

---

## 7. Stage 2 Scope and Responsibilities

### What Stage 2 Does

1. **Diagnose Current State**
   - Calculate current DPPP distribution using existing cycle_time
   - Compute satisfaction ratio with current settings
   - Show user where they stand

2. **Calculate Required Cycle Time**
   - Find cycle_time needed to achieve target satisfaction
   - Report adjustment direction (REDUCE/INCREASE/MAINTAIN)

### What Stage 2 Does NOT Do (Deferred to Phase 3A)

- ❌ Calculate final window count
- ❌ Check instrument feasibility
- ❌ Validate DPPP with proposed cycle_time
- ❌ Optimize injection time

### Why This Separation?

**Stage 2** provides the **diagnostic information**:
- "You need cycle_time ≤ 2.5 sec to achieve 70% satisfaction at DPPP 7.5"

**Phase 3A** provides the **optimization**:
- "To achieve 2.5 sec cycle_time, you can:"
  1. Use 200 windows with current injection time
  2. Use 400 windows with 2× faster injection time
  3. Use 150 windows with 1.5× longer injection time

This allows users to:
- Understand the requirement first (Stage 2)
- Explore different implementation options (Phase 3A)

---

## 8. Instrument Specifications

### Thermo Astral

```yaml
Acquisition Mode: Parallel (MS1 and MS2 simultaneous)
Max Scan Rate: 100 Hz
MS1 Time: 5 ms
MS2 Time: 3 ms (default)
Min Window Width: 2 Da
Cycle Time Formula: max(MS1_time, n_windows × MS2_time)
```

**Characteristics**:
- Ultra-fast MS2 (3 ms)
- Parallel acquisition enables short cycles
- But: Window width constraint (≥2 Da) can be limiting

### Thermo Orbitrap Exploris

```yaml
Acquisition Mode: Sequential (MS1 then MS2)
Max Scan Rate: 25 Hz (optimized: 40 Hz)
MS1 Time: 50 ms
MS2 Time: 20 ms (default)
Min Window Width: 1 Da
Cycle Time Formula: MS1_time + (n_windows × MS2_time)
```

**Characteristics**:
- Moderate scan rate
- Sequential acquisition = additive cycle time
- More flexible window width

### Traditional Orbitrap

```yaml
Acquisition Mode: Sequential
Max Scan Rate: 8 Hz (optimized: 12 Hz)
MS1 Time: 100 ms
MS2 Time: 80 ms (default)
Min Window Width: 1 Da
Cycle Time Formula: MS1_time + (n_windows × MS2_time)
```

**Characteristics**:
- Slower but high resolution
- Long cycle times typical
- Best suited for lower DPPP targets (4-5)

---

## 9. Common Misconceptions

### ❌ Misconception 1: "Higher DPPP needs more windows"

**Reality**: Higher DPPP needs **shorter cycle time**, which often means **fewer windows**

```
DPPP = (1.7 × FWHM) / cycle_time

To increase DPPP:
→ Decrease cycle_time
→ Cycle_time = MS1 + (n_windows × MS2)
→ To decrease cycle_time, reduce n_windows OR reduce MS2_time
```

### ❌ Misconception 2: "70% satisfaction → use 70th percentile FWHM"

**Reality**: Use **30th percentile** (1 - 0.70)

```
70% satisfaction = rescue 70%, abandon 30%
→ Find the shortest FWHM among the rescued 70%
→ This is the 30th percentile
```

### ❌ Misconception 3: "Target DPPP 7.5 means 7.5 ± tolerance"

**Reality**: Target DPPP is a **minimum threshold**

```
CORRECT: DPPP ≥ 7.5 is good (higher is better)
WRONG: DPPP must be in [7.2, 7.8] range
```

### ❌ Misconception 4: "Scan rate = 1 / cycle_time"

**Reality**: Scan rate = **n_windows / cycle_time**

```
Example:
cycle_time = 1 sec
n_windows = 300

CORRECT scan_rate = 300 / 1 = 300 Hz
WRONG scan_rate = 1 / 1 = 1 Hz

The instrument must scan 300 windows per second!
```

---

## 10. Workflow Summary

```
[User Experiment]
  Existing cycle_time (e.g., from DIA-NN metadata)
  FWHM distribution from precursors
           ↓
[Stage 2: DPPP Diagnosis]
  Step 1: Calculate current DPPP distribution
          → "Currently X% meet DPPP ≥ 7.5"

  Step 2: Calculate required cycle_time
          → "Need cycle_time ≤ Y sec for 70% satisfaction"
           ↓
[Phase 3A: Window Count Determination]
  Input: required_cycle_time from Stage 2

  Calculate: max_windows from scan rate constraint
  Check: feasibility (window width, instrument limits)
  Recommend: injection time adjustments if needed
           ↓
[Phase 3B: RT Binning]
  Segment RT into bins
           ↓
[Phase 3C: m/z Range Optimization]
  Optimize m/z ranges per RT segment
  Handle variable window widths
           ↓
[Phase 3D: Window Generation]
  Generate final isolation window scheme
```

---

## References

- **Spectronaut Manual**: DPPP definition and targets
- **Thermo Orbitrap Specifications**: Instrument timing parameters
- **DIA-NN Documentation**: FWHM calculation and quality metrics

**Version**: 2.0
**Last Updated**: 2025-10-15
**Author**: DIA Window Optimizer Development Team
