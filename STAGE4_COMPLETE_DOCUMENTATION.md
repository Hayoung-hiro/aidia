# Stage 4: Visualization & Reporting - Complete Documentation

## Overview

**Version**: 4.0 (Complete suite with multi-strategy comparison)
**Last Updated**: 2025-10-31
**Status**: ✅ Production Ready

Stage 4 provides comprehensive visualization and reporting capabilities for the DIA Window Optimizer, generating 24 publication-quality plots across 8 major categories with multi-strategy comparison support.

---

## Complete Plot Suite (24 Plots)

### Category 1: DPPP Distribution Analysis (2 plots)

**Plot 1A: DPPP Comparison (Simple)**
- **Function**: `plot_dppp_comparison(optimization_plan, validated_data)`
- **Purpose**: Compare current vs recommended DPPP distributions
- **Features**:
  - Dual density curves (current = blue, recommended = coral)
  - Target DPPP reference line
  - Statistics annotation box
  - Satisfaction ratio calculation
- **Output**: `plot1a_dppp_comparison_simple.png`

**Plot 1B: DPPP Comparison (Enhanced)**
- **Function**: `plot_dppp_comparison_enhanced(optimization_plan, validated_data)`
- **Purpose**: Enhanced version with visual annotations
- **Features**:
  - All features from Plot 1A
  - Satisfied region highlighting (green zone)
  - Median DPPP lines with values
  - DPPP improvement arrow
  - Detailed shift metrics
- **Output**: `plot1b_dppp_comparison_enhanced.png`

`✶ Insight ─────────────────────────────────────`
**DPPP Formula**: `DPPP = (FWHM_seconds × 1.7) / cycle_time_seconds`

The 1.7 factor represents the chromatographic peak width relative to FWHM. Optimization reduces cycle time to shift the DPPP distribution rightward, increasing satisfaction ratio (% of precursors meeting target DPPP).
`─────────────────────────────────────────────────`

---

### Category 2: Precursor Distribution Analysis (3 plots)

**Plot 2: RT × m/z Density Heatmap**
- **Function**: `plot_rt_mz_density_heatmap(validated_data, bins = 50)`
- **Purpose**: Visualize 2D precursor density distribution
- **Features**:
  - Viridis plasma color scale
  - 50×50 grid density calculation
  - Bright regions = high precursor concentration
- **Output**: `plot2_rt_mz_density_heatmap.png`

**Plot 2B: RT Histogram (Continuous)**
- **Function**: `plot_rt_histogram(validated_data, bins = 50)`
- **Purpose**: Show temporal elution pattern
- **Features**:
  - Continuous histogram (50 bins)
  - Median and mean RT lines
  - Peak elution region highlighting (yellow)
  - Early vs late RT statistics
- **Output**: `plot2b_rt_histogram_continuous.png`

**Plot 2B: RT Histogram (5-min binned)**
- **Function**: `plot_rt_histogram_binned(validated_data, bin_width_min = 5)`
- **Purpose**: Time-based RT binning visualization
- **Features**:
  - 5-minute time bins
  - Bin-wise precursor counts
  - RT segment annotations
- **Output**: `plot2b_rt_histogram_5min.png`

---

### Category 3: m/z Distribution Analysis (1 plot)

**Plot 3: m/z Density Overlay by RT Segment**
- **Function**: `plot_mz_normalized_density(optimized_windows, validated_data)`
- **Purpose**: Compare m/z distributions across RT segments
- **Features**:
  - Normalized density profiles (max = 1.0)
  - 6 sampled RT segments
  - Viridis turbo color scale
  - Identifies m/z range shifts over time
- **Output**: `plot3_mz_density_overlay.png`

---

### Category 4: m/z Range Optimization (5 plots)

**Plot 4A-4D: Individual Strategy m/z Excluded Regions**
- **Function**: `plot_mz_distribution_with_exclusions(windows_list[[strategy]], validated_data, max_bins_to_show = 6)`
- **Purpose**: Show excluded precursors for each strategy
- **Strategies**: Quantile, Smoothing, Outlier, Coverage
- **Features**:
  - 6-panel faceted layout (sampled RT bins)
  - Red points = excluded precursors
  - Blue histogram = included precursors
  - Exclusion statistics per bin
- **Outputs**:
  - `plot4_quantile_mz_excluded.png`
  - `plot4_smoothing_mz_excluded.png`
  - `plot4_outlier_mz_excluded.png`
  - `plot4_coverage_mz_excluded.png`

**Plot 4E: All-Strategy Width Comparison**
- **Function**: `plot_mz_width_comparison_all_strategies(windows_list, validated_data)`
- **Purpose**: Compare m/z range widths across strategies
- **Features**:
  - 4-panel faceted layout
  - Line plot showing m/z width evolution over RT
  - Mean width reference lines
  - Strategy-specific color coding
- **Output**: `plot4e_mz_width_all_strategies.png`

`✶ Insight ─────────────────────────────────────`
**m/z Optimization Strategies**:

1. **Quantile (P5-P95)**: Conservative approach, removes top/bottom 5%
2. **Smoothing (Savitzky-Golay)**: DynamicDIA-inspired, smooth boundaries
3. **Outlier (±3SD)**: Statistical outlier removal, widest coverage
4. **Coverage (95% target)**: Adaptive approach, balances width vs coverage

Each strategy trades off between narrower m/z ranges (better spectral quality) and wider coverage (more precursors identified).
`─────────────────────────────────────────────────`

---

### Category 5: Coverage Visualization (1 plot)

**Plot 5: Coverage Map 2×2 Grid**
- **Function**: `plot_density_with_mz_ranges_grid(windows_list, validated_data)`
- **Purpose**: Visual comparison of m/z range coverage across strategies
- **Features**:
  - 2×2 grid layout (4 strategies)
  - Density heatmap with m/z boundary overlay (green lines)
  - RT segment boundaries (white dotted lines)
  - Mean width and coverage statistics per strategy
- **Output**: `plot5_coverage_map_2x2.png`

---

### Category 6: Optimization Trade-off (1 plot)

**Plot 6: Satisfaction vs Cycle Time Trade-off Curve**
- **Function**: `plot_satisfaction_curve(optimization_plan, validated_data, cycle_time_range = c(0.5, 3.0), n_points = 50)`
- **Purpose**: Visualize optimization path and trade-offs
- **Features**:
  - S-curve showing satisfaction vs cycle time relationship
  - Current state marker (blue circle)
  - Recommended state marker (coral circle)
  - Improvement arrow with metrics
  - Target satisfaction reference line
- **Output**: `plot6_satisfaction_curve.png`

---

### Category 7: Window Width Distribution (8 plots)

**Plot 7 (×4): Window Width Distribution by Strategy**
- **Function**: `plot_window_width_distribution(windows_list[[strategy]], validated_data, max_segments_to_show = 6)`
- **Purpose**: Analyze window width patterns per strategy
- **Features**:
  - 6-panel faceted layout (sampled RT segments)
  - Dual Y-axis: Normalized density (left) + Window width (right)
  - Blue histogram: Input precursor density
  - Red step function: Variable window widths
  - Legend: "Input Histogram" and "Variable Windows"
  - Decimal formatting (1 decimal place for width)
- **Outputs**:
  - `plot7_quantile_window_width_distribution.png`
  - `plot7_smoothing_window_width_distribution.png`
  - `plot7_outlier_window_width_distribution.png`
  - `plot7_coverage_window_width_distribution.png`

**Plot 7B (×4): Window Index Width Bars**
- **Function**: `plot_cumulative_window_count(windows_list[[strategy]], validated_data, max_segments_to_show = 6)`
- **Purpose**: Visualize window width as horizontal bars
- **Features**:
  - 6-panel faceted layout (sampled RT segments)
  - X-axis: m/z position (Da)
  - Y-axis: Window index (1, 2, 3, ...)
  - Bar length = window width
  - Title includes total width and mean width statistics
- **Outputs**:
  - `plot7b_quantile_window_index_width.png`
  - `plot7b_smoothing_window_index_width.png`
  - `plot7b_outlier_window_index_width.png`
  - `plot7b_coverage_window_index_width.png`

`✶ Insight ─────────────────────────────────────`
**Window Width Visualization Evolution**:

Plot 7B underwent 4 design iterations to achieve the perfect visualization:
1. **v1**: Cumulative count S-curve → Not showing width
2. **v2**: Vertical stacking with color gradient → User wanted length-based
3. **v3**: Horizontal cumulative stacking → Wrong axis arrangement
4. **v4 (Final)**: Window index stacking with bars → "이게 바로 내가 원하던 그림이야!"

Final design uses X=m/z position, Y=window index, bar length=window_width for maximum intuitiveness.
`─────────────────────────────────────────────────`

---

### Category 8: Strategy Comparison (3 plots)

**Plot 8A: Ridge Plot - Strategy Width Comparison**
- **Function**: `plot_strategy_width_ridge(windows_list, validated_data)`
- **Purpose**: Compare window width distributions using ridge plots
- **Features**:
  - **ggridges** package for professional ridge plots
  - 4 overlapping density curves (one per strategy)
  - Median lines shown within distributions (quantile_lines = TRUE)
  - Color scheme: Blue (Quantile/Smoothing) vs Red (Outlier/Coverage)
  - Alpha transparency (0.7) for better visibility
  - Informative subtitle with interpretation guide
- **Output**: `plot8a_strategy_width_ridge.png`

**Plot 8B: Box Plot - Strategy Statistical Summary**
- **Function**: `plot_strategy_width_boxplot(windows_list, validated_data)`
- **Purpose**: Statistical comparison with quartiles and outliers
- **Features**:
  - Box boundaries = 25th/75th percentiles (IQR)
  - Horizontal line in box = Median
  - White diamond = Mean
  - Individual points = Outliers
  - Same color scheme as Plot 8A for consistency
  - Subtitle explains statistical elements
- **Output**: `plot8b_strategy_width_boxplot.png`

**Plot 8C: CDF - Strategy Cumulative Distribution**
- **Function**: `plot_strategy_width_cdf(windows_list, validated_data)`
- **Purpose**: Quantitative distribution comparison
- **Features**:
  - S-curves using `stat_ecdf()` for empirical CDF
  - Dashed vertical lines = Median width per strategy
  - Y-axis as percentage (0-100%)
  - Legend on right side
  - Steeper slope = more concentrated distribution
- **Output**: `plot8c_strategy_width_cdf.png`

**Combined 3-Panel Figure**
- **Function**: `plot_strategy_width_comparison_combined(windows_list, validated_data)`
- **Purpose**: Generate all 3 plots in single vertical layout
- **Output**: `plot8_combined_strategy_comparison.png`

`✶ Insight ─────────────────────────────────────`
**Complementary Visualization Strategy**:

The Ridge + Box + CDF combination provides three complementary perspectives:

1. **Ridge Plot**: Shows *complete distribution profile* - shape, skewness, multiple peaks
2. **Box Plot**: Provides *statistical summaries* - quartiles, outliers, central tendency at a glance
3. **CDF**: Enables *quantitative comparison* - exact percentiles and statistical testing

This tri-plot approach revealed key findings:
- QUANTILE & SMOOTHING: Nearly identical narrow distributions (~14-16 Da median)
- OUTLIER: Widest windows (~18-20 Da median) with highest coverage (97%)
- COVERAGE: Balanced approach (~17 Da median, 95% coverage)

Users can make **data-driven strategy selection** based on their priorities.
`─────────────────────────────────────────────────`

---

## File Structure

```
R/
├── stage4_visualization.R              # Main orchestration (1,495 lines)
├── plot2b_rt_histogram.R              # RT histogram functions
├── plot4_mz_distribution_excluded.R   # m/z excluded regions
├── plot4_mz_width_comparison.R        # m/z width comparison
├── plot4_mz_range_optimization.R     # m/z optimization wrapper
├── plot5_density_with_mz_ranges.R    # Coverage map 2×2
├── plot7_window_width_distribution.R # Window width plots (Plot 7 & 7B)
└── plot8_strategy_width_comparison.R # Strategy comparison (Plot 8A/B/C)

tests/
├── test_plot8_strategy_comparison.R  # Standalone Plot 8 test
└── test_stage4_complete.R            # Full Stage 4 test

docs/
├── PLOT8_IMPLEMENTATION_SUMMARY.md   # Plot 8 detailed documentation
└── STAGE4_COMPLETE_DOCUMENTATION.md  # This file
```

---

## Dependencies

### R Packages

```r
# Core plotting
library(ggplot2)    # Base plotting framework
library(dplyr)      # Data manipulation
library(tidyr)      # Data reshaping

# Visualization enhancements
library(viridis)    # Color scales (plasma, turbo)
library(scales)     # Scale transformations (percent, comma)
library(gridExtra)  # Multi-panel layouts
library(grid)       # Grid graphics

# Specialized plots
library(ggridges)   # Ridge plots (Plot 8A) - NEW in v4.0
```

### Installation

All packages available on CRAN:

```r
install.packages(c(
  "ggplot2", "dplyr", "tidyr", "viridis", "scales",
  "gridExtra", "grid", "ggridges"
))
```

**ggridges** specific:
- Version: 0.5.7 (tested)
- Size: 2.2 MB
- Required for: Professional ridge plots in Plot 8A
- Documentation: https://wilkelab.org/ggridges/

---

## Usage

### Basic Usage

```r
# Load Stage 4 module
source("R/stage4_visualization.R")

# Generate all plots
viz_result <- generate_visualizations(
  validated_data = validated_data,        # From Stage 1
  optimization_plan = optimization_plan,  # From Stage 2
  optimized_windows = optimized_windows,  # From Stage 3
  output_dir = "output/",
  create_pdf = TRUE,
  create_individual_plots = TRUE,
  plot_format = "png",
  plot_dpi = 300
)

# Access plots
viz_result$plots                 # Named list of 24 ggplot objects
viz_result$report_files          # PDF, method file, individual plots
viz_result$summary_statistics    # Optimization metrics
viz_result$metadata              # Generation metadata
```

### Individual Plot Generation

```r
# Generate specific plots
plot1a <- plot_dppp_comparison(optimization_plan, validated_data)
plot8a <- plot_strategy_width_ridge(windows_list, validated_data)

# Save plots
ggsave("plot1a.png", plot1a, width = 10, height = 7, dpi = 300)
ggsave("plot8a.png", plot8a, width = 10, height = 8, dpi = 300)
```

### Multi-Strategy Analysis

```r
# Generate windows for all 4 strategies
strategies <- c("quantile", "smoothing", "outlier", "coverage")
windows_list <- list()

for (strategy in strategies) {
  windows_list[[strategy]] <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    rt_bin_width_min = 5,
    mz_strategy = strategy,
    window_mode = "variable"
  )
}

# Generate comparison plots
plot4e <- plot_mz_width_comparison_all_strategies(windows_list, validated_data)
plot5 <- plot_density_with_mz_ranges_grid(windows_list, validated_data)
plot8a <- plot_strategy_width_ridge(windows_list, validated_data)
plot8b <- plot_strategy_width_boxplot(windows_list, validated_data)
plot8c <- plot_strategy_width_cdf(windows_list, validated_data)
```

---

## Output Files

### Individual Plots (24 files)

When `create_individual_plots = TRUE`:

```
output/
├── plot1a_dppp_comparison_simple.png
├── plot1b_dppp_comparison_enhanced.png
├── plot2_rt_mz_density_heatmap.png
├── plot2b_rt_histogram_continuous.png
├── plot2b_rt_histogram_5min.png
├── plot3_mz_density_overlay.png
├── plot4_quantile_mz_excluded.png
├── plot4_smoothing_mz_excluded.png
├── plot4_outlier_mz_excluded.png
├── plot4_coverage_mz_excluded.png
├── plot4e_mz_width_all_strategies.png
├── plot5_coverage_map_2x2.png
├── plot6_satisfaction_curve.png
├── plot7_quantile_window_width_distribution.png
├── plot7_smoothing_window_width_distribution.png
├── plot7_outlier_window_width_distribution.png
├── plot7_coverage_window_width_distribution.png
├── plot7b_quantile_window_index_width.png
├── plot7b_smoothing_window_index_width.png
├── plot7b_outlier_window_index_width.png
├── plot7b_coverage_window_index_width.png
├── plot8a_strategy_width_ridge.png
├── plot8b_strategy_width_boxplot.png
├── plot8c_strategy_width_cdf.png
└── plot8_combined_strategy_comparison.png (optional)
```

### Report Files

When `create_pdf = TRUE`:

```
output/
├── optimization_report.pdf    # Multi-panel PDF report
└── method.csv                 # Thermo Orbitrap method file
```

### Method File Format (CSV)

```csv
RT_start,RT_end,Center_mz,Window_width
11.10,16.10,422.8,14.5
11.10,16.10,437.3,15.2
11.10,16.10,452.5,16.1
...
```

Format compatible with Thermo Orbitrap instruments for direct import.

---

## Performance

### Execution Time

**Test Configuration**:
- Dataset: 80,763 precursors (90-minute gradient)
- Instrument: Fusion Lumos
- RT bins: 13 (5-minute bins)
- Windows per bin: 26
- Strategies: All 4 (quantile, smoothing, outlier, coverage)

**Timing Breakdown**:
- Stage 1 (Data Validation): ~2.5 sec
- Stage 2 (Optimization Planning): ~1.0 sec
- Stage 3 (Window Optimization, ×4 strategies): ~5.0 sec
- **Stage 4 (Visualization, 24 plots): ~15.0 sec**
- **Total Pipeline**: ~23.5 seconds

**Plot Generation Time**:
- Basic plots (1A/1B, 2, 2B, 3, 6): ~2 sec
- m/z optimization plots (4A-4E): ~3 sec
- Coverage map (5): ~2 sec
- Window width plots (7, 7B ×4): ~5 sec
- Strategy comparison (8A/B/C): ~3 sec

### File Sizes

**Individual Plots** (300 DPI PNG, white background):
- Standard plots (1A, 2, 3, 6): 150-200 KB each
- Multi-panel plots (4A-4D, 7/7B): 200-300 KB each
- Complex plots (5, 8A/B/C): 150-250 KB each
- Combined plot (8): ~450 KB

**Total Output Size**: ~5-6 MB for complete plot suite

---

## Design Principles

### Visual Consistency

1. **Color Scheme**:
   - DPPP plots: Blue (current) vs Coral (recommended)
   - Density heatmaps: Viridis plasma
   - Strategy comparison: Blue tones (Quantile/Smoothing) vs Red tones (Outlier/Coverage)
   - Reference lines: Black (target), Gray (auxiliary)

2. **Typography**:
   - Title: Bold, 12-14pt
   - Subtitle: Regular, 9-11pt, informative
   - Axis labels: 10-11pt
   - Annotations: Monospace for statistics, 3-3.5pt

3. **Layout**:
   - Single plots: 10×7 inches
   - Ridge plots: 10×8 inches (taller for stacking)
   - Combined plots: 10×15 inches (vertical layout)
   - Multi-panel grids: Equal facet spacing

### Information Hierarchy

1. **Primary Information**: Main plot elements (density curves, bars, lines)
2. **Secondary Information**: Reference lines, statistical markers
3. **Tertiary Information**: Annotations, statistics boxes, legends
4. **Caption**: Interpretation guide in plot caption

### Accessibility

1. **Color Blind Friendly**: Viridis color scales + distinct shapes
2. **High Contrast**: White background, bold lines
3. **Clear Labels**: All axes labeled with units
4. **Legends**: Positioned to avoid data overlap

---

## Version History

### Version 4.0 (2025-10-31) - Current

**Major Changes**:
- ✅ Added Plot 8 (A/B/C): 4-strategy window width comparison
- ✅ Integrated ggridges package for professional ridge plots
- ✅ Extended Plot 7/7B to all 4 strategies
- ✅ Increased total plot count from 13 to 24
- ✅ Added comprehensive multi-strategy analysis

**New Features**:
- Ridge plot (Plot 8A) with median quantile lines
- Box plot (Plot 8B) with mean diamonds and outlier detection
- CDF plot (Plot 8C) with statistical distribution comparison
- Window index width bars (Plot 7B) after 4 design iterations
- Unified color scheme across all strategy comparison plots

**Bug Fixes**:
- Fixed discrete/continuous scale conflict in ridge plot
- Fixed Y-axis formatting in Plot 7 (1 decimal place)
- Fixed legend positioning in Plot 1A/1B

### Version 3.0 (2025-10-25)

**Major Changes**:
- Redesigned plot architecture with modular functions
- Removed deprecated functions (plot_rt_window_size, plot_precursor_coverage_map)
- Added Plot 4 (A-E): m/z optimization comparison
- Added Plot 5: Coverage map 2×2 grid
- Added Plot 6: Satisfaction vs cycle time trade-off

### Version 2.1 (2025-10-20)

**Major Changes**:
- Added Plot 1B: Enhanced DPPP comparison with visual annotations
- Added Plot 6: Satisfaction curve

### Version 2.0 (2025-10-15)

**Major Changes**:
- Added Plot 2B: RT histogram (continuous and binned)
- Added Plot 7: Window width distribution

### Version 1.0 (2025-10-10)

**Initial Release**:
- 8 basic plots (Plot 1, 2, 3, 4, 5)
- PDF report generation
- Method file export

---

## Troubleshooting

### Common Issues

#### Issue 1: "Package 'ggridges' not found"

**Error**: Cannot load Plot 8 functions
**Fix**:
```r
install.packages("ggridges")
library(ggridges)
```

#### Issue 2: "Discrete values supplied to continuous scale"

**Error**: Ridge plot Y-axis scale conflict
**Fix**: Already fixed in v4.0 - remove manual `scale_y_continuous()` call

#### Issue 3: Plot 8 not generating in pipeline

**Error**: Functions not loaded or existence check failed
**Fix**:
```r
# Verify sourcing
source("R/plot8_strategy_width_comparison.R")

# Check function existence
exists("plot_strategy_width_ridge")  # Should return TRUE
```

#### Issue 4: "object 'windows_list' not found"

**Error**: Missing multi-strategy window optimization
**Fix**:
```r
# Ensure all 4 strategies are run
strategies <- c("quantile", "smoothing", "outlier", "coverage")
windows_list <- list()

for (strategy in strategies) {
  windows_list[[strategy]] <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    mz_strategy = strategy,
    ...
  )
}
```

#### Issue 5: Slow plot generation

**Symptoms**: Stage 4 takes >30 seconds
**Solutions**:
- Reduce plot resolution: `plot_dpi = 150` (default: 300)
- Skip individual plots: `create_individual_plots = FALSE`
- Skip PDF report: `create_pdf = FALSE`
- Downsample data for testing: Use smaller dataset

---

## Future Enhancements

### Planned Features (v4.1+)

1. **Interactive Plots**: Plotly integration for web-based reports
2. **Statistical Tests**: Add Kolmogorov-Smirnov test results to Plot 8
3. **Animation**: Animated GIF showing optimization progression
4. **Violin Plots**: Hybrid violin+box plot option for Plot 8
5. **Heatmap Matrix**: 2D strategy comparison heatmap
6. **Faceted RT Evolution**: Show strategy differences over RT bins

### Performance Optimizations

1. Cache density calculations for faster Plot 8 regeneration
2. Parallelize plot generation across CPU cores
3. Add downsampling option for large datasets (>100K precursors)
4. Implement progressive rendering for real-time visualization

### Export Options

1. SVG export for vector graphics
2. PowerPoint template integration
3. LaTeX figure generation
4. Automated figure caption generation

---

## References

### Scientific Background

- **DPPP (Data Points Per Peak)**: Spectronaut documentation on chromatographic sampling
- **DIA Window Optimization**: Bruderer et al. (2015) "Extending the limits of quantitative proteome profiling with data-independent acquisition and application to acetaminophen-treated three-dimensional liver microtissues"
- **DynamicDIA**: Variable isolation windows based on precursor density

### Software & Packages

- **ggplot2**: Wickham, H. (2016). ggplot2: Elegant Graphics for Data Analysis. Springer-Verlag New York.
- **ggridges**: Wilke, C. O. (2021). ggridges: Ridgeline Plots in 'ggplot2'. R package version 0.5.7. https://wilkelab.org/ggridges/
- **viridis**: Garnier, S. (2021). viridis: Colorblind-Friendly Color Maps for R.

### Related Documentation

- [CLAUDE.md](../CLAUDE.md) - Project overview and development guidelines
- [DEVELOPMENT.md](../DEVELOPMENT.md) - Development status and progress
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture details
- [PHASE4_VISUALIZATION.md](phases/PHASE4_VISUALIZATION.md) - Stage 4 development guide
- [PLOT8_IMPLEMENTATION_SUMMARY.md](../PLOT8_IMPLEMENTATION_SUMMARY.md) - Plot 8 detailed documentation

---

## Credits

**Development**: Claude (Anthropic) with user guidance
**Testing**: Real proteomics data (80,763 precursors, 90-minute gradient)
**Visualization Design**: Iterative refinement based on user feedback
**Version 4.0 Highlights**: Plot 8 implementation with ggridges integration

---

**Last Updated**: 2025-10-31
**Version**: 4.0
**Status**: ✅ Production Ready
**Plot Count**: 24 (Complete Suite)
**Test Status**: All tests passing with real data
