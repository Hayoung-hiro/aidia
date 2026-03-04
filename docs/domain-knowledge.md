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
