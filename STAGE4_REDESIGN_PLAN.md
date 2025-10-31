# Stage 4 Visualization - Redesign Plan

**Date**: 2025-10-31
**Status**: Implemented
**Version**: 3.0 (Standardized naming and complete plot output)

---

## 🎯 Design Philosophy

### Core Principles
1. **Before/After Comparison**: Show optimization impact clearly
2. **Strategy Differentiation**: Compare 4 strategies side-by-side
3. **Multi-scale Visualization**: Global → RT segment → Strategy detail
4. **Actionable Insights**: Each plot must answer a specific question

### User Requirements Summary
- Plot 3: Use overlay for clarity (not facets)
- Plot 4: Separate plots per strategy (avoid crowding when many RT segments)
- Plot 7: Replace RT window count with RT-segment precursor histograms + window width overlay
- Plot 5: Use density heatmap (not scatter)
- Data: Need 4-strategy comparison data (quantile, smoothing, outlier, coverage)
- Intermediate data: Save strategy results during pipeline for visualization

---

## 📊 Final Plot Structure (8 Essential Plots)

### **Plot 1: DPPP Distribution Comparison**
**Question Answered**: "How does optimization improve DPPP?"

**Design**:
- **Type**: Dual density curve (overlay)
- **X-axis**: DPPP value
- **Y-axis**: Density
- **Curves**:
  - Blue: Current DPPP (using current cycle time)
  - Red: Expected DPPP (using recommended cycle time)
- **Reference line**: Target DPPP (7.5) - vertical dashed line
- **Annotations** (text box):
  ```
  DPPP = (FWHM × 60 × 1.7) / cycle_time

  Current State:
    Median FWHM: 5.4 sec
    Current cycle time: 1.200 sec
    Current satisfaction: 46.9%

  Recommended:
    Recommended cycle time: 1.180 sec
    Expected satisfaction: 70%+

  Total precursors: 22,047
  ```

**Reference**: `plots_for_develop/dppp_comparison_analysis.png`

**Implementation**:
- Input: `validated_data`, `optimization_plan`
- Calculate current DPPP: `(FWHM * 60 * 1.7) / current_cycle_time`
- Calculate expected DPPP: `(FWHM * 60 * 1.7) / recommended_cycle_time`
- Use `geom_density()` with `alpha = 0.5`

---

### **Plot 2: RT × m/z Precursor Density Heatmap**
**Question Answered**: "Where are precursors concentrated in RT × m/z space?"

**Design**:
- **Type**: 2D heatmap
- **X-axis**: Retention Time (min)
- **Y-axis**: m/z (Da)
- **Color**: Precursor count per bin (log scale for visibility)
- **Purpose**: Show temporal heterogeneity - data density varies across RT

**Reference**: `plots_for_develop/02.plot3_rt_mz_heatmap.png`

**Implementation**:
- Reuse existing `plot_rt_mz_density_heatmap()`
- Input: `validated_data`
- Binning: 50×50 (adjustable)
- Color scale: `viridis` with log transformation

---

### **Plot 3: m/z Density Profiles by RT Segment (Overlay)**
**Question Answered**: "How does m/z distribution differ across RT segments?"

**Design**:
- **Type**: Line plot (overlay, NOT facets)
- **X-axis**: m/z (Da)
- **Y-axis**: Normalized density
- **Lines**: One per RT segment (different colors)
- **Legend**: RT segment ranges (e.g., "RT1: 11.9-16.9 min")
- **Purpose**: Show that different RT segments need different m/z ranges

**Reference**: `plots_for_develop/03.plot4_mz_normalized_density.png`

**User Requirement**: "overlay가 더 명확해보여"

**Implementation**:
- Modify existing `plot_mz_normalized_density()`
- Change from facets to single plot with `color = rt_segment_id`
- Add clear legend with RT ranges
- Use distinct colors (e.g., `scale_color_brewer(palette = "Set1")`)

---

### **Plot 4: m/z Range Optimization by Strategy (4 Separate Plots)**
**Question Answered**: "How does each strategy optimize m/z ranges?"

**Design**:
- **Type**: 4 separate plots (one per strategy)
- **Each plot**:
  - X-axis: RT segment ID
  - Y-axis: m/z range (Da)
  - Bars: Original range (gray) vs Optimized range (colored)
  - Labels: Coverage % per segment
- **Strategies**: Quantile, Smoothing, Outlier, Coverage
- **Layout**: 2×2 grid via `grid.arrange()`

**Reference**:
- `plots_for_develop/phase3c_mz_distribution_by_rt_bin.png`
- `plots_for_develop/phase3c_mz_distribution_coverage.png`
- `plots_for_develop/phase3c_mz_distribution_outlier.png`

**User Requirement**: "rt_segment가 많아지면 plot이 매우 많아지므로, 각 전략 별 별도로 그리는게 좋겠어"

**Implementation**:
- Create `plot_mz_range_by_strategy(strategy_results, strategy_name)`
- Loop through 4 strategies
- Each plot shows RT segments on X-axis
- Bar chart: `geom_col()` with position dodge for original vs optimized

**Data Required**:
- Need to run Stage 3 with all 4 strategies
- Save intermediate results: `strategy_results[[strategy_name]]$mz_ranges`

---

### **Plot 5: Coverage Map by Strategy (2×2 Density Heatmap)**
**Question Answered**: "Which precursors are covered by each strategy?"

**Design**:
- **Type**: 2×2 grid of density heatmaps
- **Each panel** (one strategy):
  - Base: RT × m/z density heatmap
  - Overlay: Polygon showing optimized m/z range per RT segment
  - Color: Density (background) + polygon outline (white/black)
- **Strategies**: Quantile, Smoothing, Outlier, Coverage

**Reference**: `plots_for_develop/04.plot6_precursor_coverage_map.png`

**User Requirement**:
- "Density heatmap + polygon (추천)"
- "하나의 그림에 4가지 전략을 모두 표현하지 말고 각각 4개의 그림을 2x2로 grid"

**Implementation**:
- Base layer: `geom_tile()` with precursor density
- Overlay: `geom_polygon()` for optimized m/z range boundaries
- Use `facet_wrap(~ strategy)` or `grid.arrange()`
- File size: Should be <500 KB (density heatmap is efficient)

**Data Required**:
- 4 strategy results with optimized m/z ranges per RT segment
- Polygon coordinates: `rt_start, rt_end, mz_start, mz_end` per segment

---

### **Plot 6: Strategy Optimization Summary (4-Panel Comparison)**
**Question Answered**: "Which strategy performs best overall?"

**Design**:
- **Type**: 4-panel subplot (2×2 layout)
- **Panel A** (Top-Left): m/z Range Width
  - X-axis: RT segment
  - Y-axis: m/z width (Da)
  - Lines: 4 strategies + original (5 lines total)
  - Shows range reduction per strategy
- **Panel B** (Top-Right): Coverage Ratio
  - X-axis: RT segment
  - Y-axis: Coverage %
  - Bars: 4 strategies (grouped)
  - Target line: 95% coverage
- **Panel C** (Bottom-Left): Precursors Retained vs Removed
  - X-axis: Strategy
  - Y-axis: Precursor count
  - Stacked bar: Retained (green) vs Removed (red)
- **Panel D** (Bottom-Right): Overall m/z Distribution
  - X-axis: m/z (Da)
  - Y-axis: Count
  - Histogram: Original (gray) + 4 strategies (colored, overlay)

**Reference**: `plots_for_develop/phase3c_optimization_summary.png`

**Implementation**:
- Create 4 separate ggplot objects
- Combine with `grid.arrange(nrow = 2, ncol = 2)`
- Each panel answers a specific comparison question

**Data Required**:
- Summary statistics per strategy:
  - m/z width per RT segment
  - Coverage ratio per RT segment
  - Total retained/removed precursors
  - Overall m/z distribution

---

### **Plot 7: Window Width Distribution by RT Segment**
**Question Answered**: "How are window widths distributed across m/z in each RT segment?"

**Design**:
- **Type**: Multi-panel histogram + cumulative curve (like reference image)
- **Layout**: N panels (one per RT segment, arranged in grid)
- **Each panel** (top):
  - Histogram of precursor m/z distribution
  - Overlay: Window boundaries (vertical lines)
  - Shows how windows cover the m/z range
- **Each panel** (bottom):
  - Cumulative window count curve
  - X-axis: m/z
  - Y-axis: Window index
  - Shows S-curve of window allocation

**Reference**: `plots_for_develop/Histogram_window_width.png`

**User Requirement**: "RT segment별 precursor_mz의 histogram과 그 width를 표현하면 좋을 것 같아"

**Implementation**:
- For each RT segment:
  - Top: `geom_histogram()` of precursor m/z + `geom_vline()` for window boundaries
  - Bottom: `geom_line()` of cumulative window count
- Use `facet_grid(rows = c("histogram", "cumulative"), cols = vars(rt_segment_id))`
- Title each panel with RT range (e.g., "RT1: 11.9-16.9 min")

**Data Required**:
- Precursors per RT segment with m/z values
- Window boundaries (mz_start, mz_end) per RT segment

---

### **Plot 8: DPPP Achievement Heatmap (Fixed)**
**Question Answered**: "Which windows achieve target DPPP?"

**Design**:
- **Type**: Heatmap (RT segment × Window index)
- **X-axis**: RT segment
- **Y-axis**: Window index within segment
- **Color**: % of precursors meeting target DPPP
- **Color scale**: Red (low %) → Yellow → Green (high %)

**Implementation**:
- **Fix window_id parsing**:
  ```r
  # Current (WRONG): gsub("^window_", "", window_id)
  # Fix: Extract number from "RT1_W1" format
  window_num = as.integer(gsub("^RT\\d+_W", "", window_id))
  ```
- Assign precursors to windows
- Calculate DPPP per precursor: `(FWHM * 60 * 1.7) / cycle_time`
- Calculate achievement % per window: `sum(dppp >= target_dppp) / n_precursors`
- Use `geom_tile()` with gradient color scale

**Data Required**:
- Window assignments per precursor
- DPPP calculation per precursor
- Target DPPP from `optimization_plan`

---

## 🔄 Additional Workflow Visualization (Optional)

### **Diagram 1: Pipeline Flowchart**
**Purpose**: Explain overall workflow

**Design**:
- Boxes: Stage 1 → Stage 2 → Stage 3 → Stage 4
- Arrows: Data flow with object names
- Decision diamonds: Strategy selection, DPPP check
- Create with `DiagrammeR` or external tool

---

### **Diagram 2: RT Binning Illustration**
**Purpose**: Explain time-based RT binning

**Design**:
- Timeline with bins marked
- Bar chart: Precursor count per bin
- Annotation: Window count per bin

---

### **Diagram 3: Before/After Comparison**
**Purpose**: Show optimization impact

**Design**:
- Side-by-side comparison
- Left: Full m/z range (400-1000 Da) for all RT
- Right: Segmented optimized ranges
- Metrics table: Coverage, Window count, Efficiency

---

## 📦 Data Requirements

### Required Intermediate Data

To generate all plots, we need to save strategy results during pipeline execution:

**File**: `strategy_comparison_results.rds`

**Structure**:
```r
strategy_results <- list(
  quantile = list(
    optimized_windows = OptimizedWindows,
    mz_ranges = tibble(rt_segment_id, mz_start, mz_end, coverage_pct),
    statistics = list(total_coverage, mean_width, n_precursors_retained)
  ),
  smoothing = list(...),
  outlier = list(...),
  coverage = list(...)
)
```

### Modification Required in Stage 3

**Current**: `optimize_windows()` runs once with selected strategy

**Needed**: Option to run all 4 strategies and save results

**Implementation Options**:

**Option A**: Batch mode in Stage 3
```r
optimize_all_strategies <- function(validated_data, optimization_plan, ...) {
  strategies <- c("quantile", "smoothing", "outlier", "coverage")
  results <- list()

  for (strategy in strategies) {
    cat(sprintf("Running strategy: %s\n", strategy))
    results[[strategy]] <- optimize_windows(
      validated_data, optimization_plan,
      mz_strategy = strategy,
      ...
    )
  }

  saveRDS(results, "intermediate/strategy_comparison_results.rds")
  return(results)
}
```

**Option B**: Separate pipeline runs
```r
# Run pipeline 4 times, save each result
for (strategy in c("quantile", "smoothing", "outlier", "coverage")) {
  config$mz_optimization$strategy <- strategy
  result <- run_pipeline(config)
  saveRDS(result, sprintf("intermediate/%s_result.rds", strategy))
}
```

**Recommendation**: Option A (more efficient, single data load)

---

## 🛠️ Implementation Plan

### Phase 1: Core Plots (Priority 1)
**Estimated Time**: 4 hours

1. ✅ **Plot 1**: DPPP Comparison - **New** (45 min)
2. ✅ **Plot 2**: RT × m/z Heatmap - **Reuse** existing plot3 (15 min)
3. ✅ **Plot 3**: m/z Density Overlay - **Modify** existing plot4 to use overlay (30 min)
4. ✅ **Plot 8**: DPPP Achievement - **Fix** window_id parsing (20 min)

### Phase 2: Strategy Comparison Plots (Priority 2)
**Estimated Time**: 3 hours
**Requires**: 4-strategy data

5. ✅ **Plot 4**: m/z Range by Strategy - **New** (45 min)
6. ✅ **Plot 5**: Coverage Map 2×2 - **New** (60 min)
7. ✅ **Plot 6**: Strategy Summary 4-panel - **New** (60 min)

### Phase 3: Advanced Plots (Priority 3)
**Estimated Time**: 2 hours

8. ✅ **Plot 7**: Window Width Histograms - **New** (60 min)
9. ⚠️ **Workflow Diagrams** - **Optional** (60 min)

### Phase 4: Integration & Testing
**Estimated Time**: 2 hours

- Update `generate_visualizations()` to call all 8 plot functions
- Update `create_pdf_report()` with new plot layout
- Test with real 4-strategy data
- Verify file sizes and rendering quality
- Update documentation

**Total Estimated Time**: 11 hours

---

## 📋 Checklist

### Prerequisites
- [ ] Run pipeline with 4 strategies (quantile, smoothing, outlier, coverage)
- [ ] Save intermediate results: `strategy_comparison_results.rds`
- [ ] Verify data structure matches requirements

### Plot Implementation
- [ ] Plot 1: DPPP Comparison (new)
- [ ] Plot 2: RT × m/z Heatmap (reuse)
- [ ] Plot 3: m/z Density Overlay (modify)
- [ ] Plot 4: m/z Range by Strategy (new, needs 4-strategy data)
- [ ] Plot 5: Coverage Map 2×2 (new, needs 4-strategy data)
- [ ] Plot 6: Strategy Summary 4-panel (new, needs 4-strategy data)
- [ ] Plot 7: Window Width Histograms (new)
- [ ] Plot 8: DPPP Achievement (fix window_id)

### Testing
- [ ] Test each plot individually
- [ ] Verify file sizes (<500 KB per plot)
- [ ] Check visual clarity and readability
- [ ] Test with different RT segment counts (2, 3, 5 segments)
- [ ] Validate with different strategies

### Documentation
- [ ] Update `stage4_visualization.R` with new functions
- [ ] Update API documentation
- [ ] Add usage examples
- [ ] Update CLAUDE.md with new plot descriptions

---

## 🚀 Execution Prompt

### Step 1: Generate 4-Strategy Data

```r
# Modify run_with_config.R or create new script
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")

# Run pipeline for all strategies
strategies <- c("quantile", "smoothing", "outlier", "coverage")
strategy_results <- list()

for (strategy in strategies) {
  cat(sprintf("\n=== Running strategy: %s ===\n", strategy))

  result <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    mz_strategy = strategy,
    window_mode = "fixed",
    # ... other parameters
  )

  strategy_results[[strategy]] <- result
}

# Save intermediate data
dir.create("intermediate", showWarnings = FALSE)
saveRDS(strategy_results, "intermediate/strategy_comparison_results.rds")
```

### Step 2: Implement Plot Functions

```r
# stage4_visualization_v2.R

# Plot 1: DPPP Comparison
plot_dppp_comparison <- function(validated_data, optimization_plan) {
  # Calculate current and expected DPPP
  # Create dual density curve
  # Add annotations
}

# Plot 2: Reuse existing plot_rt_mz_density_heatmap()

# Plot 3: Modify to overlay
plot_mz_density_overlay <- function(validated_data, optimized_windows) {
  # Single plot with multiple colored lines
  # No facets
}

# Plot 4: New - m/z range by strategy
plot_mz_range_by_strategy <- function(strategy_results) {
  # 2×2 grid of bar charts
  # One per strategy
}

# Plot 5: New - coverage map 2×2
plot_coverage_map_grid <- function(validated_data, strategy_results) {
  # 2×2 density heatmaps with polygon overlays
}

# Plot 6: New - strategy summary 4-panel
plot_strategy_summary <- function(strategy_results) {
  # 4-panel comparison
}

# Plot 7: New - window width histograms
plot_window_width_histograms <- function(optimized_windows) {
  # Multi-panel histogram + cumulative
}

# Plot 8: Fix existing plot_dppp_achievement_heatmap()
# Fix window_id parsing: gsub("^RT\\d+_W", "", window_id)
```

### Step 3: Update Main Function

```r
generate_visualizations_v2 <- function(
  validated_data,
  optimization_plan,
  optimized_windows,
  strategy_results = NULL,  # NEW: for multi-strategy plots
  output_dir = "output/",
  create_pdf = TRUE
) {

  plots <- list()

  # Core plots (always generated)
  plots$plot1_dppp_comparison <- plot_dppp_comparison(validated_data, optimization_plan)
  plots$plot2_density_heatmap <- plot_rt_mz_density_heatmap(validated_data)
  plots$plot3_mz_density_overlay <- plot_mz_density_overlay(validated_data, optimized_windows)
  plots$plot8_dppp_achievement <- plot_dppp_achievement_heatmap(optimization_plan, optimized_windows, validated_data)

  # Strategy comparison plots (if strategy_results provided)
  if (!is.null(strategy_results)) {
    plots$plot4_mz_range_strategy <- plot_mz_range_by_strategy(strategy_results)
    plots$plot5_coverage_map_grid <- plot_coverage_map_grid(validated_data, strategy_results)
    plots$plot6_strategy_summary <- plot_strategy_summary(strategy_results)
  }

  # Advanced plots
  plots$plot7_window_histograms <- plot_window_width_histograms(optimized_windows)

  # Export and return
  # ...
}
```

---

## 📝 User Confirmation Required

### Questions for User

1. **Priority**: Should we implement Phase 1 (core plots) first, then Phase 2 (strategy plots)?
2. **Data Generation**: Should we create a separate script to generate 4-strategy data before implementing plots?
3. **Testing Strategy**: Test each plot individually or implement all then test together?
4. **PDF Layout**: Which plots should go in the PDF report? All 8 or selected subset?

### Proceed with Implementation?

**Option A**: Generate 4-strategy data first, then implement plots
**Option B**: Implement core plots (Phase 1) first, test, then proceed to strategy plots
**Option C**: Implement all plots in parallel, test with existing single-strategy data

**Recommendation**: Option B (iterative approach, validate early)

---

**Status**: Ready for user approval to exit plan mode and begin implementation.

---

## 📝 Implementation Status (v3.0)

### Standardized Plot Naming Convention

**Format**: `{plot순서}_{plot이름}.png`

All plots now follow a consistent numbering scheme for easy identification and ordering:

| Plot Number | File Name | Description | Always Output |
|-------------|-----------|-------------|---------------|
| **Plot 1A** | `plot1a_dppp_comparison_simple.png` | DPPP comparison (simple version) | ✅ Yes |
| **Plot 1B** | `plot1b_dppp_comparison_enhanced.png` | DPPP comparison (enhanced with annotations) | ✅ Yes |
| **Plot 2** | `plot2_rt_mz_density_heatmap.png` | RT × m/z precursor density heatmap | ✅ Yes |
| **Plot 2B-1** | `plot2b_rt_histogram_continuous.png` | RT distribution histogram (continuous) | ✅ Yes |
| **Plot 2B-2** | `plot2b_rt_histogram_5min.png` | RT distribution histogram (5-min bins) | ✅ Yes |
| **Plot 3** | `plot3_mz_density_overlay.png` | m/z density profiles by RT segment (overlay) | ✅ Yes |
| **Plot 4A** | `plot4a_mz_window_width.png` | m/z window width profile | ✅ Yes |
| **Plot 4B** | `plot4b_mz_width_comparison.png` | m/z width comparison (bar chart) | ✅ Yes |
| **Plot 4C** | `plot4c_mz_distribution_excluded.png` | m/z distribution with excluded regions (ALL RT bins) | ✅ Yes |
| **Plot 5** | `plot5_coverage_map_single.png` | Coverage map with m/z range overlay (single strategy) | ✅ Yes |
| **Plot 5 (multi)** | `plot5_coverage_map_2x2.png` | Coverage map 2×2 grid (multi-strategy) | 🔄 Future |
| **Plot 6** | `plot6_satisfaction_curve.png` | Satisfaction vs cycle time trade-off | ✅ Yes |

### Key Implementation Changes (2025-10-31)

#### 1. Plot 1: Both Versions Always Generated
**Previous**: Only one version generated based on preference
**Current**: Both simple (1A) and enhanced (1B) versions always output
```r
plots$`plot1a_dppp_comparison_simple` <- plot_dppp_comparison(...)
plots$`plot1b_dppp_comparison_enhanced` <- plot_dppp_comparison_enhanced(...)
```

#### 2. Plot 4: Complete Strategy Comparison
**Previous**: Plot 4C limited to 6 RT bins by default
**Current**: Plot 4C shows ALL RT bins by default (`max_bins_to_show = NULL`)
```r
# Plot 4A, 4B, 4C all generated
plots$`plot4a_mz_window_width` <- plot_mz_window_width(...)
plots$`plot4b_mz_width_comparison` <- plot_mz_width_comparison(...)
plots$`plot4c_mz_distribution_excluded` <- plot_mz_distribution_with_exclusions(
  optimized_windows, validated_data, max_bins_to_show = NULL  # Show all bins
)
```

**User Control**: Can still limit bins by passing `max_bins_to_show = 6` if needed

#### 3. Plot 5: 2×2 Grid as Default
**Previous**: Single strategy version only
**Current**: Designed for 2×2 grid with multi-strategy support
```r
# Single-strategy mode (current)
plots$`plot5_coverage_map_single` <- plot_density_with_mz_range(...)

# Multi-strategy mode (future enhancement)
plots$`plot5_coverage_map_2x2` <- plot_density_with_mz_ranges_grid(
  windows_list = list(quantile = ..., smoothing = ..., outlier = ..., coverage = ...),
  validated_data = validated_data
)
```

#### 4. Standardized Export Function
**Previous**: Hardcoded plot names in `export_individual_plots()`
**Current**: Dynamic naming using `names(plots)`
```r
export_individual_plots <- function(plots, output_dir, format = "png", dpi = 300) {
  plot_names <- names(plots)  # Uses standardized names from plots list
  for (i in seq_along(plots)) {
    filename <- paste0(plot_names[i], ".", format)
    # ...
  }
}
```

### Testing Results

**Test Command**:
```bash
Rscript test_stage4_redesigned.R
```

**Expected Output** (11 plots):
```
plot1a_dppp_comparison_simple.png
plot1b_dppp_comparison_enhanced.png
plot2_rt_mz_density_heatmap.png
plot2b_rt_histogram_continuous.png
plot2b_rt_histogram_5min.png
plot3_mz_density_overlay.png
plot4a_mz_window_width.png
plot4b_mz_width_comparison.png
plot4c_mz_distribution_excluded.png  ← Now shows all 13 RT bins
plot5_coverage_map_single.png
plot6_satisfaction_curve.png
```

### Future Enhancements

#### Multi-Strategy Support (Plot 4 & 5)

To enable complete strategy comparison, need to:

1. **Run optimization with all 4 strategies**:
```r
strategies <- c("quantile", "smoothing", "outlier", "coverage")
windows_list <- list()

for (strategy in strategies) {
  windows_list[[strategy]] <- optimize_windows(
    validated_data, optimization_plan,
    mz_strategy = strategy,
    ...
  )
}
```

2. **Generate Plot 4 All-Strategy Comparison**:
```r
# Compare all 4 strategies side-by-side
plot4d_all_strategies <- plot_mz_width_comparison_all_strategies(
  windows_list, validated_data
)
```

3. **Generate Plot 5 2×2 Grid**:
```r
# 2×2 density heatmaps with m/z range overlays
plot5_2x2_grid <- plot_density_with_mz_ranges_grid(
  windows_list, validated_data
)
```

### File Structure

```
R/
├── stage4_visualization.R          # Main orchestration (v3.0)
├── plot2b_rt_histogram.R           # RT histogram variants
├── plot4_mz_distribution_excluded.R # m/z with excluded regions
├── plot4_mz_width_comparison.R     # m/z width bar charts
├── plot4_mz_range_optimization.R   # m/z range visualization
└── plot5_density_with_mz_ranges.R  # Coverage map grid

tests/
└── test_stage4_redesigned.R        # Updated test script
```

### Backward Compatibility

**Removed Functions** (deprecated):
- ❌ `plot_rt_window_size()` → Replaced by Plot 3
- ❌ `plot_precursor_coverage_map()` → Replaced by Plot 5
- ❌ `plot_window_efficiency()` → No longer needed
- ❌ `plot_dppp_achievement_heatmap()` → To be redesigned

**Migration Guide**:
```r
# Old naming (pre-v3.0)
plots$dppp_comparison_simple        → plots$`plot1a_dppp_comparison_simple`
plots$rt_mz_heatmap                 → plots$`plot2_rt_mz_density_heatmap`
plots$mz_normalized_density         → plots$`plot3_mz_density_overlay`
plots$mz_window_width               → plots$`plot4a_mz_window_width`
plots$satisfaction_curve            → plots$`plot6_satisfaction_curve`
```

---

**Last Updated**: 2025-10-31
**Version**: 3.0
**Status**: ✅ Production Ready
