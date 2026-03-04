# AIDIA PDF Report Visualization Review

**Date**: 2026-03-04
**Reviewers**: Data Scientist Agent (Opus) + Documentation Architect Agent (Opus)
**Target Audience**: Proteomics Researcher
**Per-strategy handling**: Summary in main body, detail in Appendix

---

## Core Report Structure (Target: ~14 pages)

| Section | Plot | Status |
|---------|------|--------|
| Cover | Cover Page | Keep — add version + dataset ID |
| Executive | Executive Summary | Keep — move BEFORE Parameter Summary |
| Params | Parameter Summary | Keep — 2-column layout |
| S1: Input | FWHM Distribution | Keep |
| S1: Input | RT×m/z Heatmap | Keep — increase density grid n=150 |
| S2: DPPP | DPPP Enhanced only | Keep — remove Simple |
| S2: DPPP | Satisfaction Curve | Keep — simplify annotations |
| S2: DPPP | Impact Summary | Keep — fix "Before window count" |
| S3: Windows | m/z Density Overlay | Keep |
| S3: Windows | Window Gantt | Keep |
| S4: Strategy | Strategy Table | Keep |
| S4: Strategy | Strategy Ridge only | Keep — add Q1/Q3 quantile lines |
| S5: Verification | Tiling Coverage | Keep |
| S5: Verification | Alignment Density | Keep — expand to 3 RT segments |
| S5: Verification | FZ Zoom (conditional) | Keep — add set.seed + "Schematic" label |

## Removed from PDF

| Plot | Reason |
|------|--------|
| DPPP Simple (1a) | Enhanced is strict superset |
| RT Histogram continuous (2b) | 1D projection of Heatmap (#2) |
| RT Histogram binned (2b-5min) | Triple redundancy with #2, #2b |
| RT Bin Quality Heatmap (#9) | Min-max normalization misleads cross-metric comparison |
| m/z Width All Strategies (4e) | Redundant with Strategy Table (8d) |
| Strategy Box (8b) | Ridge with Q1/Q3 lines sufficient |
| Strategy CDF (8c) | Ridge with Q1/Q3 lines sufficient |

## Appendix (per-strategy detail)

| Plot | Content |
|------|---------|
| m/z Excluded (×5) | Per-strategy exclusion regions |
| Window Width Distribution (×5) | Per-RT-bin density + width |
| Coverage Map 2×2 | 4-strategy coverage comparison |

## Critical Issues Fixed

| # | Issue | Location | Fix |
|---|-------|----------|-----|
| 1 | `plot_mz_width.R` strategy colors outdated | L35-49 | Use `aidia_strategy_colors`, add Greedy/KDE |
| 2 | Impact Summary "Before window count" non-scientific | L200-203 | Remove panel or show "N/A" |
| 3 | FZ Zoom `runif()` without seed | L87-88 | Add `set.seed(42)` + "Schematic" subtitle |
| 4 | Executive Summary buried after Parameter Summary | export_plots.R:344 | Move before Parameter Summary |
| 5 | `exists()` guards ×11 dead in package mode | visualization.R | Remove all guards |

## Important Issues Fixed

| Issue | Location | Fix |
|-------|----------|-----|
| Density heatmap resolution too low | plot_density.R | n=50 → n=150 |
| base_size inconsistent across files | multiple | Remove overrides, use theme_aidia() default |
| Cover page missing version/dataset ID | export_plots.R | Add AIDIA version + gradient name |
| `toupper()` vs `format_strategy_label()` | plot_impact_summary.R | Use `format_strategy_label()` |
| DPPP annotation too dense | plot_dppp.R | Simplify mono text block |
| Hard-coded DPPP x-axis limit (0-15) | plot_dppp.R | Use data-driven range |
