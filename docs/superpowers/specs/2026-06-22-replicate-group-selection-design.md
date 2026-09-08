# Replicate group scan & selection at data load — DRAFT (in progress)

Status: **IN PROGRESS / 고도화 예정** — design started 2026-06-22, paused before
section (B) and before final approval. Resume from "Open items" below.

## Problem

`create_validated_dataset()` → `load_diann_data()` → `calculate_consensus_dataset()`
assumes the input DIA-NN report contains **technical replicates of a single
condition**. The replicate consensus groups by `Precursor.Id` alone
(`R/replicate_utils.R:28,119,157`).

When a *combined* report is fed in (e.g. `LFQb_Re-main/Diann_res/report.parquet`:
36 runs = 6 methods × SampleA/B × 3 reps), this silently merges heterogeneous
conditions. Measured on that file:

- per-precursor merged runs: median 14, mean 17, max 36
- **78.7%** of precursors span >1 acquisition method (53,765 span all 6)
- **72.7%** span both SampleA (65:30:5) and SampleB (65:15:20)

Consequences:
1. RT/Mz/FWHM consensus averages across different window schemes → destroys the
   per-method distinction the window/boundary (fz) analysis depends on.
2. `max_intensity_cv_percent = 30` filter on geometric intensity CV conflates
   real A-vs-B biological fold-change (yeast 2×, E.coli 4×) with technical CV →
   wrongly removes valid precursors.
3. Pre-consensus global `distinct(Precursor.Mz, RT.Start)` in `validate_data()`
   (`R/data_loader.R:254`) is not run-aware → can drop cross-method rows.

Note (separate, already diagnosed): the same file's `PG.MaxLFQ.Quality` column is
all-zero, so the default `pg_maxlfq_quality_threshold = 0.7` filter drops every
row ("0 precursors"). Workaround: `pg_maxlfq_quality_threshold = NULL`. Robust
fix: skip degenerate (all-NA / zero-variance) quality columns with a warning.

## Agreed direction

Keep the **"run one method at a time"** assumption as the core contract. Add a
convenience layer to (a) show what condition-groups a report contains and (b)
select a subset before processing.

### Decisions locked
- **Grouping must be flexible / overridable** — naming conventions vary; never
  hard-code one regex.
- **API = 2-step**: `scan_groups()` (inspect) → explicit selection argument on
  `create_validated_dataset()`. Reproducible in scripts and Shiny (no interactive
  console prompt).
- **Default group key = `method`**; user may add finer keys (e.g. `sample`) when a
  condition needs splitting → `group_by = c("method","sample")`.
- **No silent mixing**: if selection is omitted and >1 group exists → error asking
  which group; proceed automatically only when a single group is present.
- **Fallback**: if the run parser matches nothing → warn and treat each Run as its
  own group (never mis-group silently).

### Design (A) — group model & API  [proposed, not yet approved]

1. **Run attribute extractor (overridable).** Default named-capture regex pulls
   `sample`, `gradient`, `method`, `rep` from Run names; default pattern tuned to
   `<date>_Sample(?<sample>[AB])_(?<gradient>[^_]+)_(?<method>.+)_(?<rep>\d+)(\.trimmed)?`.
   `run_parser` arg accepts a user regex (named groups) **or** a
   `function(run) -> data.frame` to fully replace it.

2. `scan_groups(file, group_by = "method", run_parser = NULL)` — lightweight read
   (only Run + Precursor.Id + minimal cols), returns/prints a group summary:
   `group_id | method | samples | n_runs | n_precursors` (+ the Run vector per
   group). `group_by = c("method","sample")` splits finer.

3. `create_validated_dataset(file, groups = ..., group_by = "method", run_parser = NULL, ...)`
   — `groups` = group_id(s) or label(s) from scan. Omitted + single group → run;
   omitted + multiple → error. Internally filters to the selected Runs, then the
   existing pipeline proceeds.

## Open items (resume here)

Section (B) not yet drafted / approved:
- **Consensus change**: thread the group key into `calculate_consensus_dataset()`
  (`group_by(Precursor.Id, <keys>)`), or rely on pre-filtering to one group so
  `Precursor.Id`-only grouping stays correct. Decide which.
- **CV-filter guard**: when a selected group still spans >1 sample (default
  method-only merges A/B), auto-skip intensity-CV filter + warn. Specify exactly.
- **Degenerate-column guard** in `filter_diann_quality()` (the PG.MaxLFQ.Quality=0
  bug) — include here or separate PR?
- **Run-aware dedup**: change the global `distinct(Precursor.Mz, RT.Start)` to be
  per-Run (or Precursor.Id+Run).
- **Backward compatibility**: existing single-condition callers must work
  unchanged (no `groups`, no `run_parser`).
- **scan performance**: confirm reading only Run/Precursor.Id is enough for counts.
- **Testing plan**: grouping/parsing/fallback, selection resolution, CV-guard,
  no-silent-mixing error.
- User wants to **"고도화"** (advance/deepen) the design further before building.

## Related context
- Raw files for the fz/boundary cross-check are ready at
  `C:\Users\Hayoung\Downloads\KHUPO2026_준비`:
  `20260608_SampleA_60min_dppp4_adap_dense_01.raw` and
  `20260608_SampleA_60min_Fixed_01.raw` (same sample+rep, two methods → isolation
  window scheme comparison). Boundary/fz analysis is a separate task thread.
