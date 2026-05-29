# DPPP: Definition, Units, and Instrument-Dependent Operating Points

Authoritative domain note for how AIDIA defines and targets **DPPP (Data Points Per
Peak)**. This consolidates the literature review behind the defaults in
`R/dppp.R` (`PEAK_WIDTH_FACTOR`, `calculate_dppp`) and the parallel-instrument
handling in `R/optimization_planning.R` ("Step 5b: Duty Cycle Sync").

> Code already carries the short version of this note in `R/dppp.R` (file-header
> glossary + `PEAK_WIDTH_FACTOR` roxygen). This file is the long-form reference with
> citations.

---

## 1. Units — the single most important distinction

Two quantities are routinely confused because the names differ by one letter:

| Term | Meaning | Used by |
|------|---------|---------|
| **DPPP** (AIDIA) | data points across the **whole peak**, where peak width = **1.7 × FWHM** (= 4σ for a Gaussian, ~95% of peak area) | AIDIA everywhere (`calculate_dppp`, `target_dppp`, plots, CSV) |
| **PPP-FWHM** (`ppp_fwhm`) | data points within the **FWHM only** | DIA-NN, much of the literature |

**Conversion:**

```
DPPP (whole-peak) = 1.7 × ppp_fwhm        (so ppp_fwhm = DPPP / 1.7)
```

| DPPP (AIDIA) | ≈ ppp_fwhm |
|-------------:|-----------:|
| 5.1 | 3.0 |
| 6.0 | 3.5 |
| 7.0 (quant default) | ~4.1 |
| 10.0 | ~5.9 |

**Rule:** when a value is FWHM-based, name it `ppp_fwhm` explicitly — never a bare
"PPP" or "DPPP". Most "is it 7 or 10?" disagreements are just this unit mismatch.

---

## 2. Operating points are instrument- AND goal-dependent

There is **no single universal number**. The right target depends on the analyzer
and on whether you optimize for IDs or quantitative accuracy.

| Context | Recommended | In AIDIA DPPP | Notes |
|---------|------------:|--------------:|-------|
| "Sufficient" floor (good precision, ID-friendly) | ~3–3.5 ppp_fwhm | ~5–6 DPPP | DIA-NN guidance; Zeng & Bateman (7 whole-peak pts → <1% peak-area error) |
| **AIDIA default (quant)** | ~4.1 ppp_fwhm | **7.0 DPPP** | ID-friendly balance for sequential Orbitrap |
| Orbitrap, MAX quant accuracy | ~6 ppp_fwhm | ~10 DPPP | Best quant metrics but **~20% fewer IDs** (CQE preprint, Exploris 480) |
| Fast scanners (timsTOF; likely Astral) | ~3.4–4.0 ppp_fwhm (natural) | ~6–7 DPPP | Forcing ≥6 ppp_fwhm **degrades both IDs and quant efficiency** (CQE) |
| Skyline trapezoidal workflows | ≥~10-ish | higher | Different quant engine — NOT required for DIA-NN |

**Why instruments differ:** Orbitrap DIA (fewer, wider windows; slower scans) benefits
from more points per precursor. Fast scanners (timsTOF PASEF; Astral MR-TOF) already
sample densely and gain little from forcing high PPP; over-filtering throws away IDs.

---

## 3. Astral (and other parallel instruments): DPPP does NOT drive the result

Astral scans so fast that the DPPP target is essentially always satisfied
(`cycle_time << required`). AIDIA therefore optimizes parallel instruments
(Astral, timsTOF) for **duty-cycle SYNC**, not DPPP:

- Window count is set by `calculate_sync_optimal_windows()` (fill MS1 dead-time with MS2).
- DPPP is only **verified** as an (easily-met) constraint; it does not set the count.
- See `plan_optimization()` → "Step 5b: Duty Cycle Sync" (runs when
  `cycle_calculation == "parallel"`).

**Practical guidance:** for Astral, tune methods via **duty cycle**, not DPPP.
`target_dppp` is non-binding there by design.

### Open question (worth confirming experimentally / via further review)
The CQE study below covered **Exploris 480 (Orbitrap) and timsTOF only — not Astral**.
Astral is a fast MR-TOF, so it most likely patterns with timsTOF ("don't force high
PPP"), which is consistent with AIDIA's sync-first choice — but this is inference, not
a measured result for Astral specifically.

---

## 4. References (verified via PubMed unless noted)

- **Zeng W, Bateman KP.** Quantitative LC-MS/MS. 1. Impact of Points across a Peak on
  the Accuracy and Precision of Peak Area Measurements. *J Am Soc Mass Spectrom*
  2023;34(6):1136–1144. doi:10.1021/jasms.3c00077 — 7 whole-peak points → peak area
  within ~1% (Trapezoidal/Riemann; 0.6% Simpson).
- **Pino LK, Just SC, MacCoss MJ, Searle BC.** Acquiring and Analyzing Data Independent
  Acquisition Proteomics Experiments without Spectrum Libraries. *Mol Cell Proteomics*
  2020;19(7):1088–1103. doi:10.1074/mcp.P119.001913 — gas-phase fractionation DIA;
  mass-defect window placement; ≥~10 points (Skyline trapezoidal) guidance.
- **CQE recommendations preprint** — "Recommendations for Quantitative DIA Proteomics
  using Controlled Quantitative Experiments (CQEs)", *bioRxiv* 2025,
  doi:10.1101/2025.09.22.677725 — instrument-dependent PPP findings (Orbitrap ~6
  ppp_fwhm optimal; timsTOF fine at ~3.4–4.0; over-filtering harmful). *Preprint,
  not yet peer-reviewed; summarized via external analysis, not read directly here.*
- **DIA-NN documentation/FAQ** (Demichev) — aims for ~3–3.5 data points at FWHM
  (≈6–7 total); sufficient for good quant precision (DIA-NN models peaks, so needs
  fewer points than naive trapezoidal integration).

---

## 5. Status / future work

- **Not implemented as config:** a per-instrument `recommended_ppp_fwhm` field was
  intentionally **not** added to `inst/config/instruments.json` because no code
  currently consumes it (avoids dead config). Add it together with a consumer when
  instrument-aware target selection is implemented.
- A possible future "quant-max" mode (Orbitrap, target_dppp ≈ 10, accepting ~20% fewer
  IDs) is documented here but not yet a preset.
