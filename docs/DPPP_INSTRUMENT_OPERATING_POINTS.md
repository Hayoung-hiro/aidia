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
| "Sufficient" floor (good precision, ID-friendly) | ~3–3.5 ppp_fwhm | ~5–6 DPPP | DIA-NN guidance |
| **AIDIA default (quant)** | ~4.1 ppp_fwhm | **7.0 DPPP** | ID-friendly balance for sequential Orbitrap |
| Skyline trapezoidal workflows | ≥~10-ish | higher | Different quant engine — NOT required for DIA-NN |

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

---

## 4. References (verified via PubMed unless noted)

- **Pino LK, Just SC, MacCoss MJ, Searle BC.** Acquiring and Analyzing Data Independent
  Acquisition Proteomics Experiments without Spectrum Libraries. *Mol Cell Proteomics*
  2020;19(7):1088–1103. doi:10.1074/mcp.P119.001913 — gas-phase fractionation DIA;
  mass-defect window placement; ≥~10 points (Skyline trapezoidal) guidance.
- **DIA-NN documentation/FAQ** (Demichev) — aims for ~3–3.5 data points at FWHM
  (≈6–7 total); sufficient for good quant precision (DIA-NN models peaks, so needs
  fewer points than naive trapezoidal integration).

---

## 5. Status / future work

- **Not implemented as config:** a per-instrument `recommended_ppp_fwhm` field was
  intentionally **not** added to `inst/config/instruments.json` because no code
  currently consumes it (avoids dead config). Add it together with a consumer when
  instrument-aware target selection is implemented.
