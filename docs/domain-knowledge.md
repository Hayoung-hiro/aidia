# AIDIA Domain Knowledge

Accumulated domain-specific knowledge, design decisions, and future feature designs
for the AIDIA (Adaptive Isolation for DIA) project.

---

## Bayesian Optimization for Auto-Tune Window Placement

### Background: py_diAID Approach

py_diAID (Proteomics, 2022) uses Bayesian Optimization (BO) to optimize DIA isolation
windows on Bruker TimsTOF instruments (m/z x ion mobility 2D plane):

1. **Trapezoid parameterization**: Defines a scan area as a trapezoid in m/z x IM space (~6 parameters: corner coordinates)
2. **Variable-width windows**: Within the trapezoid, m/z axis is divided so each window contains approximately equal precursor counts (uniform spectral complexity)
3. **IM extension**: Top/bottom windows are extended to IM limits to capture outlier precursors
4. **BO iteration**: Evaluates precursor coverage against a spectral library, then uses BO (Gaussian Process surrogate + Expected Improvement) to iteratively adjust trapezoid shape (~200 iterations)

### Applicability to AIDIA

AIDIA operates on **m/z x RT** (no IM dimension). Key differences:

| Aspect | py_diAID (m/z x IM) | AIDIA (m/z x RT) |
|--------|---------------------|-------------------|
| Optimization target | Trapezoid shape (6 params) | Window placement per RT bin (1D) |
| Dimension correlation | m/z-IM: high (sloped trapezoid needed) | m/z-RT: low (R²=1.56%), bins independent |
| BO necessity | High (trapezoid slope is non-intuitive) | Moderate (m/z ranges are data-derivable) |
| Eval cost | Moderate (library matching) | Very low (~ms, just counting precursors) |

#### What AIDIA already implements from py_diAID's principles:
- **Equal precursor per window**: Greedy (MacCoss) strategy distributes windows so each contains similar precursor counts
- **Variable width**: Density window mode adapts width to precursor density
- **Adaptive RT bins**: Change point detection adjusts RT bin boundaries to data distribution

#### Where BO adds value in AIDIA:

| Level | Optimization Target | Params | Value |
|-------|---------------------|:------:|:-----:|
| **A. Hyperparameter auto-tune** | Strategy parameters (KDE bandwidth, quantile range, etc.) | 4-8 | HIGH |
| **B. RT bin boundaries** | Adaptive binning boundary positions | N_bins-1 | MEDIUM |
| **C. PTM-aware regions** | Where to place narrow windows for PTM m/z zones | 2-6 | HIGH (future) |

### Auto-Tune Design

#### Concept

```r
# User-facing API
auto_config <- auto_tune_config(
  validated_data,
  optimization_plan,
  objective = "coverage",         # or "dppp_uniformity", "balanced"
  strategy = "greedy",            # fix strategy, tune its params
  n_iter = 100                    # BO iterations (default)
)

# Returns an optimized strategy_config object
results <- optimize_windows(data, plan, strategy_config = auto_config)
```

#### Search Space (per strategy)

| Strategy | Tunable Parameters | Range |
|----------|-------------------|-------|
| greedy | `mz_step`, `apply_smoothing`, `smoothing_window` | 0.5-5.0 Da, T/F, 5-15 |
| kde | `density_threshold`, `min_coverage` | 0.01-0.20, 0.70-0.95 |
| quantile | `lower`, `upper`, `apply_smoothing` | 0.01-0.15, 0.85-0.99, T/F |
| coverage | `target_coverage` | 0.80-0.99 |
| outlier | `threshold`, `apply_smoothing` | 2.0-4.0, T/F |
| **Common** | `rt_bin_width`, `min_width_da`, `fz_offset` | 2-10 min, 2-10 Da, 0-0.5 |

#### Objective Functions

```r
# 1. Coverage maximization (simple, default)
obj_coverage <- function(result) {
  result$statistics$coverage_percentage
}

# 2. DPPP uniformity (minimize per-bin DPPP coefficient of variation)
obj_dppp_uniform <- function(result) {
  per_bin_dppp <- compute_per_bin_dppp(result)
  -calculate_cv(per_bin_dppp)  # negative because BO maximizes
}

# 3. Balanced (multi-objective weighted sum)
obj_balanced <- function(result, w_cov = 0.6, w_dppp = 0.3, w_width = 0.1) {
  coverage_score  <- result$statistics$coverage_percentage / 100
  dppp_score      <- 1 - calculate_cv(per_bin_dppp)
  width_score     <- 1 - calculate_cv(result$windows$window_width)
  w_cov * coverage_score + w_dppp * dppp_score + w_width * width_score
}

# 4. Precursor uniformity (py_diAID-inspired: minimize CV of precursors per window)
obj_precursor_uniform <- function(result) {
  -calculate_cv(result$windows$n_precursors)
}
```

#### R Library Options

| Library | Pros | Cons |
|---------|------|------|
| `rBayesianOptimization` | Lightweight, simple API, CRAN | Limited surrogate options |
| `mlrMBO` | Full-featured, custom surrogates/infill | Heavy dependencies |
| Custom GP + EI | Zero dependencies, ~100 lines | Maintenance burden |

**Recommendation**: `rBayesianOptimization` in `Suggests` (optional dependency). Falls back
to random search if not installed.

### Implementation Considerations

#### Why BO over grid/random search?

For AIDIA's auto-tune use case, the objective function is **very cheap** (~ms per evaluation).
This actually argues AGAINST BO (which shines when evaluations are expensive). However:

1. **Mixed parameter types** (continuous + boolean) make grid search combinatorially explosive
2. **Parameter interactions** (e.g., `mz_step` interacts with `smoothing_window`) are better captured by GP surrogate
3. **User experience**: BO converges in ~50-100 iterations vs ~1000+ for random search with same quality
4. **Extensibility**: When PTM-aware optimization adds more parameters, BO scales better

#### Integration with existing architecture

```
Current flow:
  User → strategy_config() → optimize_windows() → result

Auto-tune flow:
  User → auto_tune_config() ──────────────────────────> optimized strategy_config()
              │                                                    ↑
              ├─ BO iteration 1: trial config → optimize_windows() → score
              ├─ BO iteration 2: trial config → optimize_windows() → score
              ├─ ...
              └─ BO iteration N: best config found ────────────────┘
```

Key: `auto_tune_config()` wraps the existing `optimize_windows()` pipeline as a black-box
objective function. No changes to Stage 3 internals needed.

#### Planned implementation timeline

- **v0.3.0**: Auto-tune for strategy hyperparameters (Level A)
- **v0.4.0**: PTM-aware optimization with BO for narrow-window placement (Level C)
- **Future**: RT bin boundary optimization (Level B, if adaptive binning proves insufficient)

---

## Mass Defect Forbidden Zones

### Physical Basis

Amino acid residues have an average mass increment of **1.00045475 Da** (stored as
`OPTIMAL_INCREMENT` in `R/window_generation.R`). This creates a periodic "forbidden zone"
pattern in the m/z axis where peptide precursor ions cannot exist.

### Application

By placing isolation window boundaries at these forbidden zone positions, we:
1. Avoid splitting a precursor's isotope envelope across two windows
2. Maximize the m/z distance between boundaries and actual precursor peaks
3. Improve quantification accuracy by capturing complete isotope clusters

### Parameters
- **Standard offset**: `fz_offset = 0.25` Da (general proteomics)
- **Phospho offset**: `fz_offset = 0.18` Da (phosphoproteomics, tighter due to phospho mass defect)
- **Disabled**: `fz_offset = 0` (no forbidden zone placement)

### Implementation
- `calc_forbidden_edge(nominal_mz, fz_offset)`: Scalar forbidden zone calculation
- `transform_boundaries_to_fz(boundaries, fz_offset)`: Vectorized boundary array transform
- `integerize_boundaries()`: Always applied first (integer boundaries → deterministic FZ transform)

### Visualization: `plot_fz_zoom.R` (Plot 14)
Zoomed KDE density plot (~5 Da range) around a representative window boundary using
**actual precursor m/z from the input data**. Shows FZ boundary (green solid) sitting
in a low-density valley vs integer boundary (red dashed) on a high-density peak.
Caption reports quantitative density comparison at both positions.
Only generated when `fz_offset > 0`.

### Decision: FZ Validation Module — REJECTED (2026-03-09)

A standalone FZ validation module (`validate_fz_offset()`) was proposed to quantitatively
verify whether a given `fz_offset` is valid for the user's dataset by computing Peak/FZ
density ratios per charge state. After domain review, this was **rejected** for the
following reasons:

1. **No new information**: The mass defect pattern is a physical property of amino acid
   composition, not a per-dataset variable. For tryptic digests, offset=0.25 is universally
   correct. For phospho-enriched samples, 0.18 is already provided as a preset. The
   validation would only confirm what is already known from sample type.

2. **Circular bias**: The input `report.parquet` contains only DIA-NN-identified precursors.
   If the original DIA acquisition already split precursors at certain m/z positions, those
   precursors are missing from the report, making any m/z position appear "empty" and
   biasing validation toward PASS.

3. **Existing coverage**: `plot_fz_zoom.R` already demonstrates FZ effectiveness using
   real precursor data with quantitative density comparison. This provides the same
   assurance without a separate validation step.

4. **Glycoproteomics inapplicable**: Confirmed that glyco-enriched samples have
   unpredictable mass defect patterns incompatible with the Nefedov constant approach,
   limiting the module's value for the most uncertain use case.

5. **Offset selection is sample-type-driven**: Users choose fz_offset based on their
   enrichment protocol (standard=0.25, phospho=0.18, unknown=disabled), not from
   data-driven fitting. A validation step would not change this decision.

**Reference**: Full plan preserved in git history (`PLAN_AIDIA_FZ_VALIDATION.md`,
removed in commit after this decision).

---

## Geometric CV for Proteomics Data

### Why not arithmetic CV?

Proteomics intensity data follows a **log-normal distribution** (multiplicative noise model).
Arithmetic CV (SD/mean) systematically underestimates variability for log-normal data
(by ~14x in typical proteomics datasets).

### Formula

```r
# Geometric CV (correct for log-normal)
geo_cv <- sqrt(exp(var(log(x))) - 1)

# Arithmetic CV (incorrect for log-normal)
arith_cv <- sd(x) / mean(x)
```

### Usage in AIDIA

Applied in `R/replicate_utils.R` for technical replicate consensus filtering:
- Default threshold: 30% geometric CV
- Precursors exceeding threshold are filtered from consensus dataset

---

## DPPP (Data Points Per Peak) Guidelines

### Formula
```
DPPP = PEAK_WIDTH_FACTOR * FWHM_seconds / cycle_time_seconds
```
Where `PEAK_WIDTH_FACTOR = 1.7` (captures ~94% of Gaussian peak area at ±1.7σ).

### Target Modes
| Mode | Target DPPP | Use Case |
|------|:-----------:|----------|
| Quantification | 7.0 | Accurate peak area integration |
| Balanced | 4.0 | General purpose |
| Identification | 1.5 | Maximum proteome coverage |

### Shared API Rule
**Never inline the DPPP formula.** Always use `calculate_dppp()` from `R/dppp.R`.
Similarly, use `ensure_fwhm_seconds()` for FWHM unit conversion and
`estimate_window_count_preview()` for quick window count estimation.

---

## Boundary Smoothing Design (SG vs WH vs Modified Sinc)

### Context

m/z window boundaries across RT bins can exhibit abrupt jumps due to per-bin
optimization noise. Post-hoc smoothing of these boundaries produces physically
sensible window transitions. AIDIA supports two smoothing methods: Savitzky-Golay
(SG) and Whittaker-Henderson (WH).

### References

1. Schmid, M.; Rath, D.; Diebold, U. "Why and How Savitzky-Golay Filters Should
   Be Replaced". *ACS Measurement Science Au*, 2022, 2(2), 185-196.
   DOI: [10.1021/acsmeasuresciau.1c00054](https://pubs.acs.org/doi/10.1021/acsmeasuresciau.1c00054)
   — Proposes SGW (windowed SG) and Modified Sinc kernels as improved FIR
   alternatives; WH as comparison baseline for boundary handling.

2. Eilers, P.H.C. "A Perfect Smoother". *Analytical Chemistry*, 2003, 75(14),
   3631-3636. DOI: 10.1021/ac034173t
   — Foundation for Whittaker-Henderson penalized smoothing used in AIDIA.

### Paper's Key Contributions

1. **SGW (Savitzky-Golay with Window)**: Apply a tapering window function
   (e.g., Hann-square) to SG fitting weights → smooth kernel edges → better
   stopband attenuation (high-frequency noise rejection)

2. **Modified Sinc Kernel**: Truncated sinc with Gaussian window + moment
   correction for flat passband → near-ideal low-pass filter as FIR kernel

3. **Boundary handling**: Linear extrapolation before smoothing, trim after
   → avoids edge artifacts (vs. our current approach of keeping raw values)

4. **WH role in paper**: Comparison alternative only — authors recommend
   Modified Sinc + extrapolation over WH for general spectroscopic data

### Why AIDIA Uses WH as Default (Justified Deviation)

The paper targets spectroscopic signals with **thousands of data points** where
frequency-domain behavior matters. AIDIA smooths m/z boundaries across
**10-50 RT bins** — a fundamentally different regime:

| Aspect | Paper's Context | AIDIA's Context |
|--------|----------------|-----------------|
| Data length | 1000s of points | 10-50 RT bins |
| Signal type | Spectroscopic peaks | m/z boundary positions |
| Key need | Frequency selectivity | Weighted fidelity |
| WH cost (O(n³)) | Prohibitive | Negligible (n≤50) |

**WH advantages for our use case**:
- **Per-point weights**: `sqrt(n_precursors)` — bins with more data are trusted
  more, sparse bins are smoothed toward neighbors. SG/FIR methods lack this.
- **Global optimization**: No boundary artifacts by design (WH solves over all
  points simultaneously). No need for extrapolation tricks.
- **Lambda=10 with d=2**: Second-order difference penalty (smoothness), moderate
  strength. Appropriate for 10-50 point sequences.

### Lambda Selection Rationale

- **Fixed lambda=10**: Works well for typical 15-30 bin scenarios. The penalty
  balances data fidelity vs smoothness appropriately at this scale.
- **Configurable via `strategy_config`**: `whittaker_lambda` parameter exists
  in `greedy_config()`, `quantile_config()`, `outlier_config()` for programmatic
  users. Not exposed in Shiny UI (Expert panel could add it if needed).
- **Auto-tuning (GCV/AIC)**: Not implemented. For n=10-50, the improvement over
  fixed lambda=10 is marginal and adds complexity. Could be reconsidered if
  AIDIA scales to finer RT binning (100+ bins).

### SG Boundary Fix (DONE)

`smooth_savgol()` in `smoothing_utils.R` now uses `extrapolate_linear()` to
extend data by `half_window` points on each side before applying SG, then trims
the result back to original length. This replaces the naive approach of keeping
raw boundary values, eliminating edge artifacts per Schmid et al. (2022).

---

## Frontend Design System — Shiny UI (bs4Dash)

### Overview

AIDIA's Shiny app uses bs4Dash (AdminLTE3 / Bootstrap 4) with a custom CSS design system
in `inst/shiny_app/www/custom.css`. The design follows a monochrome + teal accent palette
with semantic CSS variables for light/dark mode support.

### Design Token System

All colors are defined as CSS variables in `:root` and overridden in `body.dark-mode`.
**Never use hardcoded hex colors in R server files** — always reference CSS classes or variables.

| Token Category | Examples | Usage |
|---------------|----------|-------|
| **Surfaces** | `--surface-page`, `--surface-card`, `--surface-raised`, `--surface-sunken` | Background colors for page, boxes, elevated/recessed panels |
| **Text** | `--text-primary`, `--text-secondary`, `--text-muted` | Three-level text hierarchy |
| **Borders** | `--border-default`, `--border-subtle` | Structural vs decorative borders |
| **Accent** | `--accent` (#1abc9c), `--accent-hover`, `--accent-subtle`, `--accent-muted` | Teal accent + variants |
| **Semantic** | `--semantic-success/warning/danger/info` + `*-bg` | Status colors + translucent backgrounds |
| **Box Headers** | `--box-header-bg`, `--box-header-text`, `--box-header-border` | Unified flat box headers |

### Typography Hierarchy (4 Levels)

Defined in custom.css, enforced via `!important` to override inline styles:

| Level | Element / Class | Size | Weight | Color | Use For |
|-------|----------------|:----:|:------:|-------|---------|
| **1** | `.section-title` (h4) | 15px (16px in wide cols) | 700 | `--text-primary` | Box section headings (e.g., "Peak Width Distribution") |
| **2** | `h5` inside `.box-body` | 16px | 600 | `--text-primary` | Sub-section headings (handled by CSS rule) |
| **3** | `.box-body` body text | 14px | 400 | `--text-primary` | Normal content text |
| **4** | `.help-block`, `small`, `.form-text` | 13px | 400 | `--text-muted` | Descriptions, captions, helper text |

**Rules**:
- Use `tags$h4(..., class = "section-title")` for prominent section headings within boxes
- Use `tags$h4(..., class = "section-title strategy-heading")` for accent-colored strategy headings
- The CSS `!important` on `.help-block` overrides any inline `font-size` on `helpText()` calls
- Never set `font-size` below 13px — this is the readability floor
- Form labels (`.control-label`) are 13px semi-bold (Level 4, but emphasized)

### CSS Utility Classes (for renderUI)

These classes are theme-safe (respond to dark mode) and should replace inline styles:

| Class | Purpose | Key Properties |
|-------|---------|---------------|
| `.panel-raised` | Neutral elevated panel | `background: --surface-raised`, rounded, padding |
| `.panel-accent` | Accent-tinted panel with left border | `background: --accent-muted`, `border-left: 3px solid --accent` |
| `.status-pass` | Green status panel | `background: --semantic-success-bg`, `border-left: 3px solid --semantic-success` |
| `.status-fail` | Red status panel | `background: --semantic-danger-bg`, `border-left: 3px solid --semantic-danger` |
| `.badge-dark` | Dark inline badge | `background: --text-primary`, white text |
| `.badge-accent` | Accent inline badge | `background: --accent`, white text |
| `.text-accent` | Teal text | `color: var(--accent)` |
| `.text-semantic-success/warning/danger/info` | Semantic text colors | Status-colored text |
| `.text-muted` | Muted gray text | `color: var(--text-muted)` |
| `.summary-list` | Results summary list | 13px, `line-height: 1.8` |
| `.mode-description` | Window mode description card | Raised background, rounded, small text |
| `.strategy-section` | Strategy parameter wrapper | Left border accent, padding |
| `.placeholder-section` | Empty state placeholder | Centered, large icon, muted text |
| `.results-status-bar` | Compact status bar (Step 3) | Accent-subtle bg, rounded, flex layout |

### Dark Mode Implementation

- `dark = NULL` in `dashboardPage()` → light default, toggle visible in navbar
- `body.dark-mode` class is toggled by AdminLTE3 — all CSS tokens auto-switch
- **Known limitation**: ggplot2 plots render server-side with fixed colors; they do not adapt to dark mode
- Server-rendered `style` attributes using `sprintf("color: var(--semantic-success)")` work correctly in both modes

### Layout Rules

| Property | Value | Context |
|----------|-------|---------|
| `.content` padding | 12px 16px (16px 20px desktop) | Main content area |
| `.box-body` padding | 12px 16px (16px 20px desktop) | Box inner content |
| `.box` margin-bottom | 12px | Between boxes |
| `.equal-height-row` child gap | 6px | Between side-by-side boxes |
| `.wizard-nav` padding | 12px 0 | Navigation buttons at bottom |

### Verification Checklist

When modifying the Shiny UI, verify these items:

**Visual Consistency**:
- [ ] All text ≥ 13px (readability floor enforced by CSS `!important`)
- [ ] No hardcoded hex colors in R files — use CSS classes/variables
- [ ] Section headings use `.section-title` class (not raw `h5` with inline styles)
- [ ] Help text uses `helpText()` (which renders as `.help-block`, auto-styled by CSS)
- [ ] Box headers are flat (no gradients) — unified `--box-header-bg`

**Dark Mode**:
- [ ] Toggle works (navbar button switches `body.dark-mode`)
- [ ] All text readable on dark backgrounds
- [ ] No white-on-white or dark-on-dark contrast issues
- [ ] Server-rendered panels use CSS classes, not inline `background: #xxx`

**Layout**:
- [ ] Upload + Instrument row width matches DPPP Preview width (both `width = 12` equiv)
- [ ] `equal-height-row` children align vertically with 6px gutters
- [ ] Collapsed boxes (C: RT Binning, D: Expert) expand/collapse properly
- [ ] Navigation buttons ("Continue"/"Back") are visible and aligned

**Functionality**:
- [ ] `conditionalPanel` show/hide works for all instrument-dependent controls
- [ ] DPPP preset buttons toggle correctly (client-side JS sync)
- [ ] Strategy-specific parameter panels appear/disappear
- [ ] Upload → DPPP preview → optimization → results flow works end-to-end
- [ ] CSV and PDF downloads generate correctly

### Anti-Patterns to Avoid

1. **Inline `style="color: #xxx"` in R files** — breaks dark mode. Use CSS classes.
2. **`font-size` below 13px** — unreadable. The CSS `!important` floor prevents this, but don't fight it.
3. **Gradient headers** — removed. All box headers use flat `--box-header-bg`.
4. **`dark = FALSE`** — removes the dark mode toggle entirely. Use `dark = NULL` for optional toggle.
5. **Duplicating server output in UI templates** — e.g., `textOutput("x")` that already includes context text, then adding more text around it in the UI. Check server render functions before wrapping.

---

## Export Format & Evaluation Design (v0.3.0)

### Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| RT in Format B/C | Include (rt_start, rt_end columns) | AIDIA is RT-dependent; omitting RT loses information |
| Instrument scope | Thermo only | Verified instruments are all Thermo Orbitrap |
| External method import | Not needed | AIDIA methods compared against each other |
| Batch download | ZIP for batch; individual buttons per format | UX balance |
| BO Auto-Tune | Deferred | No clear objective function — geometry metrics are proxies, not ground truth |
| max_width_da | Expose in Shiny UI next to min_width_da | Prevents extreme windows in sparse m/z regions |

### Export Formats (3 types)

All formats include RT columns because AIDIA generates RT-dependent windows.

**Format A: Thermo Targeted Mass List** (existing — `export_windows_to_csv()`)
```
Compound, Formula, Adduct, m/z, z, t start (min), t stop (min),
Isolation Window (m/z)
```
- 8 columns, Xcalibur import compatible (`Adduct = "(no adduct)"`)
- RT schedule is a **contiguous tiling** of `[acquisition_start_min,
  acquisition_end_min]`: interior boundaries are adjacent-segment midpoints,
  rounded once → zero gap/overlap/void (no MS1-only dead zones). Pass
  `acquisition_end_min` to close the trailing void; leading void closes at 0.

**Format B: Center Mass List** (new — `export_center_mass_list()`)
```
rt_start, rt_end, center_mass_mz, window_width_mz
```
- 4 columns, generic format
- Useful for method reconstruction in other software

**Format C: m/z Range List** (new — `export_mz_range_list()`)
```
rt_start, rt_end, mz_start, mz_end
```
- 4 columns, boundary-explicit format
- 7 decimal places for precision
- Useful for method verification and comparison

### In-Silico Evaluation

**Purpose**: Show how optimized windows distribute precursors from the input data.
Not a replacement for DIA-NN reanalysis, but provides immediate feedback on
window quality without requiring instrument time.

**New function**: `evaluate_windows()` in `R/window_evaluation.R`

```r
evaluate_windows(optimized_windows, validated_data, optimization_plan)
# Returns:
#   per_window: data.frame with window_id, rt_bin, mz_start, mz_end,
#               width, n_precursors, load_ratio, width_ok
#   per_rt_bin: data.frame with rt_bin, n_windows, mean_width, coverage,
#               precursor_cv, dppp_satisfaction
#   overall:    list(coverage_pct, load_balance_cv, width_stats, dppp_median)
#   quality_flags: list(empty_windows, overloaded_windows, width_violations,
#                       high_cv_bins)
```

**Quality flags**:
- `empty_windows`: windows with 0 precursors (wasted scan time)
- `overloaded_windows`: windows with >2x mean precursors (chimeric risk)
- `width_violations`: windows exceeding min/max constraints
- `high_cv_bins`: RT bins with precursor CV > 0.5 (load imbalance)

**Existing infrastructure to reuse**:
- `calculate_window_statistics_internal()` → coverage, width stats
- `calculate_precursors_per_window()` → per-window counts
- `count_precursors_in_2d_windows()` → vectorized 2D matching
- `compute_strategy_radar_metrics()` → load balance, edge safety

### Batch Comparison Export

**New function**: `export_batch_comparison()` in `R/export_methods.R`

```r
export_batch_comparison(
  windows_list,           # named list of OptimizedWindows (e.g., 5 strategies)
  validated_data,
  optimization_plan,
  output_dir,
  formats = c("thermo", "center_mass", "mz_range")
)
```

**Output structure**:
```
{output_dir}/
├── thermo/
│   ├── {strategy_A}_{mode}.csv
│   └── {strategy_B}_{mode}.csv
├── center_mass/
│   └── (same structure)
├── mz_range/
│   └── (same structure)
├── comparison.csv          ← strategy metrics side-by-side
└── evaluation_summary.csv  ← per-window quality flags for all strategies
```

**comparison.csv columns**:
```
strategy, window_mode, n_windows, mean_width_da, width_cv,
coverage_pct, load_balance_cv, edge_safety_pct, dppp_median,
empty_windows, overloaded_windows, width_violations
```

### Batch Strategy Comparison Report (PDF)

Enhanced multi-strategy comparison in PDF report:

1. **Strategy radar chart** (existing `plot_strategy_radar()`)
2. **Strategy comparison table** (existing `plot_strategy_comparison_table()`)
3. **Precursors-per-window bar chart** — NEW, per strategy, shows load distribution
4. **Width distribution violin** — NEW, per strategy, shows width variability
5. **Per-RT-bin heatmap comparison** — NEW, strategies as columns, RT bins as rows

### Shiny UI Changes (Step 3 Downloads)

```
Current:
  [Sample Name] [Condition] [CSV Method File] [PDF Report]

Updated:
  [Sample Name] [Condition]
  Format: [Thermo CSV ▼] [Center Mass ▼] [m/z Range ▼] [PDF Report]
  Batch:  [Batch Export (ZIP)] ← runs all 5 strategies, all 3 formats
```

### Implementation Order

1. max_width_da → Shiny UI (next to min_width_da)
2. export_center_mass_list() + export_mz_range_list()
3. evaluate_windows() + quality flags
4. Shiny Step 3 download buttons (3 format buttons)
5. export_batch_comparison() + ZIP handler
6. Batch comparison plots for PDF report
7. Shiny precursors-per-window visualization

---

## v0.3.1: Astral Optimization (Duty Cycle Sync + Temporal Density)

> **Detailed Astral instrument knowledge**: See [docs/astral-instrument-knowledge.md](astral-instrument-knowledge.md)
> Covers architecture, MS2 parameters, AGC/space charge, IT tradeoffs, sync tables.

### Duty Cycle Sync Constraint

For **parallel instruments** (Astral, TimsTOF), MS1 and MS2 run simultaneously:
- `cycle_time = max(MS1_time, n_windows * MS2_time)`
- If total MS2 time ≠ MS1 transient time, one analyzer idles → wasted capacity
- `calculate_duty_cycle_sync()` quantifies idle time and duty cycle %
- `calculate_sync_optimal_windows()` finds n_windows for perfect sync: `floor(MS1_time / MS2_scan_time)`
- For Astral: MS1 Orbitrap 120K = 256 ms, MS2 Astral = 5 ms → sync-optimal = 51 windows

### Precursor Temporal Density (Co-Elution Proxy)

**What it measures:** Number of identified precursors with overlapping elution
profiles within a given isolation window at any point in time.

**Survivor bias caveat:** report.parquet only contains successfully identified
precursors. Precursors that failed deconvolution due to co-isolation are absent.
Values are a **lower bound** — useful for relative comparison, not absolute.

**Algorithm:** Sweepline O(k log k) per window:
1. Filter precursors in [mz_start, mz_end] AND [rt_start, rt_end]
2. Compute elution interval: [RT.Apex - 1×FWHM, RT.Apex + 1×FWHM]
3. Create event list: +1 at start, -1 at end
4. Walk events tracking cumsum → density_max = peak, density_mean = time-weighted avg

### Sync-Optimal as Primary Constraint — Justification (2026-03-11)

**Conclusion:** Sync-optimal (`floor(MS1_transient / MS2_scan_time)`) is the correct and
sufficient primary constraint for Astral window count optimization.

**Reasoning:**
1. DPPP is automatically satisfied on Astral (typical DPPP ≈ 29 at sync-optimal 102 windows,
   target is 7.0) — DPPP is not a meaningful constraint
2. The only optimization axis AIDIA controls is window count/width/placement
3. Duty cycle is the only hardware efficiency metric responsive to window count
4. Sync-optimal is the unique maximum of duty cycle (100%, no idle analyzer)

**Out of scope (by design):**
- **Sample load**: User-controlled experimental parameter. AIDIA cannot infer or adjust for it.
  Low-input workflows (single-cell, <100 ng) may benefit from fewer, wider windows (nDIA paper:
  8 Th > 2 Th at 10 ng), but this is the user's method design responsibility.
- **Ion statistics / AGC underfilling**: Post-acquisition QC domain. Astral Zoom at 200 ng + 2 Th
  frequently fails to reach 20,000-ion AGC target (JPR 2025) — detectable only from raw files,
  not from DIA-NN report.parquet.
- **Space charge**: Hardware physics. ~10³ same-m/z ions cause MR-TOF resolution degradation
  (Stewart et al. 2024). No software-side mitigation.

**Known Astral bottleneck hierarchy (literature 2024-2025):**

| Tier | Bottleneck | AIDIA addressable? |
|------|-----------|-------------------|
| Hardware physics | nDIA: 0.5% ion beam sampling, space charge | No |
| Method design | Window count/width/placement, cycle time | **Yes (sync-optimal)** |
| Method design | Sample load → optimal window width | No (user responsibility) |
| Workflow | Sample prep throughput (>180 SPD) | No |
| Workflow | Short gradient peak capacity compression | No |
| Analysis | Glycoproteomics software gap | No |
| Analysis | Single-cell data completeness (~18%) | No |

**References:**
- Stewart et al. 2024, J Mass Spec — space charge in MR-TOF
- Demichev et al. 2024, Nat Biotech — nDIA, sample-load-dependent window width
- Mechtler group 2025, Nat Methods — single-cell 5,300 proteins, 18% completeness
- Schilling et al. 2023, JPR — Astral quant evaluation, Orbitrap better dynamic range
- JPR 2025 — Astral Zoom evaluation, AGC underfilling at 200 ng
- MCP 2025 — TMT ratio compression on Astral (no MS3)

### Boxcar/MAP-MS (Deferred to v0.4.0)

**Concept:** Multiple narrow MS1 windows (K segments) instead of single full-range MS1.
- Improves signal-to-noise for low-abundance precursors
- Each segment gets longer AGC fill time → better ion statistics
- Sync problem becomes K-dimensional: `cycle = K × max(MS1_transient, N_k × MS2_scan)`
- Requires new export format (MS1 segment definitions)

**Prerequisite:** Duty cycle sync (v0.3.1) must work first.

**Key decisions for v0.4.0:**
- `plan_ms1_segmentation()` function to define K segments
- Modified export format for Xcalibur with MS1 segment table
- `ms1_scans_per_cycle` field in instruments.json already has placeholder (0 for parallel)

---

## Acquisition Capacity vs Identification Yield (terminology)

When discussing how "well" an acquisition method uses the instrument, AIDIA
distinguishes two orthogonal axes. **"Efficiency" is not used as an umbrella
term** for either of these — it collides with the existing
`it_optimization$parallel_filling_efficiency` field and with ADR-0001's
definition of duty cycle as *the* hardware efficiency metric for parallel
instruments.

### Axis 1: Acquisition Capacity (time-budget utilization)

How the hardware's time budget was spent during a gradient. Does **not**
involve identification outcomes — pure timer accounting.

| Metric | Source | Already in AIDIA? |
|--------|--------|-------------------|
| Duty cycle (parallel only) | `duty_cycle_sync$duty_cycle_pct` | Yes (v0.3.1) |
| Scan-time limiting factor | `scan_time$limiting_factor` (`"transient"` / `"injection_time"`) | Yes |
| Parallel filling efficiency | `it_optimization$parallel_filling_efficiency` | Yes |

The capacity story is built from **existing fields**, not new computation.
New work here is *exposure* (UI + plot), not measurement.

### Axis 2: Identification Yield (outcome per resource)

Identified precursors per unit of acquisition resource. **Requires DIA-NN
`*.stats.tsv`** (or graceful fallback). This is the only axis introducing
new measurement.

| Metric | Definition | Source |
|--------|-----------|--------|
| Precursors per minute | `precursors_identified / gradient_length_min` | stats.tsv + gradient |
| Precursors per scan slot | `precursors_identified / total_scan_slots` | stats.tsv + capacity |

Yield is an **outcome metric, not an efficiency metric**. Reporting it as
"% efficient" is misleading (typical values 0.1–5% would look catastrophic).
Always reported with absolute units (per minute / per scan slot), never as
a normalized %.

### Composite / "Limiting factor" — derived view, not S3 field

A single `bottleneck_summary` (string + one-sentence message) is derived
on demand at print/plot time from the two axes above. It is **not** stored
as a separate S3 field — to avoid stale composite values diverging from
their underlying inputs.

The existing `scan_time$limiting_factor` keeps its narrow scope (transient
vs IT within a single MS2 scan). A higher-level bottleneck classification
(capacity-bound vs yield-bound) is a separate, derived concept.

### What "efficiency" means in AIDIA going forward

- ✅ `parallel_filling_efficiency` — IT/(transient+overhead+IT) for parallel instruments (existing)
- ✅ `duty_cycle` — parallel-instrument analyzer-pair synchronization (existing)
- ❌ "Acquisition Efficiency" as a single number — **rejected** (ambiguous)
- ❌ `id / scan_slot * 100` as "% efficiency" — **rejected** (misleading magnitude)

### Rejected: Gradient-span utilization (RT range / LC method length)

A "fraction of LC method actually populated with peptides" metric was considered
and rejected. Reason: every LC method has structurally unavoidable dead zones
at both ends — column equilibration before the first peptide elutes, and wash
/ re-equilibration after the last peptide. Reporting these as "wasted scan
slots" would penalize a correctly designed method. Inefficiency *within* the
peptide-bearing region is already captured by `evaluate_windows()$quality_flags$empty_windows`.

Additionally, `R/rt_binning.R:128` defines `rt_range <- range(precursor_data$RT.Apex)`,
so AIDIA's generated method active region is automatically clipped to the
data-driven RT span — LC dead zones are excluded by construction.

### Why AIDIA cannot measure "actual acquired scan count"

AIDIA reads DIA-NN `report.parquet` + optional `*.stats.tsv` — **never the
raw mass-spec file**. See [ADR-0004](adr/0004-result-driven-input-no-raw-file.md)
for the full rationale. Therefore the literal "acquired MS2 scan count" is not
available; only an estimate from `gradient_length_s × actual_scan_rate_hz`
based on the method AIDIA produced.

This matters because DIA scan count is not fully deterministic:
- **AGC dynamic IT**: when ion target is reached before `max_IT`, the scan
  shortens, freeing time for additional cycles
- **Lock mass scans**: periodic calibration scans displace regular MS2
- **Software retries / gradient drift**: rare but possible

For most fixed-IT DIA methods the variation is small (<5%), but it is not zero.
AIDIA-derived "scan slot count" should be reported as an **estimate**, never
as a measured value.

### Capacity KPIs (v0.4.x — to be implemented)

Four "did I use the instrument well?" KPIs, all derived from existing
`OptimizationPlan` + `OptimizedWindows` + `evaluate_windows()` fields. **No new
S3 nested struct.** A single `get_capacity_kpis(plan, windows, evaluation)`
function returns them.

| KPI | Definition | Source field |
|-----|-----------|--------------|
| Filled window ratio (%) | `1 - empty_windows / total_windows` | `evaluate_windows()$quality_flags` |
| DPPP headroom (×) | `diagnosis$current_dppp_median / target_dppp` | `OptimizationPlan$diagnosis` + `$parameters` |
| Cycle time headroom (%) | `(required - actual) / required × 100` | `OptimizationPlan` top-level |
| Window count headroom (%) | `(max_windows - n_windows) / max_windows × 100` | `$parameters` + `$window_count_per_bin` |

Interpretation:
- Filled 95% / DPPP 30× / Cycle 0% / Window 5% → cycle/window saturated, DPPP has slack → can lengthen IT or narrow windows
- Filled 60% / DPPP 2× / Cycle 40% / Window 30% → underutilized → can pack more windows or shorten cycle

**Implementation pattern**: `get_capacity_kpis(plan, windows, evaluation)` is
a **derive-only function**, never stored in an S3 object. This follows the
existing `evaluate_windows()` precedent — lazy-computed in
`build_visualization_context()` for plots and cached as a Shiny reactive.
No changes to `OptimizationPlan` / `OptimizedWindows` validators, no new S3
class. Eliminates stale-data risk by construction.

**Color system (hybrid)**: Capacity KPIs do not all share the same "higher
is better" semantics, so a single traffic-light palette is wrong. AIDIA uses:

- **Monotonic KPI** (`filled_window_ratio`): existing AIDIA traffic light —
  green ≥90%, yellow 70–90%, red <70%. Consistent with the "ValueBox target
  coloring" rule in CLAUDE.md.
- **Two-sided KPIs** (3 headroom indicators): information grades — `Bad` (red,
  infeasible), `OK` (green, healthy use), `Info` (blue, slack available
  → not a problem, capacity available for other tradeoffs).

Mapping `Info` to blue (not yellow) prevents users from misreading "DPPP
headroom 30×" on Astral as a problem. A short caption ("Info indicators
mean available capacity, not a defect") sits below the KPI strip.

Default thresholds (revisitable as real-world data accumulates):

| KPI | Bad | Warn | OK | Info |
|-----|-----|------|----|------|
| `filled_window_ratio` | <70% | 70–90% | ≥90% | — |
| `dppp_headroom_x` | <1× | — | 1–2× | ≥2× |
| `cycle_time_headroom_pct` | <0% | — | 0–15% | ≥15% |
| `window_count_headroom_pct` | — | — | 0–30% | ≥30% |

**Thresholds are tunable, not hardcoded.** `get_capacity_kpis()` accepts a
`thresholds = capacity_kpi_thresholds()` argument. The constructor returns
the table above as a named nested list; users override by passing modified
values:

```r
custom <- capacity_kpi_thresholds(
  filled_window_ratio = list(bad = 0.60, warn = 0.85),
  dppp_headroom_x     = list(bad = 1.0,  info = 3.0)
)
kpis <- get_capacity_kpis(plan, windows, evaluation, thresholds = custom)
```

The Shiny UI uses defaults in v0.4.x. As real datasets accumulate, the
defaults may be retuned by editing `capacity_kpi_thresholds()` in
`R/capacity_kpis.R`. If a future need for per-deployment customization
emerges, the thresholds list can migrate to `inst/config/` JSON (mirroring
the `instruments.json` pattern) without breaking the function signature.

**Visualization form (Shiny only — not in PDF report)**:
- Four semicircular gauges (speedometer style) with the KPI value rendered
  inside the dial. Colored arc segments mark `Bad / Warn / OK / Info`
  regions per the threshold table; a tick marker shows current position.
- Implemented as a single `ggplot` with `coord_polar()` + `facet_wrap`,
  no `ggforce` / `gridExtra` / `patchwork` dependency added.
- A one-line `bottleneck_summary` text sits above or below the gauge
  strip in Shiny, derived from the four KPI states by a small rule-based
  function (`summarize_bottleneck(kpis, thresholds)`).

**PDF report intentionally excludes the KPI dashboard.** Capacity KPIs are
an *operational/interactive* diagnostic, not a publication artifact —
AIDIA's PDF report is a collection of distributional/statistical figures
appropriate for method-design write-ups. The KPI plot has **no entry in
`PLOT_REGISTRY`**; `plot_capacity_kpis()` is called only from Shiny. This
deliberately breaks the "all plots go through the registry" convention
because the registry's purpose is PDF assembly, and these KPIs are not
part of that artifact.

**Instrument-type context (Shiny header line above gauges)**: KPIs are
universal across sequential and parallel instruments, but a one-line
header gives readers the right interpretive frame:

- Sequential (Exploris, QE, etc.): `"Sequential instrument — DPPP-bound at target {target_dppp}."`
- Parallel (Astral, Astral Zoom): `"Parallel instrument — sync {duty_cycle_pct}% ({n_actual} / {n_sync_optimal} sync-optimal). DPPP-bound metrics may show high headroom."`

Rationale: `cycle_time_headroom` is computed against DPPP-derived
`required_cycle_time` (`R/optimization_planning.R:214`), but parallel
instruments are typically sync-optimal-bound, not DPPP-bound — so large
headroom values are *expected*, not a defect. The header line provides
this context without changing the KPI set itself. Sync-first hero in
Step 2 covers method-design context; Step 3 header covers
diagnostic-time context.

### Bottleneck Summary — Rule Set

`summarize_bottleneck(kpis, thresholds)` returns a single-line English
message describing the dominant condition. Rules are evaluated in
priority order; the first matching rule wins.

| # | Condition | Message |
|---|-----------|---------|
| 1 | `dppp_headroom == Bad` (≡ `cycle_headroom == Bad`) | `"DPPP target not met — cycle too long for required peak sampling. Reduce window count or shorten transient."` |
| 2 | `filled_ratio == Bad` (<70%) | `"Many empty windows — review m/z strategy or RT binning."` |
| 3 | `filled_ratio == Warn` (70–90%) AND no other `Bad` | `"Some empty windows — consider tightening m/z strategy."` |
| 4 | `cycle_headroom == OK` AND `window_headroom == OK` AND `dppp_headroom == Info` AND `filled_ratio != OK` | `"Cycle and windows near ceiling with DPPP slack — IT or m/z width tradeoff available."` |
| 5 | `cycle_headroom == Info` AND `window_headroom == Info` | `"Underutilized — add more windows or shorten cycle."` |
| 6 | `dppp_headroom == Info (≥2×)` AND cycle/window/filled all `OK` | `"Large DPPP headroom — opportunity to lengthen IT for better ion statistics."` |
| 7 | All `OK` | `"Well balanced."` |
| 8 | (fallback) | `"See individual KPIs for details."` |

**Notes on rule design**:

- Rules #1 and the `cycle_headroom < 0%` Bad condition are mathematically
  equivalent (DPPP = 1.7 × FWHM / cycle_time → headroom signs match).
  Treated as one rule to avoid duplicate messaging.
- Message language is English only in v0.4.x (matches AIDIA's
  English-output convention per CLAUDE.md). i18n is deferred.
- Rule #4 carries the `filled_ratio != OK` clause to keep it disjoint from
  rule #6 under `first-match` priority. Concretely: `filled = NA` (eval
  failed) routes to rule #4 because an m/z tradeoff is still a valid
  recommendation when filling is unknown; `filled = OK` routes to rule #6
  because tightening m/z is unnecessary when windows are already filled.
  `filled = Bad / Warn` are absorbed earlier by rules #2 / #3, so rule #4
  in practice only fires for `filled = NA`.
- For parallel instruments, rule #6 will fire frequently when filling is
  confirmed OK because DPPP is structurally satisfied. The Step 3
  instrument-context header line ("DPPP-bound metrics may show high
  headroom") sets the expectation, so no special parallel-branch message
  is added — the rule stays uniform.
- Edge case: when `evaluate_windows()` fails, `filled_ratio = NA` and
  rules #2/#3 are skipped (NA-safe condition checks).

### Shiny Step 3 Placement

Capacity KPI dashboard lives in its **own bs4Dash box** below the existing
"Result Summary" `valueBox` row in Step 3, with explicit section labels to
separate two concerns:

```
[Result Summary]                            ← existing valueBoxes (absolute values)
  Cycle Time | DPPP | Windows               ← traffic-light coloring
  
[Acquisition Capacity Diagnostics]          ← NEW collapsible box (default OPEN)
  Header line:  instrument-type context     ← e.g. "Parallel — sync 100% …"
  4 gauges:     Filled | DPPP | Cycle | Win ← information-grade coloring
  Footer line:  bottleneck summary message  ← 1-line English actionable hint
```

- `box(title = "Acquisition Capacity Diagnostics", collapsible = TRUE, collapsed = FALSE, width = 12, ...)`
- Section labels justify the two coexisting color systems (traffic light
  for absolutes, information grades for utilization).
- Existing `summary_box_*` value boxes remain unchanged — no regression
  to current UX.

### Edge Case Handling

| Case | Trigger | Handling |
|------|---------|----------|
| `evaluate_windows()` fails | tryCatch wraps the call | `filled_ratio = NA`. Fourth gauge renders gray "N/A" segment, center text "N/A". Bottleneck rules #2/#3 skipped (NA-safe). Other three KPIs unaffected. |
| Spec-limited windows | `plan$it_optimization$is_spec_limited == TRUE` | `window_count_headroom = 0%`. Gauge color stays `OK` (hardware ceiling is normal operation, not a defect). Gauge label appends "(spec-limited)". |
| Extreme DPPP headroom | Astral commonly reports ≥30× | Gauge visual cap = 5× (≥2× is `Info` anyway, so 5× saturates the dial). Center text shows actual value (e.g. "30×"). Gauge end region labeled "≥5×". |
| Header context source | `is.null(plan$duty_cycle_sync)` → sequential | Sequential: `sprintf("Sequential instrument — DPPP-bound at target %.1f.", plan$parameters$target_dppp)`. Parallel: `sprintf("Parallel instrument — sync %d%% (%d / %d sync-optimal). DPPP-bound metrics may show high headroom.", round(plan$duty_cycle_sync$duty_cycle_pct), plan$window_count_per_bin, plan$duty_cycle_sync$n_sync_optimal)`. |
| All KPIs NA | Cascading failures | Header context still renders. All four gauges show "N/A". Bottleneck falls through to rule #8: `"See individual KPIs for details."` |

### Validation Plan

**Threshold sanity check** (Part A — `tests/manual/test_capacity_kpis_real.R`):

Datasets: `C:/Users/Odyssey/Desktop/Variable_DIA_raw/Diann_res/Batch3/`
covering 30 / 60 min gradients × Fixed / Variable windows × Greedy /
Staggered strategies × with / without empirical FZ. Used for first-pass
sanity check of default thresholds — confirm no KPI lands in absurd
states (e.g., all `Bad` when method is known healthy). Default thresholds
are revised in a follow-up commit if a clear miscalibration emerges.

**Unit tests** (`tests/testthat/test-capacity-kpis.R`): 11 cases —
4 KPI calculations, 4 classification boundary checks, 8 bottleneck rule
firing checks, NA-safe behavior, spec-limited handling, sequential vs
parallel header context.

**Shiny integration** (manual checklist): Step 3 dashboard renders,
4 gauges + header + footer present, sequential / parallel header
branches correctly, collapsible toggle works, dark mode colors intact.

Identification-yield axis (precursors per minute, etc.) is a **separate
concern** and not part of these KPIs — see "Acquisition Capacity vs
Identification Yield" above. As a consequence of [ADR-0004](adr/0004-result-driven-input-no-raw-file.md)
(no raw-file input), `*.stats.tsv` parsing is **not** added in v0.4.x —
all four capacity KPIs are computable from `report.parquet` + AIDIA's own
optimization outputs.

