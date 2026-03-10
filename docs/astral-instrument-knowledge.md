# Astral Instrument Domain Knowledge

Detailed technical knowledge for the Thermo Orbitrap Astral / Astral Zoom mass spectrometer,
relevant to DIA window optimization in AIDIA.

---

## 1. Instrument Architecture

The Orbitrap Astral is a **triple-analyzer hybrid** instrument:

| Analyzer | Role | Resolution | Speed |
|----------|------|-----------|-------|
| Quadrupole | Precursor isolation | N/A | N/A |
| Orbitrap | MS1 full scans | 7,500–480,000 (user-selectable) | Resolution-dependent |
| Astral MR-TOF | MS2 fragment scans | ~80,000–100,000 (fixed) | Up to 200 Hz |

**Key point:** MS1 is ALWAYS on the Orbitrap. The Astral MR-TOF is exclusively for MS2.

### Parallel Acquisition

MS1 and MS2 run simultaneously:
```
MS1 (Orbitrap):  ─────────── transient ───────────
MS2 (Astral):    ─ W1 ─ W2 ─ W3 ─ ... ─ Wn ─────
cycle_time = max(MS1_time, n_windows × MS2_scan_time)
```

Five separate ion packets are handled simultaneously through synchronized ion transfer.

### References
- Stewart et al. (2023) Anal. Chem. DOI:10.1021/acs.analchem.3c02856
- Thermo Fisher Orbitrap Astral product page

---

## 2. MS1 Parameters (Orbitrap)

### Resolution and Transient Time

Standard Orbitrap resolution ladder applies to MS1:

| Resolution | Transient (ms) | Scan Rate |
|-----------|----------------|-----------|
| 60,000 | 128 | ~5 Hz |
| 120,000 | 256 | ~3 Hz |
| **240,000** | **512** | **~2 Hz** |
| 480,000 | 1,024 | ~0.7 Hz |

**240,000 is the standard MS1 resolution** in published DIA methods
(Orsburn 2023, Stewart 2023, Inflection Point 2024).

### Typical MS1 DIA Settings
- Resolution: 240,000
- m/z range: 375–985 or 380–980
- Max injection time: 50 ms
- AGC target: Standard (100%)

---

## 3. MS2 Parameters (Astral MR-TOF)

### Adjustable Parameters

| Parameter | Range | Typical DIA | Notes |
|-----------|-------|-------------|-------|
| **Injection time** | 0.03–40 ms | 3–6 ms | Primary sensitivity control |
| **AGC target** | Variable | 100–500% | 100% ≈ 10,000 charges for MS2 |
| **Isolation window width** | 2–20 Th | 2–4 Th | Narrower = better selectivity |
| **Collision energy** | Variable | 27% HCD | Standard for DIA |

### Non-Adjustable Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Resolution** | ~80,000–100,000 | Fixed by MR-TOF geometry |
| **Mass range** | Fixed | Determined by analyzer design |

### Resolution Note
Unlike Orbitrap, MR-TOF resolution is determined by physical flight path length.
Users cannot select resolution. Actual resolution varies slightly with ion load
(~100K at low load → ~90K at high load due to space charge).

---

## 4. Injection Time vs Performance Tradeoff

### Published Benchmark Data (Orsburn et al. 2023, J. Proteome Res.)

| Config | Window | IT | Speed | Peptide IDs | Quant CV |
|--------|--------|-----|-------|-------------|----------|
| High-throughput | 2 Th | 3.5 ms | 187 Hz | **Highest** | High (low precision) |
| Balanced | 4 Th | 10 ms | 90 Hz | Medium | Medium |
| Sensitivity | 4 Th | 20 ms | 50 Hz | Lower | **Lowest** (best precision) |
| Dynamic DIA | 2 Th | 10 ms | Variable | High | Good |

**Key insight:** Speed and quantitative precision are inversely related.
More IDs ≠ better quantification. Choose based on experimental goal:
- **Discovery/ID mode**: Short IT (3 ms), many narrow windows
- **Quantification mode**: Longer IT (6–10 ms), fewer windows, better precision

### IT and Scan Rate Relationship
- Below 2.5 ms: IT has no impact on repetition rate (>200 Hz maintained)
- Above 2.5 ms: Scan rate decreases inversely with IT
- Scan time ≈ IT + overhead (1–2 ms for Astral)

---

## 5. AGC and Space Charge Effects

### The Problem: "Crowd Control" (Stewart et al. 2024, J. Mass Spectrom.)

Space charge is "the Achilles' heel of all high-resolution ion optical devices."

### Two Critical Ion Count Thresholds

| Threshold | Effect | Symptom |
|-----------|--------|---------|
| **~10³ ions** (same m/z) | Resonant in-flight interaction | Resolving power ↓, mass shift ↑ |
| **~10⁴–10⁵ ions** (total) | Ion packet expansion before extraction | Peak coalescence, transmission loss |

### Specific Symptoms at High Ion Load
1. **Mass shift**: Ions repel → slow down → mass measured slightly higher
2. **Resolution loss**: 100K → 90K level degradation
3. **Peak coalescence**: Adjacent m/z peaks merge
4. **Transmission loss**: Ions lost during extraction

### Practical AGC Guidelines

| AGC Level | Suitability | Risk |
|-----------|-------------|------|
| 100% (10K charges) | Standard, safe | Minimal space charge |
| 200% | Good for sensitivity | Low risk |
| 500% | Max sensitivity setting | Moderate space charge risk |
| >500% | Not recommended | Significant mass accuracy loss |

**Rule of thumb**: For DIA with narrow windows (2–4 Th), AGC 100–200% is optimal.
Wider windows (>10 Th) accumulate more co-isolated ions, increasing space charge risk.

### AGC Mechanism on Astral
- "Fluxscans" (rapid pre-scans) measure incoming ion current
- AGC adjusts injection time to reach target ion count
- Actual IT = min(max_IT, time_to_reach_AGC_target)
- If ions are abundant: IT shortened well below max_IT
- If ions are scarce: IT reaches max_IT (sensitivity-limited)

---

## 6. Duty Cycle Sync for Astral DIA

### Sync-Optimal Window Count

For MS1 at 240K (512 ms transient), the sync-optimal window count depends on MS2 scan time:

| MS2 IT | Scan time | Sync-optimal N | Idle |
|--------|-----------|----------------|------|
| 2 ms | ~4 ms | 128 | 0 ms |
| 3 ms | ~5 ms | 102 | 2 ms |
| 4 ms | ~6 ms | 85 | 2 ms |
| 6 ms | ~8 ms | 64 | 0 ms |
| 10 ms | ~12 ms | 42 | 8 ms |
| 20 ms | ~22 ms | 23 | 6 ms |

### Duty Cycle
At 3 ms IT and 200 Hz, reported maximum duty cycle is ~60%.
AIDIA calculates duty cycle as: `min(MS1_time, total_MS2) / max(MS1_time, total_MS2) × 100%`

### MS1 Resolution Impact on Sync
- 120K (256 ms): sync-optimal ~51 windows at 5 ms scan time
- 240K (512 ms): sync-optimal ~102 windows at 5 ms scan time
- Lower MS1 resolution = shorter transient = fewer sync-optimal windows

---

## 7. Window Width Recommendations

### Literature-Based Ranges for Astral DIA

| Source | Window Width | IT | Context |
|--------|-------------|-----|---------|
| Stewart 2023 | 2 Th | 3 ms | High-throughput |
| Orsburn 2023 | 2–4 Th | 3.5–20 ms | Benchmarking |
| Inflection Point 2024 | 2–4 Th | 3–6 ms | Standard DIA |
| Dynamic DIA | 2 Th variable | 10 ms | Adaptive widths |

**AIDIA defaults**: min 2 Da, max 50 Da (generous upper bound for non-standard applications)

---

## 8. Astral Zoom Variant

- Same architecture (Orbitrap MS1 + MR-TOF MS2)
- "Zoom" = multi-pass MR-TOF for doubled resolution
- Overhead per scan is lower (1.0 ms vs 2.0 ms for standard Astral)
- Same MS1 resolution options and parallel acquisition model

### Reference
- PMC12154736 (2025): Evaluation of prototype Orbitrap Astral Zoom

---

## AIDIA Implementation Notes

### Currently Implemented (v0.3.1)
- `default_ms1_resolution: 240000` in instruments.json for both Astral entries
- `ms1_analyzer_type: "orbitrap"` field to flag Orbitrap MS1
- MS1 resolution selector in Shiny UI for Astral (60K–480K, default 240K)
- Duty cycle sync display using Orbitrap transient
- Temporal density (co-elution proxy) with survivor bias caveat

### Future Considerations
- AGC target input in Shiny (currently not exposed — IT is the proxy)
- Dynamic DIA support (variable window width within RT bin)
- Space charge warning when AGC × window_width exceeds threshold
- Quant vs ID mode selector affecting default IT/window width recommendations
