# m/z Optimization: Global vs Local Strategies

**Document Version**: 1.0
**Date**: 2025-11-15
**Implementation**: `R/stage3_window_optimization.R`

---

## 📊 Overview

Stage 3 m/z range optimization supports **two fundamentally different approaches** depending on the strategy:

| Strategy | Optimization Type | Description |
|----------|-------------------|-------------|
| **Smoothing** | 🌐 **GLOBAL** | Continuous RT function → Smooth → Sample at bins |
| **Quantile** | 📍 **LOCAL** | Independent calculation per RT bin |
| **Coverage** | 📍 **LOCAL** | Independent calculation per RT bin |
| **Outlier** | 📍 **LOCAL** | Independent calculation per RT bin |

---

## 🎯 Why Different Approaches?

### LOCAL Optimization (Quantile, Coverage, Outlier)

**Principle**: Each RT bin has **different precursor characteristics**

```
RT Bin 1 (early gradient, 15-20 min):
  ├─ Precursor m/z distribution: 400-800 Da (low molecular weight)
  ├─ Density: High (many early-eluting peptides)
  └─ Optimal m/z range: P5=402 Da, P95=798 Da

RT Bin 2 (late gradient, 55-60 min):
  ├─ Precursor m/z distribution: 600-1200 Da (high molecular weight)
  ├─ Density: Medium
  └─ Optimal m/z range: P5=615 Da, P95=1185 Da
```

**Calculation**: Use **only precursors within each bin**
- ✅ Accurate representation of bin-specific precursor properties
- ✅ Adaptive to natural RT-m/z correlation
- ✅ No smoothing needed (bin boundaries can have jumps)

**Example Code**:
```r
for (bin in RT_bins) {
  bin_precursors <- filter(data, rt_group == bin)
  mz_min[bin] <- quantile(bin_precursors$Mz, 0.05)  # This bin only!
  mz_max[bin] <- quantile(bin_precursors$Mz, 0.95)
}
```

---

### GLOBAL Optimization (Smoothing)

**Principle**: m/z changes **gradually and continuously** across RT

```
RT as continuous variable:
  RT=15.0 min → m/z range: 400-800 Da
  RT=15.5 min → m/z range: 405-810 Da  (gradual change)
  RT=16.0 min → m/z range: 410-820 Da
  ...
  RT=59.5 min → m/z range: 610-1180 Da
  RT=60.0 min → m/z range: 615-1185 Da
```

**Goal**: Create a **smooth, continuous m/z function** across the entire gradient

**Why?**
1. **Instrument-friendly**: Gradual m/z transitions reduce acquisition complexity
2. **Biological reality**: Peptides elute continuously, not in discrete bins
3. **Edge handling**: Smooth transitions at RT bin boundaries

**Calculation**: Three-step process
1. **Fine RT sampling**: Many RT points across entire gradient (high-resolution)
2. **Sliding window**: Calculate m/z at each RT using nearby precursors
3. **Smoothing**: Apply Savitzky-Golay filter to create smooth curve
4. **Sampling**: Assign values to RT bins from smoothed curve

---

## 🔬 Detailed Comparison

### LOCAL Optimization Process

```
Input: Precursor data + RT bins (N=5)

Step 1: RT Binning
───────────────────────────────────────────
RT Bin 1: 15.0-20.0 min → 3,245 precursors
RT Bin 2: 20.0-25.0 min → 4,127 precursors
RT Bin 3: 25.0-30.0 min → 5,891 precursors
RT Bin 4: 30.0-35.0 min → 4,623 precursors
RT Bin 5: 35.0-40.0 min → 3,118 precursors

Step 2: Calculate m/z per bin (INDEPENDENT)
───────────────────────────────────────────
Bin 1: Use 3,245 precursors only
  → P5 = 402.3 Da, P95 = 798.5 Da

Bin 2: Use 4,127 precursors only
  → P5 = 435.7 Da, P95 = 845.2 Da

Bin 3: Use 5,891 precursors only
  → P5 = 478.1 Da, P95 = 912.6 Da

... (independent for each bin)

Output: N=5 discrete m/z ranges
  mz_min = [402.3, 435.7, 478.1, 521.4, 568.2]
  mz_max = [798.5, 845.2, 912.6, 985.3, 1065.8]
```

**Characteristics**:
- ✅ Accurate per-bin precursor representation
- ✅ Fast computation (bin-by-bin)
- ✅ Handles different precursor densities naturally
- ⚠️ Potential jumps at bin boundaries (acceptable for these strategies)

---

### GLOBAL Optimization Process

```
Input: Precursor data + RT bins (N=5)

Step 1: Fine RT Sampling (entire gradient)
───────────────────────────────────────────
RT range: 15.0-40.0 min (25 min span)
Sampling interval: 0.5 min (adaptive)

RT points: [15.0, 15.5, 16.0, ..., 39.5, 40.0]
→ N=51 high-resolution points

Step 2: Sliding Window m/z Calculation
───────────────────────────────────────────
For each RT point, use precursors within ±1.25 min window:

RT=15.0 → precursors in [13.75-16.25] → P5=398 Da, P95=792 Da
RT=15.5 → precursors in [14.25-16.75] → P5=401 Da, P95=797 Da
RT=16.0 → precursors in [14.75-17.25] → P5=404 Da, P95=802 Da
...
RT=40.0 → precursors in [38.75-41.25] → P5=570 Da, P95=1068 Da

Result: High-resolution m/z curves
  mz_min_raw = [398, 401, 404, ..., 570]  (51 values)
  mz_max_raw = [792, 797, 802, ..., 1068]

Step 3: Savitzky-Golay Smoothing
───────────────────────────────────────────
Smooth high-resolution curves:
  window_size = 7 (adaptive)
  polynomial_order = 3

  mz_min_smooth = smooth(mz_min_raw)  ✅ Works! (51 ≥ 7)
  mz_max_smooth = smooth(mz_max_raw)

→ Smooth, continuous m/z functions

Step 4: Assign to RT Bins (interpolation)
───────────────────────────────────────────
Bin 1 center (17.5 min) → interpolate → mz_min=407 Da, mz_max=805 Da
Bin 2 center (22.5 min) → interpolate → mz_min=442 Da, mz_max=853 Da
Bin 3 center (27.5 min) → interpolate → mz_min=482 Da, mz_max=918 Da
Bin 4 center (32.5 min) → interpolate → mz_min=527 Da, mz_max=992 Da
Bin 5 center (37.5 min) → interpolate → mz_min=565 Da, mz_max=1058 Da

Output: N=5 smoothed m/z ranges from continuous function
```

**Characteristics**:
- ✅ Smooth, continuous m/z transitions
- ✅ No jumps at bin boundaries
- ✅ Instrument-friendly gradual changes
- ✅ Always works (sufficient high-resolution points)
- ⚠️ Slightly slower (more computation)
- ⚠️ Less bin-specific than LOCAL (by design)

---

## 📈 Visual Comparison

### LOCAL Optimization (Quantile Strategy)

```
m/z
│
│     Bin1    Bin2    Bin3    Bin4    Bin5
│   ┌────┐  ┌────┐  ┌────┐  ┌────┐  ┌────┐
│   │    │  │    │  │    │  │    │  │    │
│   │    │  │    │  │    │  │    │  │    │
│   └────┘  └────┘  └────┘  └────┘  └────┘
│       ↑ Jump ↑ Jump ↑ Jump ↑ Jump
│       (acceptable for quantile)
└──────────────────────────────────────────► RT
```

### GLOBAL Optimization (Smoothing Strategy)

```
m/z
│                    ╱──────────
│               ╱────
│          ╱────
│     ╱────
│─────
│  ↑ Smooth continuous curve
│  (no jumps at bin boundaries)
└──────────────────────────────────────────► RT
     Bin1    Bin2    Bin3    Bin4    Bin5
     Sample at bin centers from curve
```

---

## 🚀 Implementation Details

### Adaptive Parameters (GLOBAL Smoothing)

The implementation **automatically adapts** to gradient length:

| Gradient Length | RT Sampling Interval | Sliding Window | Expected Points |
|-----------------|---------------------|----------------|-----------------|
| ≤15 min (short) | 0.5 min | ±1.0 min | ~30 points |
| 15-40 min (medium) | 0.75 min | ±1.0-2.0 min | ~40 points |
| >40 min (long) | 1.0 min | ±2.0-3.0 min | ~50-100 points |

**30min Gradient Example** (RT span: 10 min):
```
Sampling interval: 0.5 min (short gradient)
RT points: 10 / 0.5 = 20 points
Sliding window: ±0.5 min (5% of 10 min)

Smoothing: window=7 (50% of 20 points)
→ ✅ SUCCESS (20 ≥ 7)
```

**Why this solves the original problem**:
```
OLD (LOCAL approach for smoothing):
  RT bins: 2 (from 5 min bin width)
  → smooth([value1, value2], window=3)
  → ❌ FAILS (2 < 3)

NEW (GLOBAL approach):
  RT points: 20 (fine sampling)
  → smooth([20 values], window=7)
  → ✅ SUCCESS (20 ≥ 7)
```

---

## 🔧 Configuration

### Config File (`config/optimization_config.json`)

```json
{
  "rt_binning": {
    "rt_bin_width_min": 5.0
  },

  "mz_optimization": {
    "strategies": ["quantile", "smoothing", "outlier", "coverage"],

    "quantile_lower": 0.05,
    "quantile_upper": 0.95,
    "target_coverage": 0.95,
    "outlier_threshold": 3.0,

    "smoothing_window": 7,
    "polynomial_order": 3,

    "_comment_smoothing": "Smoothing uses GLOBAL optimization (independent of RT bins)",
    "_note_smoothing": "Smoothing window applies to high-resolution RT sampling, not RT bins"
  }
}
```

**Key Points**:
- `rt_bin_width_min`: Affects final number of windows, NOT smoothing feasibility
- `smoothing_window`: Applies to **high-resolution RT points** (typically 20-100 points)
- Smoothing **always works** with GLOBAL approach (enough points guaranteed)

---

## 📊 When to Use Each Strategy

### Use LOCAL Strategies (Quantile, Coverage, Outlier) When:

✅ You want **accurate bin-specific m/z ranges**
✅ Precursor distribution varies significantly across RT
✅ Sharp m/z transitions at bin boundaries are acceptable
✅ Speed is important (faster computation)
✅ You have well-defined RT bins with different characteristics

**Example Use Case**:
```
Fractionated sample with distinct RT regions:
  - Early: Small peptides (400-700 Da)
  - Middle: Medium peptides (600-900 Da)
  - Late: Large peptides (800-1200 Da)

→ LOCAL quantile captures each region accurately
```

---

### Use GLOBAL Strategy (Smoothing) When:

✅ You want **smooth, continuous m/z transitions**
✅ Instrument performance benefits from gradual changes
✅ Bin boundaries should have seamless transitions
✅ Biological reality (continuous elution) is important
✅ You want elegant, publication-quality m/z curves

**Example Use Case**:
```
Standard proteomics with continuous elution:
  - Gradual increase in m/z across gradient
  - No sharp peptide class boundaries
  - Instrument prefers smooth m/z ramping

→ GLOBAL smoothing creates elegant continuous function
```

---

## 🧪 Comparison Example: 30min Gradient

### Scenario
- RT range: 11.9-21.8 min (10 min span)
- RT bin width: 5 min → **2 RT bins**
- Precursors: 7,793 unique

---

### LOCAL Quantile Strategy

```r
# Process
Bin 1 (11.9-16.9 min): 3,896 precursors
  → P5 = 402.3 Da, P95 = 798.5 Da

Bin 2 (16.9-21.8 min): 3,897 precursors
  → P5 = 415.7 Da, P95 = 812.4 Da

# Output
RT Bins: 2
m/z ranges: [402-798], [416-812]
Jump at boundary: 13.4 Da (min), 13.9 Da (max)
Computation time: ~0.01 sec
```

**Result**: Fast, accurate per-bin ranges, small jump at boundary

---

### GLOBAL Smoothing Strategy

```r
# Process
RT sampling: 0.5 min interval → 20 RT points
Sliding window: ±0.5 min

RT points calculation:
  RT=12.0: precursors in 11.5-12.5 → P5=398 Da, P95=792 Da
  RT=12.5: precursors in 12.0-13.0 → P5=401 Da, P95=797 Da
  ...
  RT=21.5: precursors in 21.0-22.0 → P5=425 Da, P95=825 Da

Smoothing: window=7, poly=3
  → Smooth continuous curves

Bin assignment (interpolation):
  Bin 1 center (14.4 min) → mz: 406-805 Da
  Bin 2 center (19.35 min) → mz: 418-818 Da

# Output
RT Bins: 2
m/z ranges: [406-805], [418-818] (smoothly interpolated)
No jumps (continuous function)
Computation time: ~0.05 sec
```

**Result**: Slower but smooth continuous transitions, no jumps

---

## 💡 Key Insights

`★ Insight ─────────────────────────────────────`
**Fundamental Difference:**

1. **LOCAL = Discrete Bins**
   - Each bin is an independent region
   - Calculate using bin's precursors only
   - Fast and bin-specific

2. **GLOBAL = Continuous Function**
   - RT is a continuous variable
   - Calculate using sliding windows
   - Smooth interpolation to bins

**Why Both Are Needed:**
- LOCAL is **more accurate** for bin-specific properties
- GLOBAL is **more elegant** for continuous transitions
- Different biological/instrument considerations
`─────────────────────────────────────────────────`

---

## 🔍 Technical Details

### Sliding Window Calculation (GLOBAL Smoothing)

```r
# For RT point = 15.0 min
rt_window_halfwidth <- 1.0  # ±1 min

# Get precursors in window
window_precursors <- data %>%
  filter(RT.Start >= 14.0 & RT.Start <= 16.0)

# Calculate quantiles from window
mz_min <- quantile(window_precursors$Mz, 0.05)
mz_max <- quantile(window_precursors$Mz, 0.95)
```

**Window Size Selection**:
- Too small: Noisy, insufficient precursors
- Too large: Over-smoothed, loses RT specificity
- **Adaptive**: ~5% of gradient length (good balance)

---

### Interpolation to RT Bins

```r
# Smoothed curve at high-resolution RT points
rt_points <- [15.0, 15.5, 16.0, ..., 40.0]  # 51 points
mz_min_smooth <- [398, 401, 404, ..., 570]  # 51 values

# RT Bin 1 center
rt_bin_center <- 17.5 min

# Find bounding RT points
  RT 17.0 min → mz_min = 410 Da
  RT 17.5 min → ? (interpolate)
  RT 18.0 min → mz_min = 416 Da

# Linear interpolation
fraction <- (17.5 - 17.0) / (18.0 - 17.0) = 0.5
mz_min_interpolated <- 410 + 0.5 * (416 - 410) = 413 Da
```

---

## 📚 References

### Related Documentation

- `IMPROVEMENT_PLAN.md`: Original issue description
- `GEOMETRIC_CV_GUIDE.md`: Replicate handling and CV calculation
- `R/stage3_window_optimization.R`: Implementation

### Implementation Functions

- `optimize_mz_ranges_internal()`: Strategy routing (line 355-465)
- `optimize_mz_ranges_smoothing_internal()`: GLOBAL smoothing (line 688-853)
- `interpolate_at_rt()`: Linear interpolation helper (line 855-882)

---

**Document Status**: ✅ Complete
**Last Updated**: 2025-11-15
**Version**: 1.0
