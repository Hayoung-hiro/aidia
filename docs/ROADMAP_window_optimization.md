# AIDIA Roadmap — Window Optimization (derived from SOTA review)

Concrete work items distilled from `docs/DIA_WINDOW_OPTIMIZATION_SOTA.md`. Each maps a
verified literature finding to an AIDIA gap, with a code pointer, effort/risk, and
acceptance criteria. Priorities: **P1** = high value + clear path, **P2** = valuable,
needs design, **P3** = experimental / validation.

> What the review **validated** in AIDIA (no action needed, keep): variable/density window
> mode; mass-defect forbidden-zone boundaries (`OPTIMAL_INCREMENT`); staggered + demux mode;
> DPPP-driven window count for sequential Orbitrap; **Astral sync-first (DPPP non-binding)**;
> RT-segmented windows. The review also **refuted** "window optimization is understudied" —
> so AIDIA's differentiator is **workflow integration** (DIA-NN input → instrument-aware
> sync / forbidden-zone / DPPP → Thermo method file), not "optimization" per se.

---

## P1 — High value, clear path

### P1.1 Instrument-aware forbidden-zone application
- **What:** Make mass-defect forbidden-zone boundary placement conditional on the analyzer's
  Q1 transmission profile, instead of applying it to every instrument unconditionally.
- **Why:** Forbidden-zone placement minimizes Q1 edge effects, but for **hyperbolic
  segmented-Q1 Orbitraps (Q Exactive+/HF/HFX, Fusion Lumos) it is often unnecessary**
  (Pino/Searle/MacCoss, MCP 2020). Applying it there adds non-integer boundaries for no gain.
- **Where:** `R/window_generation.R` (`transform_boundaries_to_fz`, `calc_forbidden_edge`,
  `generate_*_windows_internal` `fz_offset` plumbing); `inst/config/instruments.json` +
  `R/instrument_config.R` (add e.g. `q1_segmented: true/false` or `forbidden_zone_default`).
- **Effort:** M · **Risk:** Low (additive flag; default preserves current behavior).
- **Acceptance:** Each instrument config declares whether FZ is applied by default; pipeline
  honors it; staggered mode (which genuinely needs FZ) still forces it; tests cover both.

### P1.2 Document the demultiplexing step for staggered output
- **What:** Make explicit, in the exported method/report and Shiny, that staggered output
  requires a post-acquisition demultiplexing step before DIA-NN analysis.
- **Why:** Staggered/overlapping windows only realize their selectivity gain after demux in
  Skyline / ProteoWizard MSConvert (~2× spectra) (Searle JASMS 2018; MCP 2024 survey).
  Users who skip demux get wide-window data.
- **Where:** `R/export_methods.R` (staggered branch / Loop-Control guidance), Shiny Step 3,
  `README`.
- **Effort:** S · **Risk:** None (docs/UX only).
- **Acceptance:** Staggered exports carry a clear "demultiplex before DIA-NN" note + tool pointer.

---

## P2 — Valuable, needs design

### P2.1 Load-dependent window-width guidance
- **What:** Let sample load (ng on column) influence recommended window width / maxIT —
  narrower at high load, wider at low load.
- **Why:** Optimal Astral width is load-dependent: 100 ng → 4-Th/7-ms (8,600 proteins),
  10 ng → 8-Th (6,600); narrow windows under-sample at low ion load (Guzman, Nat Biotechnol
  2024; Heil, JPR 2024).
- **Where:** new optional `sample_load_ng` input → `get_instrument_width_recommendations()`
  (`R/instrument_config.R`) and `plan_optimization()` / `run_complete_pipeline()`.
- **Effort:** M–L · **Risk:** Med (new user input + recommendation logic; keep optional with
  a sensible default so existing calls are unchanged).
- **Acceptance:** Given a load, AIDIA shifts recommended width/maxIT in the documented
  direction; absent load, behavior is unchanged.

### P2.2 "Quant-max / low-DPPP" mode for short-gradient Orbitrap
- **What:** A documented operating point that *lowers* DPPP (longer cycle, more/narrower
  windows) to maximize IDs while holding quant precision — distinct from the default quant
  target (DPPP 7).
- **Why:** For short-gradient Orbitrap quant, reducing DPPP increases IDs while
  data-points-per-protein stays ~constant (Steger, JPR 2023: 6,018 proteins, CV<20%, 30 min).
  This is a *different operating point*, not a contradiction of DPPP 7. See
  `docs/DPPP_INSTRUMENT_OPERATING_POINTS.md`.
- **Where:** target/preset layer (`config/presets/`, `plan_optimization()` `target_dppp`),
  documented alongside ID(1.5)/balanced(4)/quant(7).
- **Effort:** M · **Risk:** Low–Med (mode/preset + docs; flag LOQ caveat for low-abundance).
- **Acceptance:** A selectable mode/preset documented with its trade-off and the LOQ caveat.

### P2.3 Astral nDIA preset alignment
- **What:** Verify/ship an Astral preset that reproduces nDIA-style schemes (≈300 × 2-Th over
  ~380–980 m/z, window size scaled to maxIT ~2.5 ms @ ~200 Hz).
- **Why:** nDIA is the published SOTA for Astral and is exactly what AIDIA's sync-first path
  should converge to (Guzman, Nat Biotechnol 2024).
- **Where:** `inst/config/instruments.json` (astral), sync logic in `R/optimization_planning.R`
  Step 5b, `config/presets/`.
- **Effort:** S–M · **Risk:** Low.
- **Acceptance:** Astral preset emits ~2-Th uniform windows over the nDIA range at sync-optimal
  count; documented as the nDIA-equivalent.

---

## P3 — Experimental / validation (no code, or benchmark-driven)

### P3.1 Exploris 480 / QE HF·HFX DPPP·width benchmark under DIA-NN
- **What:** Empirically determine optimal DPPP/width/count for these Orbitraps under DIA-NN
  library-free analysis, then validate AIDIA's defaults against it.
- **Why:** Open question in the literature — recent benchmarking concentrates on Astral;
  Orbitrap guidance is mostly QE Classic. This is a gap AIDIA could fill and a direct
  validation of its sequential-Orbitrap recommendations.
- **Effort:** Experimental (instrument time + DIA-NN runs) · **Risk:** n/a.
- **Acceptance:** A small benchmark table feeding AIDIA's Exploris/QE defaults.

### P3.2 Resolve the low-DPPP quant boundary
- **What:** Determine, per instrument/gradient, how low DPPP can go before quant
  (LOQ / significance for low-abundance precursors) degrades.
- **Why:** Sources disagree (~1.5 DPPP works in some; others warn of LOQ loss). Needed to set
  a safe lower bound for P2.2.
- **Effort:** Experimental/literature · **Risk:** n/a.

### P3.3 Parity check: AIDIA density mode vs py_diAID / swathTUNER
- **What:** Benchmark AIDIA's variable/density windows against established density tools on the
  same data (coverage, CV).
- **Why:** Establishes AIDIA's density mode is competitive with the field standard
  (Skowronek MCP 2022; swathTUNER).
- **Effort:** Experimental · **Risk:** n/a.

---

## Suggested sequencing
1. **P1.1** (instrument-aware FZ) + **P1.2** (demux docs) — low-risk, immediately useful,
   and P1.1 closes the one concrete nuance the SOTA review raised about a current AIDIA
   behavior.
2. **P2.3** (Astral nDIA preset) then **P2.1/P2.2** (load-aware width, quant-max mode).
3. **P3.x** experimental validation as instrument time allows (P3.1 is the highest-value gap).

References: see `docs/DIA_WINDOW_OPTIMIZATION_SOTA.md` and
`docs/DPPP_INSTRUMENT_OPERATING_POINTS.md`.
