# AIDIA v0.3.1 Session Summary (2026-03-10)

Astral instrument optimization: duty cycle sync, overhead calibration, export fixes.

---

## Completed Work

| Item | Status | Details |
|------|--------|---------|
| Astral MS1 = Orbitrap confirmed | Done | Literature: Stewart 2023, Thermo docs |
| Duty cycle sync implementation | Done | `calculate_duty_cycle_sync()`, `calculate_sync_optimal_windows()` |
| Sync-first window count | Done | Parallel instruments: sync-optimal is primary, DPPP is reference only |
| Astral cycle time fix | Done | `max(MS1_orbitrap, n * MS2_astral)` — 0.522s @ 240K |
| Instrument-specific overhead | Done | `ms1_overhead_ms` + `ms2_overhead_ms` per instrument in JSON |
| Precursor temporal density | Done | Sweepline algorithm with survivor bias caveat |
| CSV export format fix | Done | Thermo 8-col, Center Mass 2-col, m/z Range 1-col |
| PDF generation error fix | Done | `calculate_satisfaction` -> `dppp_satisfaction_pct()` |
| Astral domain knowledge | Done | `docs/astral-instrument-knowledge.md` |
| All tests passing | Done | 226 unit + 5 Astral sync manual tests |

---

## Key Design Decisions

### 1. Sync-First for Parallel Instruments

Astral's DPPP is never a bottleneck (DPPP ~ 29 at sync-optimal vs target 7.0). The real optimization target is **duty cycle sync** — matching MS1 and MS2 analyzer utilization.

```
sync-optimal = floor(MS1_transient / MS2_scan_time)
  240K + 3ms IT: floor(512 / 5.0) = 102 windows → 99.6% duty cycle
  240K + 6ms IT: floor(512 / 8.0) = 64 windows  → 100% duty cycle
```

For sequential instruments (Exploris, Q Exactive), DPPP remains the primary constraint.

### 2. Overhead: JSON-Based Instead of Heuristic

Replaced the `calculate_scan_overhead()` 20% heuristic with fixed per-instrument values in `instruments.json`. The heuristic gave incorrect results at high resolutions (102.4ms at 240K vs actual ~10ms).

`calculate_scan_overhead()` is kept as a last-resort fallback when no JSON config is available.

### 3. Astral Architecture in AIDIA

- `ms1_analyzer_type: "orbitrap"` and `default_ms1_resolution: 240000` added to JSON
- `optimization_planning.R`: parallel branch computes MS1 from Orbitrap transient + overhead
- `instrument_utils.R`: `calculate_cycle_time_from_experiment()` uses JSON overhead for both MS1 and MS2
- Shiny: MS1 resolution selector shown for Astral instruments

---

## Modified Files

| File | Changes |
|------|---------|
| `inst/config/instruments.json` | Added `ms1_overhead_ms`, `ms2_overhead_ms`, `ms1_analyzer_type`, `default_ms1_resolution`, width recommendations; removed `astral_sensitive` |
| `R/instrument_utils.R` | MS1 overhead from JSON (`base_config$ms1_overhead_ms`); Astral MS1 uses Orbitrap transient; `calculate_ms2_scan_time()` accepts `ms2_overhead_ms` |
| `R/optimization_planning.R` | Parallel branch: MS1 = transient + JSON overhead; sync-first window count for Astral |
| `R/export_plots.R` | Fixed `calculate_satisfaction` error at line 520 |
| `R/export_methods.R` | 3 export formats matching Python method_generator.py |
| `R/precursor_matching.R` | `calculate_precursor_temporal_density()` sweepline algorithm |
| `R/window_evaluation.R` | Extended with temporal density metrics |
| `R/plot_evaluation.R` | `plot_temporal_density()` with survivor bias caveat |
| `inst/shiny_app/ui_step1_data.R` | Astral MS1 resolution selector |
| `inst/shiny_app/server_instrument.R` | Duty cycle sync display, Astral config updates |
| `tests/manual/test_astral_sync.R` | 5 physics-based tests with JSON overhead |
| `tests/testthat/test-duty-cycle-sync.R` | Unit tests for sync functions |
| `tests/testthat/test-temporal-density.R` | Unit tests for temporal density |
| `docs/astral-instrument-knowledge.md` | Comprehensive Astral domain knowledge |

---

## Current Overhead Values (Literature Estimates)

| Instrument | ms1_overhead_ms | ms2_overhead_ms | Source |
|------------|:---:|:---:|--------|
| Astral / Astral Zoom | 10.0 | 1.0–2.0 | Literature estimate (Orbitrap C-trap/IRM) |
| Q Exactive / Q Exactive HF-X | 12.0 | 12.0 | Literature estimate |
| Exploris 480 | 10.0 | 10.0 | Literature estimate |
| Eclipse / Fusion Lumos | 10.0 | 10.0 | Literature estimate |
| timsTOF series | — | 0.5–1.0 | Literature estimate |
| SCIEX ZenoTOF 7600 | — | 3.0 | Literature estimate |
| Waters SYNAPT XS | — | 5.0 | Literature estimate |

---

## Pending: Overhead Calibration from Raw Files

### Objective

Replace literature-estimated overhead values with empirically measured values from Thermo raw files.

### Method

```
overhead_ms = measured_scan_interval - max(transient_time, actual_injection_time)
```

Where:
- **measured_scan_interval**: Time between consecutive scans (`diff(scan_RT)`)
- **transient_time**: Resolution-dependent (from `get_transient_time()` lookup table)
- **actual_injection_time**: Recorded in raw file trailer (`Ion Injection Time (ms)`)

### Extraction via rawrr (R)

```r
library(rawrr)

# 1. Extract scan index (RT timestamps)
index <- readIndex("file.raw")
scan_times_ms <- index$scanTime * 60 * 1000  # min -> ms

# 2. Extract actual injection times from trailer
trailers <- readTrailer("file.raw")
actual_it <- trailers[["Ion Injection Time (ms)"]]

# 3. Identify scan types
ms1_scans <- which(index$MSOrder == "Ms")
ms2_scans <- which(index$MSOrder == "Ms2")

# 4. MS2 overhead: consecutive MS2 within same cycle
ms2_intervals <- diff(scan_times_ms[ms2_scans])
ms2_within_cycle <- ms2_intervals[ms2_intervals < 100]  # same-cycle threshold

# Known transient for the resolution used:
ms2_transient <- get_transient_time(resolution, "orbitrap")  # or 0 for TOF
ms2_overhead <- median(ms2_within_cycle) - max(ms2_transient, median(actual_it[ms2_scans]))

# 5. MS1 overhead: MS1 scan duration
#    (interval from MS1 start to first MS2 of same cycle)
ms1_to_ms2 <- scan_times_ms[ms2_scans[1]] - scan_times_ms[ms1_scans[1]]
ms1_transient <- get_transient_time(ms1_resolution, "orbitrap")
ms1_overhead <- ms1_to_ms2 - max(ms1_transient, actual_it[ms1_scans[1]])
```

### Calibration Checklist

- [ ] Acquire raw files from representative DIA runs (per instrument)
- [ ] Extract scan intervals and injection times via rawrr
- [ ] Calculate MS1 overhead: `MS1_interval - max(MS1_transient, MS1_IT)`
- [ ] Calculate MS2 overhead: `median(MS2_intervals_within_cycle) - max(MS2_transient, MS2_IT)`
- [ ] Compare with current JSON values
- [ ] Update `instruments.json` with empirical values
- [ ] Re-run `devtools::test()` and `test_astral_sync.R`
- [ ] Record instrument model, firmware version, and acquisition method used

### Important Notes

- Overhead is hardware-fixed per instrument model (C-trap fill/extract, IRM timing, digitizer sync)
- NOT affected by: resolution, IT, AGC settings, sample complexity
- CAN vary by: firmware version, instrument calibration state (minor)
- For Astral: MS1 overhead = Orbitrap-side only; MS2 overhead = MR-TOF transfer timing
- Recommend measuring from DIA runs (not DDA) for representative MS2 intervals

---

## Remaining Before v0.3.1 Release

- [ ] Overhead calibration from raw files (user-driven)
- [ ] Version bump after verification
- [ ] Commit and Notion log
