# Multi-Strategy Visualization Bug Fix
# DIA Window Optimizer v2.0

**Date**: 2025-11-19
**Bug**: Smoothing strategy caused multi-strategy visualization failure
**Status**: ✅ **FIXED** - All 24 plots now generate successfully

---

## 🐛 Problem Description

### Symptoms
- Multi-strategy plots (Plot 4, 5, 7, 8) failed when smoothing strategy was included
- Error: `Existing data has 0 rows` when generating windows
- Stage 3 output showed: `Mean m/z width: NA Da`, `Mean coverage: NA%`

### Root Cause Analysis

**Primary Issue**: `prospectr::savitzkyGolay()` removes boundary points

```r
# Input vector
RT points:  [11.9, 12.4, 12.9, ..., 20.8, 21.3, 21.8]  # 20 points
m/z values: [500,  510,  520,  ..., 900,  910,  920]   # 20 values

# After Savitzky-Golay smoothing (window=7)
Smoothed:   [     , 512,  522,  ..., 898,  908,      ]  # 14 values only!
                  ↑                           ↑
              3 points removed            3 points removed
```

**Why?** Window size 7 requires 3 neighboring points on each side:
- First 3 points: Missing left neighbors → Cannot compute
- Last 3 points: Missing right neighbors → Cannot compute
- **Only middle 14 points can be smoothed**

**Cascading Failures**:
1. **Stage 3**: RT bin 2 center (19.38 min) fell in removed boundary region
2. **Interpolation returned NA** for mz_min and mz_max
3. **Window generation failed** with empty windows
4. **Multi-strategy plots crashed** due to missing data

---

## ✅ Solution: dynamicDIA.py Approach

### Scientific Rationale

**Original Research Method** (dynamicDIA.py, Line 70-71):
```python
if start < 0 or stop >= size_data:
    result = y_array[i]  # Keep original value at boundaries
```

**Why This Is Correct**:
1. **Smoothing limitations**: Boundaries lack sufficient neighboring points for reliable smoothing
2. **Preserve actual data**: Use measured values instead of extrapolation/guessing
3. **Scientific integrity**: No assumptions about unmeasured regions

### Implementation

**Before** (Incorrect - Extrapolation):
```r
# Linear extrapolation to fill missing boundaries
slope <- (smoothed[2] - smoothed[1])
for (i in 3:1) {
  result[i] <- result[i + 1] - slope  # Guessing!
}
```

**After** (Correct - Preserve Original):
```r
# Keep original values at boundaries (dynamicDIA method)
half_window <- (window_size - 1) / 2  # = 3 for window_size=7

result[1:half_window] <- y_array[1:half_window]  # Original first 3
result[(original_length - half_window + 1):original_length] <-
  y_array[(original_length - half_window + 1):original_length]  # Original last 3

# Fill middle with smoothed values
result[(half_window + 1):(original_length - half_window)] <- smoothed
```

**Result**:
```r
# Input:  20 values
# Output: 20 values (3 original + 14 smoothed + 3 original)
result = [500, 510, 520, smooth(530), ..., smooth(890), 900, 910, 920]
         ↑    ↑    ↑                                     ↑    ↑    ↑
      original  original  original                   original orig orig
```

---

## 🔧 Code Changes

### 1. R/smoothing_utils.R

**Function**: `smooth_savgol()`

**Change**: Boundary handling strategy

```r
# Previous: Extrapolation (incorrect)
# New: Preserve original values (correct)

if (length(smoothed) < original_length) {
  half_window <- (window_size - 1) / 2
  result <- numeric(original_length)

  # Keep original values at boundaries (dynamicDIA method)
  # Scientifically correct: boundaries lack sufficient neighboring points
  result[1:half_window] <- y_array[1:half_window]
  result[(original_length - half_window + 1):original_length] <-
    y_array[(original_length - half_window + 1):original_length]

  # Fill middle section with smoothed values
  result[(half_window + 1):(original_length - half_window)] <- smoothed

  return(result)
}
```

### 2. R/stage3_window_optimization.R

**Two fixes for GLOBAL smoothing strategy**:

#### Fix A: `optimize_mz_ranges_smoothing_internal()` (Line 841)

**Problem**: Used `filter(rt_group == i)` but smoothing doesn't create rt_group
**Solution**: Filter by RT range instead

```r
# Before (failed for GLOBAL smoothing)
bin_data <- precursor_data %>% filter(rt_group == i)

# After (works for GLOBAL smoothing)
bin_data <- precursor_data %>%
  filter(RT.Start >= rt_bin_start & RT.Start <= rt_bin_end)
```

#### Fix B: `generate_windows_internal()` (Line 506)

**Problem**: Assumed rt_group column always exists
**Solution**: Conditional check for column existence

```r
# Adaptive filtering: GLOBAL vs LOCAL strategies
if ("rt_group" %in% colnames(precursor_data)) {
  # LOCAL strategies (quantile, coverage, outlier)
  bin_data <- precursor_data %>% filter(rt_group == i)
} else {
  # GLOBAL strategy (smoothing)
  bin_data <- precursor_data %>%
    filter(RT.Start >= rt_start & RT.Start <= rt_end)
}
```

---

## ✅ Test Results

### Smoothing Strategy Validation

```r
# 30min gradient, Astral instrument, DPPP 7.0
Smoothing strategy:
  - RT bins: 2 (5-min each)
  - Windows: 185 generated
  - Coverage: 88.9% (19,589 / 22,047 precursors)
  - Mean m/z width: 438.7 Da ✓ (previously NA)
  - Mean coverage: 89.1% ✓ (previously NA)
```

### Multi-Strategy Comparison

```
Strategy Comparison (30min gradient):
┌───────────┬─────────┬──────────┬────────────┐
│ Strategy  │ Windows │ Coverage │ m/z Width  │
├───────────┼─────────┼──────────┼────────────┤
│ Quantile  │ 184     │ 90.0%    │ 425.3 Da   │
│ Coverage  │ 186     │ 95.2%    │ 489.1 Da   │
│ Outlier   │ 185     │ 88.5%    │ 398.7 Da   │
│ Smoothing │ 185     │ 88.9%    │ 438.7 Da ✓ │
└───────────┴─────────┴──────────┴────────────┘
```

### Visualization Success

**All 24 plots generated successfully**:
- ✅ Plot 1A, 1B: DPPP comparison
- ✅ Plot 2, 2B: RT distribution
- ✅ Plot 3: m/z density overlay
- ✅ **Plot 4**: m/z excluded regions (4 strategies) ← **Previously failed**
- ✅ **Plot 5**: Coverage map 2×2 grid ← **Previously failed**
- ✅ Plot 6: Satisfaction curve
- ✅ **Plot 7, 7B**: Window width analysis (4 strategies) ← **Previously failed**
- ✅ **Plot 8A, 8B, 8C**: Strategy width comparison ← **Previously failed**

---

## 📊 Impact Assessment

### Before Fix
- ❌ Smoothing strategy unusable in multi-strategy mode
- ❌ Plot 4, 5, 7, 8 crashed with smoothing
- ❌ Users limited to 3 strategies (quantile, coverage, outlier)

### After Fix
- ✅ All 4 strategies work in multi-strategy mode
- ✅ All 24 plots generate successfully
- ✅ Complete strategy comparison available
- ✅ Follows original dynamicDIA methodology

---

## 🔬 Scientific Validation

### Comparison with dynamicDIA.py

**Original Implementation** (Line 64-79):
```python
for i in range(size_data):
    start, stop = i - halfsize_kernel, i + halfsize_kernel + 1

    if start < 0 or stop >= size_data:
        result = y_array[i]  # Boundary preservation
    else:
        # Convolution for middle points
        for j in range(start, stop):
            result = result + kernel[k] * y_array[j]
```

**Our Implementation**:
```r
# Matches dynamicDIA.py behavior:
# - Input length = Output length
# - Boundaries use original values
# - Middle section smoothed
```

✅ **Methodology alignment confirmed**

---

## 📝 Files Modified

### Core Bug Fix
1. **R/smoothing_utils.R** (26 lines changed)
   - Replaced extrapolation with boundary preservation
   - Added dynamicDIA.py reference in comments

2. **R/stage3_window_optimization.R** (15 lines changed)
   - Fixed GLOBAL smoothing RT filtering
   - Added rt_group existence check

### Test Files Added
3. **tests/manual/test_smoothing_bug.R** (142 lines)
   - Reproduces bug with quantile vs smoothing comparison
   - Validates fix with 2 comprehensive tests

4. **tests/manual/test_multi_strategy_final.R** (101 lines)
   - End-to-end multi-strategy visualization test
   - Generates all 4 strategies + 24 plots

---

## 🎯 Lessons Learned

### 1. Library Behavior Matters
- **Always check** if library functions modify data length
- `prospectr::savitzkyGolay()` truncates by design
- Read documentation carefully

### 2. Follow Original Research
- dynamicDIA.py had solved this problem correctly
- Original research code is often scientifically validated
- **Don't reinvent** - follow proven methods

### 3. No Extrapolation Without Evidence
- **Extrapolation = Guessing** beyond measured data
- Use actual measurements whenever possible
- Acknowledge limitations (boundaries are unreliable)

### 4. Test Edge Cases
- Boundary conditions often reveal bugs
- Test with minimal RT bins (n=2) to stress boundaries
- Multi-strategy mode exposes integration issues

---

## ✅ Verification Checklist

- [x] Smoothing strategy generates valid mz_ranges
- [x] No NA values in coverage or m/z width
- [x] Window generation succeeds for all strategies
- [x] Multi-strategy plots (4, 5, 7, 8) render correctly
- [x] All 24 plots generate without errors
- [x] Coverage rates reasonable (>85%)
- [x] Follows dynamicDIA.py methodology
- [x] Tests added for regression prevention

---

**Status**: ✅ **RESOLVED**
**Validation**: All tests passing (100%)
**Production Ready**: Yes

**Commit**: `560230c` - "fix: Resolve smoothing strategy multi-strategy visualization bug"
