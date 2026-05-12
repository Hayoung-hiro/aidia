# AIDIA Reporting System Redesign Plan (Revised)

> Last updated: 2026-04-13

## Context

AIDIA's Stage 4 generates 30+ plots with significant redundancy (4 DPPP variants, 3 width distribution formats, overlapping layouts). This plan restructures reporting around a **5-section narrative** — each section answers one user question with minimum non-redundant data.

### Design Principles

- **Publication-quality output**: All plots use `theme_aidia()` (Style C — Nature/Science standard)
- **PNG-first workflow**: Individual plots generated as PNG for iterative review; PDF assembly is the final step
- **No redundancy**: Each piece of information appears exactly once in the report
- **Table over decoration**: Prefer clean `tableGrob` tables over decorative tiles/scorecard UI

---

## Visual Design System

### Theme: Style C (Nature/Science)

Selected from 3 candidates (A: Minimal, B: Classic Academic, C: Nature/Science):

```r
theme_aidia()
# - Black axis text and titles (high contrast)
# - Bold axis lines (0.4pt black), visible ticks
# - No panel grid lines (clean publication style)
# - White background
# - Muted, colorblind-safe palette
```

### Color Palette (muted, publication-ready)

```r
# Strategy colors
aidia_strategy_colors <- c(
  greedy   = "#4878A8",  # Steel blue
  kde      = "#7B68AE",  # Muted purple
  quantile = "#2D9B83",  # Sage teal
  coverage = "#C75B5B",  # Dusty red
  outlier  = "#D4923A"   # Amber
)

# Functional colors
primary  = "gray10"    # Near-black (text)
accent   = "#C75B5B"   # Dusty red (highlights)
success  = "#2D9B83"   # Sage teal (met/pass)
warning  = "#D4923A"   # Amber (caution)
before   = "#4878A8"   # Steel blue (current state)
after    = "#C75B5B"   # Dusty red (optimized state)
```

### Grid/Table Panels

All non-ggplot pages (Executive Summary, Data Summary, Instrument Metadata) use:
- `gridExtra::tableGrob` with `ttheme_minimal`
- Header: dark background (`gray20`), white bold text
- Rows: alternating `white` / `gray95`
- Verdict cells: color-coded (teal = met, red = not met)

---

## Report Structure

```
┌──────────────┬────────────────────────────────────────────┐
│  Section     │  User Question                             │
├──────────────┼────────────────────────────────────────────┤
│ 1. Input     │ "What are the characteristics of my data?" │
│ 2. Diagnosis │ "What's wrong with current acquisition?"   │
│ 3. Result    │ "What did AIDIA produce?"                  │
│ 4. Validation│ "Did optimization actually improve?"       │
│ 5. Comparison│ "Which strategy fits my use case?"         │
└──────────────┴────────────────────────────────────────────┘
```

### Front Matter (before sections)

| Page | Type | Content |
|------|------|---------|
| Cover | grid | AIDIA branding, key metrics, timestamp |
| Executive Summary | **tableGrob** | 9-row metric/value table + verdict + recommendation |
| Configuration Summary | tableGrob | Full parameter table (18 rows) |

---

## Section 1: Input Data Profile

**Subtitle**: "Precursor distribution characteristics and chromatographic quality"

| # | Visual | Type | File | Role |
|---|--------|------|------|------|
| 1 | **Precursor Distribution Heatmap** | ggplot | `R/plot_density.R` | RT × m/z density with contour overlay (inferno palette) |
| 2 | **FWHM Distribution** | ggplot | `R/plot_fwhm_distribution.R` | Peak width histogram; median + implied DPPP annotation |
| 3 | **Data Summary** | tableGrob | `R/export_plots.R` | Precursor count, m/z/RT range, FWHM stats |

### Heatmap: 2D Contour (selected)

```r
# 2D kernel density with contour overlay
stat_density_2d(fill = density, geom = "raster") +
stat_density_2d(color = "white", bins = 8)        # contour ridges
# Palette: viridis "inferno"
```

A 3D surface variant (`plot_rt_mz_density_surface()` using base R `persp()`) is also implemented for optional use but not included in the standard report due to theme inconsistency with ggplot-based plots.

### FWHM: Median + DPPP context (P15 removed)

Previous design showed P15 (15th percentile) as a "critical" marker, but P15 has no special domain meaning in the DPPP pipeline — satisfaction is calculated from the full distribution, not from a single percentile. The revised plot shows:
- **Median FWHM** with labeled marker
- **Implied DPPP** at the required cycle time (annotated)
- **Mode region** (density peak) to highlight the most common peak width

### Data Summary: Table (replaces Quality Score Panel)

The old quality score (`0.4×FWHM + 0.3×RT + 0.3×m/z` issue rates) is near 1.0 for any properly processed DIA-NN output and provides little information. Replaced with a clean summary table showing raw statistics.

### Removed (redundant)
- RT histograms (`plot2b_*`) — marginal projection of heatmap Y-axis
- Charge state × m/z (`plot19`) — not actionable for window optimization; appendix only

---

## Section 2: Acquisition Diagnosis

**Subtitle**: "Current DPPP status, cycle time trade-off, and instrument parameters"

| # | Visual | Type | File | Role |
|---|--------|------|------|------|
| 4 | **DPPP Diagnosis Table** | tableGrob | `R/plot_dppp.R` | Before/After: cycle time, DPPP, satisfaction, windows; verdict color-coded |
| 5 | **Satisfaction Curve** | ggplot | `R/plot_satisfaction.R` | S-curve with current/required points, feasibility region |
| 6 | **Instrument Metadata** | tableGrob | `R/export_plots.R` | MS1/MS2 scan times, cycle mode — all from OptimizationPlan fields |

### Satisfaction Curve Features

- Horizontal target line + vertical required cycle time guide
- Shaded feasibility region (above target, left of required CT)
- Current (steel blue) and Required (dusty red) annotated points

### Removed (redundant)
- `plot1a_dppp_comparison_simple`, `plot1b_dppp_enhanced`, `plot1b_dppp_satisfaction_combined`
- `plot15_dppp_distribution` — already summarized as satisfaction %

---

## Section 3: Optimized Window Layout

**Subtitle**: "Isolation window tiling, density alignment, and precursor load balance"

| # | Visual | Type | File | Role |
|---|--------|------|------|------|
| 7 | **Tiling Coverage Map** | ggplot | `R/plot_tiling_coverage.R` | Window rectangles colored by precursor count; gap/overlap detection |
| 8 | **Precursor Load Balance** | ggplot | `R/plot_load_balance.R` | Per-RT-segment window utilization: IQR + jitter + high-load threshold |
| 9 | **m/z Density Profiles** | ggplot | `R/plot_density.R` | Normalized m/z density per RT segment (6 representative segments) |
| 10 | **Window Width + Density Overlay** | ggplot (faceted) | `R/plot_window_width.R` | Per-RT-bin: precursor density (blue) + variable window width (red), dual y-axis |
| 11 | **Window Index Width Bars** | ggplot (faceted) | `R/plot_window_width.R` | Per-RT-bin: window index vs m/z position, shows width variation across m/z range |

---

## Section 4: Optimization Validation

**Subtitle**: "Before/after comparison, boundary safety, and forbidden zone verification"

| # | Visual | Type | File | Role |
|---|--------|------|------|------|
| 12 | **Impact Dashboard** | gridExtra (2×2) | `R/plot_impact_summary.R` | Before/after bars: cycle time, satisfaction; text panels: windows, metrics |
| 13 | **Edge Proximity** | ggplot | `R/plot_edge_proximity.R` | Precursor-to-boundary distance histogram with danger/center zones |
| 14 | **FZ Zoom** | ggplot | `R/plot_fz_zoom.R` | Forbidden zone boundary placement detail — **always included** |

### FZ Offset: Always-On (not conditional)

FZ offset is applied by default because:
- 2+ and 3+ charge states dominate most DIA datasets
- Their isotope envelopes cluster near integer m/z values
- Without FZ offset, window boundaries frequently cut through isotope envelopes, causing incomplete fragmentation
- The FZ zoom plot validates that boundaries are properly shifted away from these danger zones

Future enhancement: add a before/after isotope envelope visualization showing the cutting problem and its resolution.

---

## Section 5: Strategy Comparison *(conditional: >= 2 strategies)*

**Subtitle**: "Multi-strategy performance comparison across quality dimensions"

| # | Visual | Type | File | Role |
|---|--------|------|------|------|
| 15 | **Comparison Table** | tableGrob | `R/plot_strategy_comparison.R` | Coverage, width stats, utilization per strategy |
| 16 | **Width Ridge Plot** | ggplot (ggridges) | `R/plot_strategy_comparison.R` | Actual Da distributions per strategy |
| 17 | **Boundary Grid Heatmap** | ggplot (faceted) | `R/plot_density_overlay.R` | Side-by-side heatmap with m/z boundary overlay per strategy |
| 18 | **m/z Excluded Regions** | ggplot (faceted) | `R/plot_mz_excluded.R` | Per-strategy: density + excluded tails per RT bin (6 bins sampled) |
| 19 | **Strategy Boundary Comparison** | ggplot (faceted) | `R/plot_density_overlay.R` | 2×2+1 grid: all strategies with boundary lines on same density background |

### Ridge Plot Replaces Radar Chart

Radar normalizes to 0-1 (loses scale). Ridge shows actual Da width distributions — users directly see "this strategy produces narrower windows." The Comparison Table covers the multi-axis numerical summary.

---

## Appendix

| Section | Content | Condition |
|---------|---------|-----------|
| A | Adaptive RT binning validation | Only if `rt_binning_mode == "adaptive"` |

---

## Plot Count Summary

| Section | Previous | Current | Change |
|---|---|---|---|
| Front Matter | 3 pages | 3 pages (cover, exec table, config table) | Exec: tiles → table |
| 1. Input Profile | 5 | 3 plots + 1 table (+ 3D optional) | +3D surface |
| 2. Diagnosis | 5 | 2 plots + 1 table | -3 plots |
| 3. Window Layout | 4 | 5 plots | +2 (plot7, plot7b restored) |
| 4. Validation | 3 | 3 plots (FZ always-on) | FZ no longer conditional |
| 5. Comparison | 8 | 5 plots | -3 (radar, box, CDF removed; boundary grid, excluded, comparison restored) |
| **Total core** | **28** | **18-19 plots + 3 tables = ~20** | Focused, no redundancy |
| Appendix | ~15 | conditional only | reduced |

---

## Implementation Status

### Completed

| Item | File | Notes |
|------|------|-------|
| `theme_aidia()` → Style C | `R/theme_aidia.R` | Black axes, no grid, muted palette; 38 call sites |
| Strategy palette → muted | `R/theme_aidia.R` | `aidia_strategy_colors` updated |
| Executive Summary → table | `R/export_plots.R` | `.draw_executive_summary()` rewritten as `tableGrob` |
| Section 1 subtitle | `R/export_plots.R` | "characteristics" framing |
| 2D contour heatmap | `R/plot_density.R` | `stat_density_2d` raster + contour overlay |
| 3D surface (optional) | `R/plot_density.R` | `plot_rt_mz_density_surface()` via `persp()` |
| DPPP table verdict colors | `R/plot_dppp.R` | Green/red per-cell in Verdict column |
| Satisfaction curve | `R/plot_satisfaction.R` | Target line + feasibility region + crosshair |
| 5-section PDF structure | `R/export_plots.R` | `create_pdf_report()` rewritten |
| Coverage delta | `R/plot_impact_summary.R` | Before/after coverage in impact dashboard |

### Pending (Pass 2 — fine-tune after user review of Pass 1 PNGs)

| # | Item | File | Notes |
|---|------|------|-------|
| 1 | FWHM: remove P15, add mode + DPPP | `R/plot_fwhm_distribution.R` | |
| 2 | Data Summary → table with score breakdown | `R/export_plots.R` | Show sub-scores: FWHM/RT/m/z |
| 3 | Satisfaction curve: add knee point + fix deprecation | `R/plot_satisfaction.R` | Optimal efficiency annotation |
| 4 | Instrument metadata fine-tune | `R/export_plots.R` | |
| 5 | Tiling coverage map fine-tune | `R/plot_tiling_coverage.R` | |
| 6 | Load balance fine-tune | `R/plot_load_balance.R` | |
| 7 | m/z density profiles fine-tune | `R/plot_density.R` | |
| 8 | Impact dashboard fine-tune | `R/plot_impact_summary.R` | Title, panel balance |
| 9 | Edge proximity fine-tune | `R/plot_edge_proximity.R` | |
| 10 | Width ridge fine-tune | `R/plot_strategy_comparison.R` | |
| 11 | FZ zoom: make always-on | `R/plot_fz_zoom.R`, `R/export_plots.R` | Remove conditional |
| 12 | Restore plot7/7b to S3 | `R/visualization.R`, `R/export_plots.R` | Window width overlay |
| 13 | Restore plot2c/plot4/plot5 to S5 | `R/visualization.R`, `R/export_plots.R` | Strategy comparison |
| 14 | Final PDF assembly & verification | `R/export_plots.R` | Last step |

### Deferred

| Item | Reason |
|------|--------|
| `report_level` parameter | Future — add "standard" vs "detailed" mode |
| Redundant plot pruning | After `report_level` — conditionally skip legacy plots |

---

## Key Files

| File | Role |
|------|------|
| `R/theme_aidia.R` | Design system: theme, palettes, strategy labels |
| `R/export_plots.R` | PDF structure, front matter pages, grid panels |
| `R/visualization.R` | Stage 4 orchestrator: generates all plots |
| `R/plot_density.R` | Heatmap (2D/3D), m/z density profiles |
| `R/plot_fwhm_distribution.R` | FWHM histogram |
| `R/plot_dppp.R` | DPPP diagnosis table + legacy DPPP plots |
| `R/plot_satisfaction.R` | Satisfaction vs cycle time S-curve |
| `R/plot_tiling_coverage.R` | Window tiling integrity map |
| `R/plot_load_balance.R` | Precursor load balance per RT segment |
| `R/plot_impact_summary.R` | Before/after impact dashboard (2×2) |
| `R/plot_edge_proximity.R` | Window edge proximity histogram |
| `R/plot_strategy_comparison.R` | Width ridge, box, CDF, comparison table |
| `R/plot_density_overlay.R` | Boundary grid heatmap (Section 5) |

---

## Verification

1. Individual PNG output: `source("tests/manual/test_plot_comparison.R")`
2. Full PDF: `source("tests/manual/test_report_redesign.R")` (final step only)
3. Unit tests: `devtools::test()` — no API breaking changes
4. Visual checklist:
   - Style C theme consistent across all ggplot plots
   - Tables match dark-header / alternating-row style
   - No duplicate information across sections
   - Contour lines visible on heatmap density peaks
   - FWHM shows median + DPPP context (no P15)
   - Verdict colors in DPPP table (teal/red)
5. Shiny: `aidia::run_aidia_app()` — Step 3 still renders correctly
