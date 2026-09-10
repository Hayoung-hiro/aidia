# DIA Isolation-Window Optimization — State of the Art (2019–2025)

Cited synthesis of the literature on DIA isolation-window design (width, count,
boundary placement) for bottom-up proteomics, with emphasis on Thermo Orbitrap /
Orbitrap Astral / Bruker timsTOF and DIA-NN library-free workflows.

> **Provenance.** Produced by the `deep-research` harness: 5 search angles → 17 sources
> → 85 candidate claims → 25 adversarially verified (3-vote) → **23 confirmed / 2 refuted**
> → 11 synthesized findings. This is a research summary, not a peer-reviewed document;
> treat instrument-specific numbers as indicative and re-verify against the primary
> sources before acting. Web sources (publisher pages / preprints / repos); several
> primary URLs were 403 and confirmed via open-access PMC mirrors.

---

## TL;DR

Window design is three coupled levers — **WIDTH**, **COUNT**, **PLACEMENT** — and the
optimum depends strongly on **instrument speed** and **sample load**. Two paradigms:

1. **Conventional Orbitrap (QE/Exploris) and timsTOF** — variable / density-adapted
   windows (equal precursor load per window) + mass-defect "forbidden-zone" boundaries
   + staggered/overlapping windows with computational demultiplexing.
2. **Ultra-fast Orbitrap Astral** — narrow uniform windows (nDIA: ~2 Th over 380–980 m/z
   at ~200 Hz), giving ~2× proteins and ~3× peptides of competing platforms at median
   precursor CV < 7%.

DIA-NN library-free is the common analytical backbone, so these principles are directly
actionable in DIA-NN workflows.

---

## By lever

### 1. WIDTH
- **Variable/density-adapted > equal-width.** Peptide masses are non-uniform across m/z;
  equal-width windows over-fill low-m/z windows (fill in ms while high-m/z accumulates to
  the full maxIT, e.g. 251 ms), raising spectral complexity and losing low-m/z sensitivity.
  Variable division (library- or TIC-based) equalizes precursor species per window.
  *(DO-MS, J Proteome Res 2023, 10.1021/acs.jproteome.3c00177; MCP 2024 DIA survey,
  S1535947624000021)* — **high**
- **Optimal width is load-dependent (Astral).** 100 ng → 4-Th / 7-ms maxIT (8,600 proteins);
  10 ng → 8-Th (6,600). Narrow windows under-sample at low ion load.
  *(Guzman et al., Nat Biotechnol 2024, s41587-023-02099-7)* — **high**
- **Narrower ⇒ more IDs but worse quant CV.** Astral 24-min gradient: 2-Th vs 3-Th →
  9,817 vs 9,353 HeLa IDs, but 2-Th "noticeably skews the %CV distribution" (still avg
  %CV < 13% HeLa / < 20% plasma); effect is smaller at shorter gradients.
  *(Heil et al., J Proteome Res 2024, 10.1021/acs.jproteome.4c00384)* — **high**

### 2. COUNT (governed by data-points-per-peak, DPPP)
- **More windows ⇒ lower per-window complexity, more IDs, but longer cycle ⇒ lower DPPP ⇒
  worse quant.** Q Exactive Classic: most IDs at 6/8/10 MS2 windows, **best quant+coverage
  balance at 4–6 MS2 scans**; >12 windows gave >2× lower median shared-peptide ratio than 2.
  timsTOF 60 SPD: **12 dia-PASEF scans (~6 points/peak)** optimal. **Does NOT generalize to
  Astral** (300 windows @ >200 Hz achieve top IDs AND quant). *(DO-MS 2023; py_diAID, MCP
  2022, S1535-9476(22)00087-1)* — **high**
- **Counter-intuitive: for short-gradient Orbitrap quant, deliberately LOWER DPPP**
  (longer cycle, more/narrower windows) to massively increase IDs while keeping quant
  precision — data-points-per-protein stays ~constant. QE-HF, 30 min: 6,018 HeLa proteins,
  >80,000 precursors, CV < 20%, 29 samples/day. *(Steger/Sandow, J Proteome Res 2023,
  10.1021/acs.jproteome.3c00078)* — **high**. Caveat: very low DPPP can hurt LOQ for
  low-abundance precursors.

### 3. PLACEMENT
- **Mass-defect forbidden-zone boundaries.** Averagine composition creates m/z "forbidden
  zones" where no peptide precursor can exist; placing window edges there minimizes
  quadrupole transmission edge effects and boundary precursor loss. *(Pino/Searle/MacCoss,
  MCP 2020, 10.1074/mcp.P119.001913; py_diAID)* — **high**. **Nuance: for hyperbolic
  segmented-Q1 instruments (QE+/HF/HFX/Fusion Lumos) explicit forbidden-zone placement is
  often unnecessary.**
- **Staggered/overlapping + demultiplexing = compressed sensing.** Wide physical windows →
  narrower effective windows via post-acquisition demux, no cycle penalty. MSX: 20-m/z →
  5 × 4-m/z (5× selectivity). Searle staggered (QE): alternating 500–900 / 490–890 m/z →
  41 effective 10-m/z regions (2× selectivity). Requires a demux step (Skyline / ProteoWizard
  MSConvert, ~2× spectra). *(Egertson, Nat Methods 2013; Searle, JASMS 2018, PMC6445824;
  MCP 2024 survey)* — **high**
- **RT-scheduled small windows (RTwinDIA).** Reallocate cycle time to narrow (5-m/z) windows
  placed in different RT blocks (larger peptides elute later in RP-LC) → +10.6% proteins
  without exploding cycle time. *(Li/Liu, JASMS 2019, 10.1007/s13361-019-02243-1)* — **high**

---

## By instrument
- **Orbitrap Astral** — nDIA: 300 × 2-Th windows, 380–980 m/z, ~200 Hz, 2.5-ms maxIT
  (window size scaled to maxIT). DIA-NN library-free, 5-min gradient: 7,538 PG vs Exploris
  480 (3,143), timsTOF HT (3,737), ZenoTOF 7600 (3,419), TripleTOF 6600 (3,330). ~10,000 PG
  / median CV < 7% on HEK293. *(Guzman, Nat Biotechnol 2024)*
- **Bruker timsTOF** — 2-D (m/z × ion mobility) dia-PASEF; py_diAID density-adapted windows
  reach 99%/94% theoretical 2+/3+ precursor coverage (vs 88%/71% equidistant), large
  phospho gains (+28% phosphosites). *(Skowronek, MCP 2022)*
- **Orbitrap QE/Exploris** — variable windows + DPPP-tuned count + (when Q1 edges are sharp)
  forbidden-zone placement + optional staggered/demux.

---

## Refuted (excluded by 2/3 adversarial vote)
- ❌ "DIA window-scheme optimization is *understudied*." Overstated — py_diAID, DO-MS,
  swathTUNER, RTwinDIA are an active body of work.
- ❌ "Orbitraps are *categorically* better than ToF for staggered-window demultiplexing."
  Not supported as a general rule.

## Open questions
1. Quantitatively optimal **DPPP/width for Exploris 480 and QE HF/HFX under DIA-NN** —
   recent benchmarking concentrates on Astral; Orbitrap guidance comes mostly from QE Classic.
2. Head-to-head of **staggered/demux vs nDIA vs py_diAID variable** on the *same* modern
   instrument/sample (ID depth, CV, pipeline complexity).
3. The **low-DPPP limit for reliable quant** per instrument/gradient (~1.5 DPPP works in some;
   others warn of LOQ degradation for low-abundance precursors).
4. timsTOF (HT/Ultra) **2-D variable / overlapping schemes** (midia-PASEF, synchro-PASEF) vs
   Astral nDIA under matched DIA-NN workflows.

## Caveats
- **Instrument-regime dependence is the dominant caveat** — window-count rules (4–6 MS2,
  ">12 degrades quant") are mid-speed-instrument measurements and do not transfer to Astral.
- The Astral "2×/3×" multipliers used previously published reference datasets for
  competitors (not same-lab head-to-head) — indicative, not rigorously controlled.
- The short-gradient low-DPPP quant result rests on a single (peer-reviewed) source.
- Forbidden-zone placement matters mainly where Q1 transmission edges are sharp.

## Key sources
| Source | Topic |
|--------|-------|
| Guzman et al., *Nat Biotechnol* 2024 (s41587-023-02099-7) | Astral nDIA, cross-platform benchmark, load-dependent width |
| Heil et al., *J Proteome Res* 2024 (10.1021/acs.jproteome.4c00384) | Astral width vs quant trade-off |
| Skowronek et al., *MCP* 2022 (S1535-9476(22)00087-1) | py_diAID variable dia-PASEF, forbidden zones |
| DO-MS, *J Proteome Res* 2023 (10.1021/acs.jproteome.3c00177) | variable vs equal width, window-count/DPPP |
| Steger/Sandow, *J Proteome Res* 2023 (10.1021/acs.jproteome.3c00078) | low-DPPP short-gradient quant |
| Pino/Searle/MacCoss, *MCP* 2020 (10.1074/mcp.P119.001913) | mass-defect forbidden-zone placement |
| Searle, *JASMS* 2018 (PMC6445824); Egertson, *Nat Methods* 2013 | staggered/overlapping + demux |
| Li/Liu, *JASMS* 2019 (10.1007/s13361-019-02243-1) | RT-scheduled small windows (RTwinDIA) |
| MannLabs/pydiaid (GitHub); MCP 2024 DIA survey (S1535947624000021) | tooling, survey corroboration |

See `docs/ROADMAP_window_optimization.md` for how these findings map to AIDIA work items.
