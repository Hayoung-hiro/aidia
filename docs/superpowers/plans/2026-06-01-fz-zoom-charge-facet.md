# Charge-Resolved Forbidden Zone Zoom Plot — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `plot_fz_zoom()` render one facet per charge state (when charge data is present) so precursors appearing "inside" the z=1 forbidden-zone band are visibly explained as multi-charge signal rather than chased via offset fitting.

**Architecture:** Pure visualization change to a single file. Extract the current single-panel body into an internal helper, add a charge-faceted builder, and an orchestrator that picks faceted vs single-panel vs insufficient-data. No optimization, schema, or S3 changes. `Precursor.Charge` is already retained as a `QC_COLUMN` when present.

**Tech Stack:** R, ggplot2 (`facet_grid`, `after_stat(ndensity)`), dplyr, stats::density. Existing AIDIA helpers: `select_median_rt_segment`, `create_insufficient_data_plot`, `aidia_colors`, `aidia_charge_colors`, `theme_aidia`, `OPTIMAL_INCREMENT`.

**Spec:** `docs/superpowers/specs/2026-06-01-fz-zoom-charge-facet-design.md`

---

## File Structure

- **Modify:** `R/plot_fz_zoom.R` — replace the monolithic `plot_fz_zoom()` body with: orchestrator `plot_fz_zoom()` + internal helpers `fz_zoom_single_panel()`, `fz_zoom_faceted()`, `fz_zoom_band_df()`. All flat in `R/` (R package requirement).
- **Modify (tests):** `tests/manual/test_forbidden_zone.R` — add "Test 11: Charge-resolved FZ zoom" section (faceted path + fallback path). Uses the file's existing custom `pass()`/`fail()` harness.

**Note on test execution:** These manual tests use `devtools::load_all()` + mock tibbles (no parquet, no `data/`). The repo path on this machine is `C:/Projects/aidia` — the existing test file hardcodes `devtools::load_all("D:/Projects/aidia")` at line 11. Use `devtools::load_all(".")` in the new section's run instructions; do not edit the existing line 11 (out of scope). The developer runs these in a full R environment (RStudio/devtools), not the minimal Rscript.

---

## Task 1: Refactor — extract single-panel builder (no behavior change)

**Files:**
- Modify: `R/plot_fz_zoom.R:29-198` (the whole `plot_fz_zoom()` function)

- [ ] **Step 1: Extract the current plotting body into `fz_zoom_single_panel()`**

Replace the entire contents of `R/plot_fz_zoom.R` (keep the file header comment lines 1-8) with the code below. This step keeps behavior identical: `plot_fz_zoom()` still computes the boundary the same way and delegates rendering to the extracted helper.

```r
#' Forbidden Zone Zoom-in Plot (Micro View)
#'
#' Creates a zoomed view (~5 Da range) around a representative window boundary,
#' showing actual precursor m/z density. The FZ-optimized boundary (green) sits
#' in a low-density valley between isotope clusters at integer m/z positions,
#' while a naive integer boundary (red dashed) falls on a high-density peak.
#'
#' When `Precursor.Charge` is available and at least two charge states each have
#' >= 5 precursors in the zoom range, the plot is faceted by charge state so the
#' single placed boundary (computed on the z=1 grid) can be read against each
#' charge's own cluster periodicity. Otherwise a single combined panel is shown.
#'
#' Only generated when \code{fz_offset > 0} (forbidden zone optimization active).
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param boundary_index Integer, index of the internal boundary to zoom into.
#'   NULL (default) selects the median internal boundary.
#' @param fz_offset Numeric, forbidden zone offset used in optimization
#'   (default: 0.25)
#' @param zoom_range_da Numeric, total m/z range to display (default: 5)
#'
#' @return A ggplot object
#' @keywords internal
plot_fz_zoom <- function(optimized_windows,
                          validated_data,
                          boundary_index = NULL,
                          fz_offset = 0.25,
                          zoom_range_da = 5) {
  cat("  Generating FZ Zoom plot...\n")

  windows <- optimized_windows$windows
  precursor_data <- validated_data$data

  if (nrow(windows) == 0) stop("No windows found in optimized_windows object")

  is_staggered <- "cycle" %in% colnames(windows)

  # Get internal boundaries (excluding range edges)
  if (is_staggered) {
    c1_windows <- windows %>%
      filter(cycle == 1L) %>%
      arrange(rt_segment_id, mz_start)
  } else {
    c1_windows <- windows %>%
      arrange(rt_segment_id, mz_start)
  }

  # Select a representative RT segment (median)
  median_seg <- select_median_rt_segment(c1_windows)
  seg_windows <- c1_windows %>% filter(rt_segment_id == median_seg)

  if (nrow(seg_windows) < 2) {
    return(create_insufficient_data_plot(
      title = "Forbidden Zone Boundary Placement",
      message = "Need at least 2 windows to show internal boundaries"
    ))
  }

  internal_boundaries <- seg_windows$mz_end[-nrow(seg_windows)]

  # Select boundary
  if (is.null(boundary_index)) {
    boundary_index <- ceiling(length(internal_boundaries) / 2)
  }
  boundary_index <- min(boundary_index, length(internal_boundaries))
  fz_boundary <- internal_boundaries[boundary_index]

  # Nearest integer boundary (naive placement)
  integer_boundary <- round(fz_boundary)

  # --- Real precursor data in zoom window ---
  half_range <- zoom_range_da / 2
  mz_min <- fz_boundary - half_range
  mz_max <- fz_boundary + half_range

  zoom_idx <- precursor_data$Precursor.Mz >= mz_min &
    precursor_data$Precursor.Mz <= mz_max
  zoom_mz <- precursor_data$Precursor.Mz[zoom_idx]

  if (length(zoom_mz) < 5) {
    return(create_insufficient_data_plot(
      title = "Forbidden Zone Boundary Placement",
      message = sprintf("Only %d precursors in zoom range (%.1f-%.1f Da)",
                        length(zoom_mz), mz_min, mz_max)
    ))
  }

  # --- Charge-faceted path (only when charge data supports >= 2 panels) ---
  if ("Precursor.Charge" %in% colnames(precursor_data)) {
    zoom_charge <- as.integer(precursor_data$Precursor.Charge[zoom_idx])
    charge_df <- data.frame(mz = zoom_mz, charge = zoom_charge)
    charge_df <- charge_df[!is.na(charge_df$charge), ]
    counts <- table(charge_df$charge)
    retained <- as.integer(names(counts[counts >= 5]))
    if (length(retained) >= 2) {
      zoom_df <- charge_df[charge_df$charge %in% retained, ]
      return(fz_zoom_faceted(zoom_df, fz_boundary, integer_boundary,
                             mz_min, mz_max, fz_offset))
    }
  }

  # --- Fallback: single combined panel (original behavior) ---
  fz_zoom_single_panel(zoom_mz, fz_boundary, integer_boundary,
                       mz_min, mz_max, fz_offset)
}

#' Single-panel forbidden zone zoom (original layout)
#'
#' @param zoom_mz Numeric vector of precursor m/z within the zoom range
#' @param fz_boundary Numeric FZ-optimized boundary m/z
#' @param integer_boundary Numeric nearest-integer boundary m/z
#' @param mz_min,mz_max Numeric zoom range limits
#' @param fz_offset Numeric forbidden zone offset
#' @return A ggplot object
#' @keywords internal
fz_zoom_single_panel <- function(zoom_mz, fz_boundary, integer_boundary,
                                 mz_min, mz_max, fz_offset) {
  df <- data.frame(mz = zoom_mz)

  kde <- stats::density(zoom_mz, n = 1024, from = mz_min, to = mz_max,
                        adjust = 0.3)
  density_df <- data.frame(mz = kde$x, density = kde$y)
  density_df$density <- density_df$density / max(density_df$density)

  fz_center <- floor(fz_boundary) + 0.5
  fz_band_df <- data.frame(
    xmin = fz_center - fz_offset,
    xmax = fz_center + fz_offset,
    ymin = 0,
    ymax = 1.15
  )

  density_at_fz <- approx(density_df$mz, density_df$density, xout = fz_boundary)$y
  density_at_int <- approx(density_df$mz, density_df$density, xout = integer_boundary)$y

  ggplot() +
    geom_rect(
      data = fz_band_df,
      aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
      fill = aidia_colors$grid, alpha = 0.5
    ) +
    geom_histogram(
      data = df,
      aes(x = mz, y = after_stat(density) / max(after_stat(density))),
      bins = 80,
      fill = viridis::viridis(1, option = "cividis", begin = 0.4),
      alpha = 0.35, color = NA
    ) +
    geom_line(
      data = density_df,
      aes(x = mz, y = density),
      color = viridis::viridis(1, option = "cividis", begin = 0.6),
      linewidth = 0.8
    ) +
    geom_vline(xintercept = integer_boundary, color = aidia_colors$accent,
               linetype = "dashed", linewidth = 0.8, alpha = 0.8) +
    geom_vline(xintercept = fz_boundary, color = aidia_colors$success,
               linetype = "solid", linewidth = 1.0) +
    annotate("text", x = integer_boundary, y = 1.08,
             label = sprintf("Integer: %d", integer_boundary),
             color = aidia_colors$accent, size = 3.5, fontface = "bold",
             hjust = -0.1) +
    annotate("text", x = fz_boundary, y = 1.02,
             label = sprintf("FZ: %.2f", fz_boundary),
             color = aidia_colors$success, size = 3.5, fontface = "bold",
             hjust = -0.1) +
    annotate("text", x = fz_center, y = 1.12, label = "Forbidden Zone",
             color = aidia_colors$secondary, size = 3, fontface = "italic") +
    labs(
      title = "Forbidden Zone Boundary Placement",
      subtitle = sprintf(
        "FZ offset = %.2f Da | %d precursors in view | Boundary shifted %.2f Da from integer",
        fz_offset, length(zoom_mz), abs(fz_boundary - integer_boundary)
      ),
      caption = sprintf(
        "Actual precursor m/z density | Density at FZ boundary: %.2f vs Integer: %.2f (lower = better)",
        density_at_fz %||% 0, density_at_int %||% 0
      ),
      x = "m/z (Da)", y = "Relative Precursor Density"
    ) +
    theme_aidia() +
    theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank()) +
    coord_cartesian(xlim = c(mz_min, mz_max), ylim = c(0, 1.2))
}
```

- [ ] **Step 2: Regenerate docs and load the package**

Run:
```r
devtools::document()
devtools::load_all(".")
```
Expected: no errors; `fz_zoom_single_panel` registered as internal (no new `.Rd` for internals).

- [ ] **Step 3: Verify existing window-placement tests still pass (unaffected)**

Run: `Rscript tests/manual/test_forbidden_zone.R`
Expected: `STATUS: ALL TESTS PASSED` (this file does not yet call `plot_fz_zoom`; the refactor must not change its result).

- [ ] **Step 4: Commit**

```bash
git add R/plot_fz_zoom.R NAMESPACE man
git commit -m "refactor: extract fz_zoom_single_panel from plot_fz_zoom (no behavior change)"
```

---

## Task 2: Write the failing charge-facet test

**Files:**
- Modify: `tests/manual/test_forbidden_zone.R` (append a new section before the final Summary block at line ~453)

- [ ] **Step 1: Add the charge-resolved test section**

Insert this block immediately before the `# Summary` section (the `cat("\n===...RESULTS...")` block). It loads `ggplot2` for `ggplot_build()`, builds a dense mock with a `Precursor.Charge` column, and asserts the faceted vs fallback behavior.

```r
# ============================================================================
# Test 11: Charge-resolved FZ zoom plot
# ============================================================================

cat("\n--- Test 11: Charge-resolved FZ Zoom ---\n")

library(ggplot2)

# Dense mock so a 5 Da zoom window holds >= 5 precursors per charge state
set.seed(7)
n_dense <- 4000
charge_vec <- sample(c(2L, 3L, 4L), size = n_dense, replace = TRUE,
                     prob = c(0.6, 0.3, 0.1))
mock_charge <- tibble(
  Precursor.Id    = paste0("Precursor_", seq_len(n_dense)),
  Precursor.Mz    = runif(n_dense, min = 400, max = 1000),
  RT.Apex         = runif(n_dense, min = 5, max = 60),
  FWHM            = runif(n_dense, min = 0.08, max = 0.25),
  Precursor.Charge = charge_vec
)
validated_charge <- as_ValidatedData(mock_charge)

plan_charge <- plan_optimization(
  validated_data = validated_charge,
  instrument_preset = "astral",
  target_dppp = 7.0,
  target_satisfaction = 0.70
)

result_charge <- optimize_windows(
  validated_data = validated_charge,
  optimization_plan = plan_charge,
  mz_strategy = "greedy",
  window_mode = "fixed",
  fz_offset = 0.25
)

# Helper: count facet panels in a ggplot
panel_count <- function(p) nrow(ggplot2::ggplot_build(p)$layout$layout)

# 11a: charge present -> faceted (>= 2 panels)
p_faceted <- plot_fz_zoom(result_charge, validated_charge, fz_offset = 0.25)
if (inherits(p_faceted, "ggplot") && panel_count(p_faceted) >= 2) {
  pass(sprintf("Charge present: faceted plot with %d panels", panel_count(p_faceted)))
} else {
  fail(sprintf("Charge present: expected >= 2 facet panels, got %d",
               panel_count(p_faceted)))
}

# 11b: charge absent -> single panel (fallback, backward compatible)
mock_nocharge <- mock_charge
mock_nocharge$Precursor.Charge <- NULL
validated_nocharge <- as_ValidatedData(mock_nocharge)
result_nocharge <- optimize_windows(
  validated_data = validated_nocharge,
  optimization_plan = plan_charge,
  mz_strategy = "greedy",
  window_mode = "fixed",
  fz_offset = 0.25
)
p_single <- plot_fz_zoom(result_nocharge, validated_nocharge, fz_offset = 0.25)
if (inherits(p_single, "ggplot") && panel_count(p_single) == 1) {
  pass("Charge absent: single-panel fallback")
} else {
  fail(sprintf("Charge absent: expected 1 panel, got %d", panel_count(p_single)))
}
```

- [ ] **Step 2: Run the test and verify 11a FAILS**

Run: `Rscript tests/manual/test_forbidden_zone.R`
Expected: Test 11a FAILS — `plot_fz_zoom` currently always returns a single panel, so `panel_count(p_faceted)` is `1`, not `>= 2`. (11b should already PASS via the existing fallback.)

- [ ] **Step 3: Commit the failing test**

```bash
git add tests/manual/test_forbidden_zone.R
git commit -m "test: add failing charge-resolved FZ zoom facet test"
```

---

## Task 3: Implement the charge-faceted builder

**Files:**
- Modify: `R/plot_fz_zoom.R` (append the two new internal helpers referenced by the orchestrator from Task 1)

- [ ] **Step 1: Add `fz_zoom_band_df()` and `fz_zoom_faceted()`**

Append these functions to the end of `R/plot_fz_zoom.R`. `fz_zoom_band_df()` reproduces the z=1 band exactly (`(k+0.5)*1.0 ± fz_offset`) and scales period and half-width by `1/z` for higher charges — this is geometric (period `OPTIMAL_INCREMENT/z`), not a data fit.

```r
#' Per-charge forbidden-zone band rectangles for the zoom plot
#'
#' For charge \code{z}, isotope-cluster periodicity in m/z is
#' \code{OPTIMAL_INCREMENT / z}; gap centers fall at \code{(k + 0.5) * period}.
#' Reproduces the single-panel band exactly when \code{z == 1}.
#'
#' @param charge Integer charge state
#' @param mz_min,mz_max Numeric zoom range limits
#' @param fz_offset Numeric forbidden zone offset (band half-width at z=1)
#' @param ymax Numeric top of the band rectangle (default 1.15)
#' @return data.frame with columns charge, xmin, xmax, ymin, ymax
#' @keywords internal
fz_zoom_band_df <- function(charge, mz_min, mz_max, fz_offset, ymax = 1.15) {
  period <- OPTIMAL_INCREMENT / charge
  half <- fz_offset / charge
  k_min <- floor(mz_min / period) - 1
  k_max <- ceiling(mz_max / period) + 1
  centers <- (seq(k_min, k_max) + 0.5) * period
  centers <- centers[centers >= mz_min & centers <= mz_max]
  data.frame(
    charge = charge,
    xmin = centers - half,
    xmax = centers + half,
    ymin = 0,
    ymax = ymax
  )
}

#' Charge-faceted forbidden zone zoom (one panel per charge state)
#'
#' @param zoom_df data.frame with columns \code{mz} and \code{charge}
#'   (already filtered to charges with >= 5 precursors in range)
#' @param fz_boundary Numeric FZ-optimized boundary m/z (common to all facets)
#' @param integer_boundary Numeric nearest-integer boundary m/z
#' @param mz_min,mz_max Numeric zoom range limits
#' @param fz_offset Numeric forbidden zone offset
#' @return A ggplot object faceted by charge state
#' @keywords internal
fz_zoom_faceted <- function(zoom_df, fz_boundary, integer_boundary,
                            mz_min, mz_max, fz_offset) {
  charge_levels <- sort(unique(zoom_df$charge))

  density_df <- do.call(rbind, lapply(charge_levels, function(z) {
    mz_z <- zoom_df$mz[zoom_df$charge == z]
    kde <- stats::density(mz_z, n = 512, from = mz_min, to = mz_max,
                          adjust = 0.3)
    data.frame(mz = kde$x, density = kde$y / max(kde$y), charge = z)
  }))

  band_df <- do.call(rbind, lapply(charge_levels, function(z) {
    fz_zoom_band_df(z, mz_min, mz_max, fz_offset)
  }))

  # Color map keyed by charge (consistent with Plot 19)
  pal <- if (length(charge_levels) <= 5) {
    aidia_charge_colors[seq_along(charge_levels)]
  } else {
    viridis::viridis(length(charge_levels), option = "D")
  }
  names(pal) <- as.character(charge_levels)

  zoom_df$charge_f    <- factor(zoom_df$charge, levels = charge_levels)
  density_df$charge_f <- factor(density_df$charge, levels = charge_levels)
  band_df$charge_f    <- factor(band_df$charge, levels = charge_levels)

  ggplot() +
    geom_rect(
      data = band_df,
      aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
      fill = aidia_colors$grid, alpha = 0.5
    ) +
    geom_histogram(
      data = zoom_df,
      aes(x = mz, y = after_stat(ndensity), fill = charge_f),
      bins = 80, alpha = 0.35, color = NA, show.legend = FALSE
    ) +
    geom_line(
      data = density_df,
      aes(x = mz, y = density, color = charge_f),
      linewidth = 0.8, show.legend = FALSE
    ) +
    geom_vline(xintercept = integer_boundary, color = aidia_colors$accent,
               linetype = "dashed", linewidth = 0.8, alpha = 0.8) +
    geom_vline(xintercept = fz_boundary, color = aidia_colors$success,
               linetype = "solid", linewidth = 1.0) +
    scale_fill_manual(values = pal) +
    scale_color_manual(values = pal) +
    facet_grid(
      charge_f ~ .,
      labeller = labeller(charge_f = function(x) paste0("z = ", x))
    ) +
    labs(
      title = "Forbidden Zone Boundary Placement by Charge State",
      subtitle = sprintf(
        "FZ offset = %.2f Da | anchored to z = 2 | boundary shifted %.2f Da from integer",
        fz_offset, abs(fz_boundary - integer_boundary)
      ),
      caption = paste0(
        "Per-charge real precursor density. The z=1 grid boundary (green) ",
        "need not align with z=2/z=3 cluster gaps (shorter period)."
      ),
      x = "m/z (Da)", y = "Relative Precursor Density"
    ) +
    theme_aidia() +
    theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank()) +
    coord_cartesian(xlim = c(mz_min, mz_max))
}
```

- [ ] **Step 2: Regenerate docs and reload**

Run:
```r
devtools::document()
devtools::load_all(".")
```
Expected: no errors; new helpers internal (no new public `.Rd`).

- [ ] **Step 3: Run the test and verify Test 11 PASSES**

Run: `Rscript tests/manual/test_forbidden_zone.R`
Expected: `STATUS: ALL TESTS PASSED`, including `Charge present: faceted plot with 3 panels` (z=2,3,4) and `Charge absent: single-panel fallback`.

- [ ] **Step 4: Commit**

```bash
git add R/plot_fz_zoom.R NAMESPACE man
git commit -m "feat: facet FZ zoom plot by charge state when charge data present"
```

---

## Task 4: Document the behavior in domain knowledge

**Files:**
- Modify: `docs/domain-knowledge.md` (the "Mass Defect Forbidden Zones" → "Visualization: `plot_fz_zoom.R`" subsection, ~line 175)

- [ ] **Step 1: Update the visualization note**

Replace the existing `### Visualization: plot_fz_zoom.R (Plot 14)` paragraph with:

```markdown
### Visualization: `plot_fz_zoom.R` (Plot 14)
Zoomed KDE density plot (~5 Da range) around a representative window boundary using
**actual precursor m/z from the input data**. Shows FZ boundary (green solid) vs
integer boundary (red dashed). When `Precursor.Charge` is present and >= 2 charge
states each have >= 5 precursors in the zoom range, the plot **facets by charge
state** (one panel per z), drawing each charge's own periodicity band
(`OPTIMAL_INCREMENT / z`). This makes explicit that precursors appearing inside the
z=1 forbidden band are higher-charge signal (z=2 period ~0.5 Da, z=3 ~0.33 Da) on an
incommensurate grid — not an offset-estimation error. z=2 is the interpretation
anchor. Falls back to a single combined panel when charge data is absent.
Only generated when `fz_offset > 0`.
```

- [ ] **Step 2: Commit**

```bash
git add docs/domain-knowledge.md
git commit -m "docs: note charge-faceted behavior of plot_fz_zoom"
```

---

## Self-Review

**Spec coverage:**
- Charge-present facet path → Task 3 (`fz_zoom_faceted`), orchestrator branch in Task 1.
- Per-charge FZ band at `OPTIMAL_INCREMENT/z` → Task 3 (`fz_zoom_band_df`).
- ≥5-precursor retention + ≥2-charge gate → Task 1 orchestrator (`counts >= 5`, `length(retained) >= 2`).
- Fallback to single panel → Task 1 (`fz_zoom_single_panel`), test 11b.
- z=2 anchor in labels → Task 3 subtitle.
- No z=2-ideal reference line → omitted by design (not present in any task). ✓
- `aidia_charge_colors` reuse, `create_insufficient_data_plot` fallback → Task 1/Task 3. ✓
- No algorithm/schema/S3 change → only `R/plot_fz_zoom.R`, tests, docs touched. ✓
- Tests structural (panel count, ggplot class) → Task 2. ✓

**Placeholder scan:** No TBD/TODO; all code blocks complete.

**Type consistency:** Orchestrator calls `fz_zoom_faceted(zoom_df, fz_boundary, integer_boundary, mz_min, mz_max, fz_offset)` and `fz_zoom_single_panel(zoom_mz, fz_boundary, integer_boundary, mz_min, mz_max, fz_offset)` — signatures match the definitions in Tasks 1 and 3. `fz_zoom_band_df(charge, mz_min, mz_max, fz_offset)` matches its caller. `panel_count()` uses `ggplot2::ggplot_build(p)$layout$layout` consistently.
