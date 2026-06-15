# AIDIA - Adaptive Isolation for DIA

<div align="center">

<img src="man/figures/logo.jpg" alt="AIDIA logo" height="150"/>

**Your Adaptive Aid for DIA Optimization**

[![Version](https://img.shields.io/badge/version-0.4.0-blue.svg)](https://github.com/Hayoung-hiro/aidia)
[![R](https://img.shields.io/badge/R-%3E%3D%204.0.0-brightgreen.svg)](https://www.r-project.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

*RT-dependent isolation window optimization for Data-Independent Acquisition mass spectrometry*

</div>

---

## What is AIDIA?

**AIDIA** = **A**daptive **I**solation for **DIA**

Also: "Your **Aid** for DIA optimization"

AIDIA aids researchers in optimizing DIA isolation windows through intelligent, RT-dependent optimization strategies specifically designed for Thermo Orbitrap instruments.

---

## ✨ Key Features

- 🎯 **5 Optimization Strategies**: Greedy, KDE, Quantile, Coverage, Outlier (S3-dispatched; add a new strategy with one constructor + one method)
- 📊 **3 Window Modes**: Density (variable), Fixed, Staggered
- 🔧 **Verified Instruments**: Astral, Exploris, Q Exactive, Eclipse, Fusion Lumos (Thermo Orbitrap)
- 📁 **3 Method Export Formats**: Thermo 8-column CSV, Center Mass list, m/z Range list
- 📐 **Publication-Quality Figure Export**: 6 journal presets (JPR, MCP, Anal Chem, Nature Methods, Proteomics, JASMS) with column-width and font sizing, multi-panel assembly via patchwork
- 🧬 **Technical Replicate Handling**: Consensus-based with geometric CV filtering
- ⚡ **Duty Cycle Sync**: Sync-optimal window count for parallel instruments (Astral)
- 📈 **DPPP-Based Planning**: Quant mode (7.0) or ID mode (1.5)
- 📉 **Boundary Smoothing**: Whittaker-Henderson (default) with optional Savitzky-Golay
- 🔬 **Bootstrap CI**: Boundary uncertainty estimation via stratified resampling
- 🧭 **Baseline Comparisons**: Optimized vs equal-width baseline overlay in load balance, window coverage, and temporal density plots
- 📑 **Structured PDF Report**: 3-section + appendices layout with active-strategy highlighting in cross-strategy comparison plots
- ⚡ **Quick Preview Template**: `report_template = "minimal"` generates 7 essential plots in ~12 sec (~70% faster than full report) for rapid parameter iteration

---

## 🚀 Quick Start

### Installation

```r
# Install from GitHub
# install.packages("remotes")
remotes::install_github("Hayoung-hiro/aidia")
```

### Basic Usage

```r
library(aidia)

# Run pipeline
validated <- create_validated_dataset("data/report.parquet")
plan <- plan_optimization(validated, current_cycle_time = 3.5,
                          instrument_preset = "astral", target_dppp = 7.0)

# v0.4.1+: pass a typed strategy_config (flat `mz_strategy = "..."` params
# still work but are deprecated and will be removed in v0.6.0).
windows <- optimize_windows(validated, plan,
                            strategy_config = greedy_config(),
                            rt_bin_width_min = 5,
                            window_mode = "density")

# Export method file (Thermo Xcalibur 8-column CSV)
export_windows_to_csv(windows, "output/method.csv", validated)

# Full report (44 plots + multi-page PDF, default)
viz <- generate_visualizations(validated, plan, windows, output_dir = "output/")

# Quick preview (7 essential plots, ~70% faster — useful during parameter tuning)
viz_quick <- generate_visualizations(validated, plan, windows,
                                      output_dir = "output/",
                                      report_template = "minimal")

# Export selected plots for manuscript submission (JPR single column, PDF)
export_publication_figures(
  viz$plots,
  selected = c("s1_01_density_heatmap", "s2_01_impact_summary",
               "s2_04_load_balance",   "s3_02_strategy_ridge"),
  output_dir = "output/figures/",
  journal = "jpr",
  column = "single",
  format = "pdf"
)
```

### Shiny Web Interface

```r
# Launch interactive UI
aidia::run_aidia_app()
```

Step 3 ("Results") exposes a **"PDF scope"** radio next to the download button:

- **Full report (all plots)** — default, ~42 sec for 5 strategies
- **Quick summary (essential, faster)** — 7 plots, ~12 sec for rapid iteration

---

## 🎯 Optimization Strategies

| Strategy | Algorithm | Smoothing | Use Case |
|----------|-----------|-----------|----------|
| **Greedy** | MacCoss Lab sliding | ✅ WH (default ON) | Recommended, maximize coverage |
| **KDE** | Kernel Density Estimation | ❌ N/A | Peak-based optimization |
| **Quantile** | P5-P95 percentiles | ✅ WH (default ON) | Fast, robust |
| **Coverage** | Min range for target % | ❌ N/A | Discovery, comprehensive |
| **Outlier** | Mean ± 3σ | ✅ WH (default ON) | High-throughput, inclusive |

> **Boundary Smoothing**: Whittaker-Henderson (WH) smoothing prevents abrupt m/z boundary jumps across RT bins. Savitzky-Golay (SG) available as an alternative.

### Window Modes

| Mode (`window_mode`) | Description | Use Case |
|------|-------------|----------|
| **`"density"`** | Variable width based on precursor density (dense regions = narrower) | Default, adaptive |
| **`"fixed"`** | Equal width windows across m/z range | Simple, consistent |
| **`"staggered"`** | Alternating offset between odd/even RT bins | Reduced boundary effects |

---

## 🔧 Supported Instruments

### ✅ Verified (Thermo Orbitrap)

| Instrument | Type | Acquisition | Scan Rate |
|------------|------|-------------|-----------|
| **Astral / Astral Zoom** | Orbitrap | Parallel | 200-270 Hz |
| **Q Exactive / HF-X** | Orbitrap | Sequential | 12-40 Hz |
| **Exploris 480** | Orbitrap | Sequential | 40 Hz |
| **Eclipse Tribrid** | Orbitrap | Sequential | 40 Hz |
| **Fusion Lumos** | Orbitrap | Sequential | 20 Hz |

### 🔜 Planned (Not Yet Verified)

| Instrument | Type | Status |
|------------|------|--------|
| Bruker TimsTOF | PASEF | Coming soon |
| SCIEX ZenoTOF 7600 | TOF | Coming soon |
| Waters SYNAPT | IMS-TOF | Coming soon |

---

## 📊 DPPP Targets

**DPPP Formula**: `(1.7 × FWHM) / cycle_time`

| Target DPPP | Mode | Purpose |
|-------------|------|---------|
| **7.0** | Quant | Quantification accuracy (recommended) |
| **4.0** | Balanced | Compromise |
| **1.5** | ID | Maximum identification |

---

## 🛠️ 4-Stage Pipeline

```
┌─────────────────────────────────────────────────────────┐
│  Stage 1: Data Validation                              │
│    Input: DIA-NN parquet/TSV → ValidatedData           │
├─────────────────────────────────────────────────────────┤
│  Stage 2: Optimization Planning                        │
│    DPPP diagnosis → OptimizationPlan                   │
├─────────────────────────────────────────────────────────┤
│  Stage 3: Window Optimization + Export                 │
│    5 strategies × 3 modes → Method CSV files           │
├─────────────────────────────────────────────────────────┤
│  Stage 4: Visualization                                │
│    30+ plots + multi-page PDF report                   │
└─────────────────────────────────────────────────────────┘
```

---

## 📁 Output Files

### Method Files (Stage 3)

| Format | Function | Use |
|--------|----------|-----|
| **Thermo 8-column CSV** | `export_windows_to_csv()` | Direct import into Xcalibur (Compound, Formula, Adduct, m/z, z, t start (min), t stop (min), Isolation Window (m/z)); adjacent segments tile contiguously (zero gap/overlap), Adduct = `(no adduct)`. Optional `fill_void = TRUE` extends the schedule to the full run length to also close the leading/trailing void |
| **Center Mass list** | `export_center_mass_list()` | Plain m/z centroid list per RT bin |
| **m/z Range list** | `export_mz_range_list()` | Boundary-pair list per RT bin |
| **Batch comparison ZIP** | `export_batch_comparison()` | All 5 strategies × 3 formats + comparison.csv |

### Visualization Outputs (Stage 4)

- **Multi-page PDF** report (3 sections + appendices, journal-ready narrative)
- 44 (full template) or 7 (minimal template) ggplot/grob objects exposed via `viz$plots` (key naming: `s{section}_{order}_{name}` and `app_{appendix}_{name}`)
- Optional individual PNGs per plot
- **Registry-driven**: see `PLOT_REGISTRY` for the catalogue; add a new plot by inserting one list entry instead of editing the orchestrator

### Publication Figures

`export_publication_figures()` re-renders any subset of plots at journal-specific dimensions and font sizing:

| Journal | Single | 1.5 col | Double |
|---------|:--:|:--:|:--:|
| JPR / MCP / Proteomics | 85 mm | 114 mm | 170 mm |
| Anal Chem / JASMS | 84 mm | 114 mm | 174 mm |
| Nature Methods | 89 mm | 120 mm | 183 mm |

Output formats: PDF (cairo), SVG, TIFF (LZW), PNG @ 600 DPI. Multi-panel assembly with A/B/C tagging via `patchwork` (Suggests).

---

## 📚 Documentation

- **[CLAUDE.md](CLAUDE.md)**: Developer guide (architecture, API, pipeline details)
- **[CONTRIBUTING.md](CONTRIBUTING.md)**: Code style and contribution guidelines
- **[NEWS.md](NEWS.md)**: Release notes and version history

---

## ⚡ Performance

| Operation | Time | Output |
|-----------|------|--------|
| Stage 1: Validation | ~2 sec | ValidatedData |
| Stage 2: Planning | <1 sec | OptimizationPlan |
| Stage 3: Optimization (×6) | ~20 sec | 6 window sets |
| Stage 4: Visualization (`"full"`) | ~25 sec | 44 plots + multi-page PDF |
| Stage 4: Visualization (`"minimal"`) | ~12 sec | 7 essential plots + short PDF |
| **Total (full)** | **~50 sec** | Complete analysis |
| **Total (minimal)** | **~35 sec** | Quick preview |

*Benchmark: 90min gradient, 27K precursors*

---

## 🔬 Scientific Background

### DPPP Methodology
- Doellinger et al. (2020, 2023): DPPP optimization for DIA

### Greedy Algorithm
- MacCoss Lab: dynamicDIA approach with Savitzky-Golay smoothing

### RT-Dependent Optimization
- **LOCAL strategies**: Bin-specific (Quantile, Coverage, Outlier)
- **GLOBAL strategies**: Continuous function (Greedy, KDE)

---

## 🤝 Contributing

1. See [CLAUDE.md](CLAUDE.md) for architecture and development guide
2. Review [CONTRIBUTING.md](CONTRIBUTING.md) for code style guidelines
3. Open an issue for discussion

---

## 📜 License

MIT License - See [LICENSE](LICENSE)

---

## 🙏 Acknowledgments

- **DPPP Methodology**: Doellinger et al. (2020, 2023)
- **DIA-NN**: Demichev et al. (2020)
- **Greedy Algorithm**: MacCoss Lab (dynamicDIA)
- **Savitzky-Golay**: Savitzky & Golay (1964)

---

<div align="center">

**AIDIA** - Adaptive Isolation for DIA

*Aiding your DIA experiments*

**Version 0.4.0**

</div>
