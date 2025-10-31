# Stage 4 Plot Review - Issues and Fixes

**Date**: 2025-10-30
**Status**: In Progress - Plot Validation

---

## Test Data Summary

- **Input**: `data/30min_report.parquet`
- **Precursors**: 22,047 (after quality filtering)
- **RT Range**: 11.9 - 21.8 min (9.9 min span)
- **m/z Range**: 401.2 - 1002.5 Da (601.3 Da span)
- **Windows Generated**: 34 (2 RT bins × 17 windows)
- **Coverage**: 90.0%
- **Target DPPP**: 7.5
- **Actual Cycle Time**: 0.900 sec

---

## Plot 1: DPPP Density Heatmap

### Purpose
Show DPPP distribution across RT × m/z space to visualize where high/low DPPP values occur

### Expected Output
2D heatmap with:
- X-axis: Retention Time (min)
- Y-axis: m/z (Da)
- Color: DPPP value
- Overlay: Target DPPP line (7.5)

### Current Status
✅ Generates without errors (99 KB)

### Data Check
- Sample DPPP values: 9.20 - 13.8 (mostly above target)
- Binning: 40 × 40 tiles
- Formula: DPPP = (FWHM × 60 × 1.7) / cycle_time

### Issues
❓ Need to verify visual output matches expectations

### Action Required
- [ ] Visual inspection of plot
- [ ] Verify target line shows correctly
- [ ] Check color scale is meaningful

---

## Plot 2: RT Window Size Distribution

### Purpose
Show how many windows are allocated to each RT segment

### Expected Output
Bar chart with:
- X-axis: RT midpoint (min)
- Y-axis: Number of windows
- Labels: Window count on each bar

### Current Status
✅ Generates without errors (84 KB)

### Data Check
```
RT Segment 1 (11.9-16.9 min): 17 windows
RT Segment 2 (16.9-21.8 min): 17 windows
```

### Issues
✅ None - data looks correct (equal allocation)

### Action Required
- [ ] Visual inspection to confirm clarity

---

## Plot 3: RT × m/z Density Heatmap

### Purpose
Show precursor density distribution to understand data coverage

### Expected Output
2D heatmap with:
- X-axis: Retention Time (min)
- Y-axis: m/z (Da)
- Color: Precursor count per bin

### Current Status
✅ Generates without errors (96 KB)

### Data Check
- 22,047 precursors across 9.9 min RT × 601.3 Da m/z
- Expected density: ~3.7 precursors per Da per minute

### Issues
❓ Need to verify binning shows clear density patterns

### Action Required
- [ ] Visual inspection
- [ ] Verify density calculation is meaningful

---

## Plot 4: m/z Normalized Density

### Purpose
Show m/z density profiles per RT segment with window overlays

### Expected Output
Line plots with:
- Multiple panels (one per RT segment)
- X-axis: m/z (Da)
- Y-axis: Normalized density
- Overlays: Window boundaries

### Current Status
✅ Generates without errors (216 KB - largest plot)

### Data Check
- 2 RT segments
- 17 windows per segment
- Fixed window mode (equal widths)

### Issues
❓ Large file size (216 KB) - is this optimal?
❓ Need to verify normalization is correct

### Action Required
- [ ] Visual inspection
- [ ] Check if file size can be reduced
- [ ] Verify window overlays are clear

---

## Plot 5: Window Width Distribution

### Purpose
Show distribution of window widths across m/z range

### Expected Output
Scatter plot with:
- X-axis: m/z center (Da)
- Y-axis: Window width (Da)
- Points: Individual windows

### Current Status
✅ Generates without errors (144 KB)

### Data Check
- Mean width: 26.4 Da
- SD: 0.28 Da (very uniform - fixed mode)
- Range: 26.2 - 26.7 Da

### Issues
❓ With fixed mode, all widths are nearly identical
❓ Is this plot meaningful for fixed mode?

### Action Required
- [ ] Visual inspection
- [ ] Consider if plot should be different for fixed vs variable mode
- [ ] May need conditional rendering based on mode

---

## Plot 6: Precursor Coverage Map ⚠️ MAJOR ISSUE

### Purpose
Show which precursors are covered by windows (colored by coverage status)

### Expected Output
Scatter plot with:
- X-axis: Retention Time (min)
- Y-axis: m/z (Da)
- Color: Covered (green) vs Uncovered (red)
- All 22,047 precursors as points

### Current Status
⚠️ **File size: 1.5 MB** - Too large for practical use

### Issues
❌ **CRITICAL**: Plotting 22K points results in huge file
❌ Coverage calculation is expensive
❌ Plot may be unreadable due to overplotting

### Proposed Fixes

**Option 1: Binned Heatmap** (Recommended)
- Bin precursors into grid (e.g., 50×50)
- Show coverage percentage per bin
- Much smaller file size (<100 KB)
- Still shows spatial coverage patterns

**Option 2: Sampling**
- Randomly sample 1000-2000 precursors
- Faster rendering
- May miss coverage gaps

**Option 3: Hexbin Plot**
- Use `geom_hex()` for automatic binning
- Shows density + coverage
- Efficient for large datasets

### Action Required
- [x] Identified issue
- [ ] Implement Option 1 (binned heatmap)
- [ ] Test new implementation
- [ ] Verify file size <200 KB

---

## Plot 7: Window Efficiency

### Purpose
Show distribution of precursors per window to assess load balance

### Expected Output
Histogram or violin plot with:
- X-axis: Window index or m/z center
- Y-axis: Number of precursors
- Stats: Mean, CV

### Current Status
✅ Generates without errors (100 KB)

### Data Check
- Mean: 583.6 precursors/window
- CV: 0.41 (moderate variation)
- 34 windows total

### Issues
❓ Need to verify plot type is most informative

### Action Required
- [ ] Visual inspection
- [ ] Consider boxplot or violin plot instead of current format

---

## Plot 8: DPPP Achievement Heatmap ⚠️ ERROR

### Purpose
Show which windows achieve target DPPP across RT × m/z space

### Expected Output
Heatmap with:
- X-axis: RT segment
- Y-axis: Window index
- Color: DPPP achievement (% precursors meeting target)

### Current Status
⚠️ **WARNING**: NA conversion errors

### Error Details
```
Warning: There was 1 warning in `mutate()`.
ℹ In argument: `window_id = as.integer(gsub("^window_", "", window_id))`.
Caused by warning:
! 강제형변환에 의해 생성된 NA 입니다
```

### Root Cause
- Window IDs are in format: "RT1_W1", "RT1_W2", etc.
- Code tries: `gsub("^window_", "", window_id)` → Doesn't match pattern
- Then converts to integer → Fails, produces NA
- Result: 34 tiles removed from heatmap (all windows!)

### Fix Required
```r
# Current (WRONG):
window_id = as.integer(gsub("^window_", "", window_id))

# Fix Option 1: Match actual pattern
window_id_num = as.integer(gsub("^RT\\d+_W", "", window_id))

# Fix Option 2: Use factor ordering
window_id = factor(window_id, levels = unique(window_id))

# Fix Option 3: Use row number
window_id = row_number()
```

### Action Required
- [x] Identified issue
- [ ] Implement Fix Option 1 or 2
- [ ] Test corrected plot
- [ ] Verify heatmap shows all windows

---

## Additional Issues

### Min/Max Warnings
```
min(x): min에 전달되는 인자들 중 누락이 있어 Inf를 반환합니다
max(x): max에 전달되는 인자들 중 누락이 있어 -Inf를 반환합니다
```

**Likely Cause**: Distance calculations with NA values in Plot 6 or 8

**Fix**: Add `na.rm = TRUE` to min/max calls

---

## Summary

### Plots Requiring Fixes

| Plot | Issue | Priority | Estimated Effort |
|------|-------|----------|------------------|
| Plot 6 | File size (1.5MB) | HIGH | 30 min |
| Plot 8 | window_id conversion | HIGH | 15 min |
| Plot 5 | Meaningless for fixed mode | MEDIUM | 20 min |
| Plot 4 | File size (216KB) | LOW | 15 min |
| All | min/max NA warnings | LOW | 10 min |

### Plots OK (Pending Visual Review)

- Plot 1: DPPP Density Heatmap ✓
- Plot 2: RT Window Size Distribution ✓
- Plot 3: RT × m/z Density Heatmap ✓
- Plot 7: Window Efficiency ✓

---

## Next Steps

1. **Fix Plot 8** (window_id conversion) - Quick fix, blocks heatmap
2. **Fix Plot 6** (file size) - Implement binned heatmap
3. **Visual review** of all plots with user
4. **Enhance Plot 5** if fixed mode needs different visualization
5. **Add na.rm=TRUE** to min/max calls
6. **Re-test** all plots with fixes

---

**Note**: All plot image files are available in `results_stage4_test/` for visual inspection.
