# AIDIA - Adaptive Isolation for DIA

<div align="center">

**Your Adaptive Aid for DIA Optimization**

[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](https://github.com/KBSI/aidia)
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

- 🎯 **5 Optimization Strategies**: Greedy, KDE, Quantile, Coverage, Outlier (with optional SG smoothing)
- 📊 **3 Window Modes**: Variable (Density), Fixed, Staggered
- 🔧 **Multi-Instrument Support**: Astral, Exploris, Orbitrap, TimsTOF
- 📁 **22-Column Thermo Format**: Direct import to Xcalibur
- 🧬 **Technical Replicate Handling**: Consensus-based with geometric CV filtering
- ⚡ **High Performance**: Vectorized operations, 50-100× faster matching
- 📈 **DPPP-Based Planning**: Quant mode (7.0) or ID mode (1.5)
- 📉 **Savitzky-Golay Smoothing**: Smooth m/z boundaries across RT bins

---

## 🚀 Quick Start

### Installation

```r
# Install from GitHub
# install.packages("remotes")
remotes::install_github("KBSI/aidia")
```

### Basic Usage

```r
library(aidia)

# Run pipeline
validated <- create_validated_dataset("data/report.parquet")
plan <- plan_optimization(validated, current_cycle_time = 3.5,
                          instrument_preset = "astral", target_dppp = 7.0)
windows <- optimize_windows(validated, plan, rt_bin_width_min = 5,
                            mz_strategy = "greedy", window_mode = "variable")

# Export method file
export_windows_to_csv(windows, "output/method.csv", validated, plan)

# Generate visualizations
viz <- generate_visualizations(validated, plan, windows, output_dir = "output/")
```

### Shiny Web Interface

```r
# Launch interactive UI
aidia::run_aidia_app()
```

---

## 🎯 Optimization Strategies

| Strategy | Algorithm | SG Smoothing | Use Case |
|----------|-----------|--------------|----------|
| **Greedy** | MacCoss Lab sliding | ✅ Optional | Recommended, maximize coverage |
| **KDE** | Kernel Density Estimation | ❌ N/A | Peak-based optimization |
| **Quantile** | P5-P95 percentiles | ✅ Optional | Fast, robust |
| **Coverage** | Min range for target % | ❌ N/A | Discovery, comprehensive |
| **Outlier** | Mean ± 3σ | ✅ Optional | High-throughput, inclusive |

> **SG Smoothing**: Savitzky-Golay smoothing prevents abrupt m/z boundary jumps across RT bins.

### Window Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **Variable** | Density-based width (Dense=Narrow) | Default, adaptive |
| **Fixed** | Equal width windows | Simple, consistent |
| **Staggered** | Offset in alternating RT bins | Reduced edge effects |

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
│    24 plots + PDF report                               │
└─────────────────────────────────────────────────────────┘
```

---

## 📁 Output Files

### Method Files (22-Column Thermo Format)

Compatible with **Thermo Xcalibur**:
- Compound, Formula, Adduct
- m/z, z (charge state)
- t start/stop (RT windows)
- Isolation Window, AGC Target
- Start/End m/z boundaries
- Window_ID, RT_Segment_ID
- Recommended_Cycle_Time_Sec

---

## 📚 Documentation

- **[USAGE_GUIDE.md](docs/USAGE_GUIDE.md)**: Comprehensive user guide
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)**: System architecture
- **[CLAUDE.md](CLAUDE.md)**: Developer guide
- **[GEOMETRIC_CV_GUIDE.md](docs/GEOMETRIC_CV_GUIDE.md)**: CV calculation

---

## ⚡ Performance

| Operation | Time | Output |
|-----------|------|--------|
| Stage 1: Validation | ~2 sec | ValidatedData |
| Stage 2: Planning | <1 sec | OptimizationPlan |
| Stage 3: Optimization (×6) | ~20 sec | 6 window sets |
| Stage 4: Visualization | ~25 sec | 24 plots + PDF |
| **Total** | **~50 sec** | Complete analysis |

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

1. Check [USAGE_GUIDE.md](docs/USAGE_GUIDE.md)
2. Review [ARCHITECTURE.md](docs/ARCHITECTURE.md)
3. See [CLAUDE.md](CLAUDE.md) for development guide

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

**Version 0.1.0** | KBSI Proteomics

</div>
