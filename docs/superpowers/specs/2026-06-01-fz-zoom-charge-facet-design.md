# Spec: Charge-Resolved Forbidden Zone Zoom Plot

**Date**: 2026-06-01
**Status**: Approved (design), pending implementation plan
**Scope**: Visualization only — no algorithm, schema, or S3 field changes

---

## Background

`plot_fz_zoom()` (Plot 14, `R/plot_fz_zoom.R`) shows a ~5 Da zoom around one
representative window boundary, with actual precursor m/z density and a shaded
"forbidden zone" band drawn at period **1.0 Da (z=1)** around `floor(boundary)+0.5`.

Users observing this plot frequently see precursors sitting *inside* the drawn
FZ band and infer the offset has "room to move." Investigation established that
this is **not an estimation error**:

- The drawn band assumes a single **z=1 periodicity (1.00045 Da)**.
- Tryptic data is dominated by **z=2** (then z=3, z=4), whose isotope/mass-defect
  periodicity in m/z is **~0.5 Da (z=2)** and **~0.33 Da (z=3)** — incommensurate
  with the z=1 grid. These higher-charge precursors legitimately populate the
  z=1 "forbidden" band.
- A single boundary cannot empty all charge periodicities simultaneously
  (periods 1.0 / 0.5 / 0.33 share no common divisor).
- Data-driven offset fitting was rejected: circular bias (report contains only
  DIA-NN-identified precursors → previously-split precursors look "absent"),
  overfitting to a single plotted boundary, breakage of staggered Loop Control N
  uniformity, and sub-quadrupole-resolution payoff. See
  `docs/domain-knowledge.md` ("Decision: FZ Validation Module — REJECTED").

**Conclusion**: keep the fixed offset (0.25 / phospho 0.18). The valuable,
proportionate improvement is **diagnostic, not algorithmic** — make the plot
charge-resolved so the "data in the FZ" effect is *explained* (it is multi-charge
signal) rather than chased. z=2 is the correct anchor because higher charges'
cluster layers narrow or vanish.

## Goal

When charge information is available, render `plot_fz_zoom` as a **per-charge
facet** (one horizontal panel per charge state), each showing that charge's own
real precursor density, so the reader can see the actual placed boundary sitting
relative to each charge's clusters. Anchor the interpretation to z=2.

## Non-Goals

- No change to `OPTIMAL_INCREMENT`, `calc_forbidden_edge`,
  `transform_boundaries_to_fz`, or any boundary placement logic.
- No new S3 field, no change to `ESSENTIAL_COLUMNS` / `QC_COLUMNS`.
- No "z=2-ideal boundary" reference line (explicitly declined — avoids implying
  the boundary should move).
- No per-dataset offset fitting.

## Design

**Single function modified**: `plot_fz_zoom()` in `R/plot_fz_zoom.R`.

### Data availability (already satisfied)

`Precursor.Charge` is in `QC_COLUMNS` (`R/column_selection.R:39`) and is retained
when present in the input (`:119` `intersect(QC_COLUMNS, available_columns)`).
DIA-NN reports include it by default. No schema work required.

### Behavior

1. **Boundary selection** — unchanged: median RT segment
   (`select_median_rt_segment`), middle internal boundary. The vertical
   boundary lines (FZ green solid, integer red dashed) are computed exactly as
   today and are **common to all facets**.

2. **Charge-present path** (`Precursor.Charge` exists AND ≥2 distinct charges
   each with ≥5 precursors in the zoom range):
   - Partition zoom-range precursors by charge state.
   - Keep only charges with ≥5 precursors in view (reuses the existing
     5-precursor minimum); drop sparse charges from faceting.
   - One facet row per retained charge, ordered ascending (z=2, z=3, z=4, ...),
     via `facet_grid(charge ~ .)` (or `facet_wrap(~charge, ncol = 1)`).
   - Per facet: histogram + KDE of that charge's precursors (same styling as
     current single-panel), plus a shaded FZ band drawn at that charge's
     periodicity `OPTIMAL_INCREMENT / z` to show where that charge's gaps fall.
   - Fill colors keyed by charge via the existing `aidia_charge_colors` palette
     (consistent with Plot 19, `plot_charge_mz.R`).
   - Subtitle/caption anchor to z=2 (state z=2 as the design basis and report
     per-charge precursor counts in view).

3. **Fallback path** (no `Precursor.Charge`, OR only one charge with enough data):
   - Exactly the current single-panel plot. Full backward compatibility.

4. **Insufficient data**: reuse `create_insufficient_data_plot()` exactly as
   today (e.g., <5 precursors in the zoom range overall, <2 windows in segment).

### Per-charge FZ band math

For charge `z`, the m/z-space periodicity of peptide isotope clusters is
`inc_z = OPTIMAL_INCREMENT / z`. The shaded forbidden band per facet is drawn at
this period across the zoom range (semi-transparent, same grid color as today),
making explicit that the single placed boundary aligns with z=1 gaps but not
necessarily z=2/z=3 gaps.

## Data flow

Inputs unchanged: `(optimized_windows, validated_data, boundary_index, fz_offset,
zoom_range_da)`. Internally adds a charge-grouping branch over
`validated_data$data$Precursor.Charge`. Returns a single ggplot object in all
paths (faceted or single-panel), so the `PLOT_REGISTRY` dispatcher and PDF
report need no changes.

## Error handling

- Missing `Precursor.Charge` → fallback path (no error).
- Charge present but degenerate (one charge, or all charges sparse) → fallback.
- Standard insufficient-data guards retained.

## Testing

Functional/manual (data dir empty in dev — user runs tests):

- Extend `tests/manual/test_forbidden_zone.R` mock data with a `Precursor.Charge`
  column (skewed toward z=2, then z=3, z=4) and add structural assertions:
  - charge-present input → returned object is a `ggplot` with facet layout
    (e.g., `length(ggplot_build(p)$layout$layout$PANEL) >= 2`).
  - charge-absent input (current mock) → returned object is a `ggplot` with a
    single panel (fallback path exercised).
  - single-charge input → single panel (degenerate guard).
- Assertions are structural (ggplot object, panel count, layers), not visual.

## Open questions

None blocking. Facet vs facet-implementation detail (`facet_grid` vs
`facet_wrap`) is an implementation choice during planning.
