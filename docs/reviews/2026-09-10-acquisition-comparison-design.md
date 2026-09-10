# 2D-KDE acquisition proposals and paired in-silico evaluation

Status: design proposal; no new acquisition data or measured improvement is claimed.
Existing paper optimization algorithms are unchanged. The original-method
baseline integration described below is implemented in Shiny; the broader
paired evaluation design remains proposed.

## Proposed acquisition strategies

1. Use the global RT–m/z domain to concentrate a fixed cycle budget on the useful
   mass range. This is the agreed global-domain proposal. Related time-dependent
   scheduling already exists; a KDE implementation alone does not establish novelty.
2. Within that domain, place windows to reduce transient crowding, rather than
   only equalizing the number of precursor apexes accumulated over an RT bin.
   A proposed objective is to minimize peak/P95 estimated window load or the
   time integral of squared window loads, with count coverage and fixed CT/N
   constraints. Count and signal load remain separate selectable objectives.
   KDE expected load is a smoothed model, not an observed count or actual interference.
3. Require adequate coverage on held-out similar runs, and inspect RT-shift
   sensitivity. Broaden margins where instability is observed, retaining fixed
   CT/N and width feasibility. Do not claim that an offline schedule corrects
   live RT shifts or is equivalent to real-time alignment.

Dynamic DIA precedent: [Heil et al., Dynamic Data Independent Acquisition Mass
Spectrometry with Real-Time Retrospective Alignment](https://pmc.ncbi.nlm.nih.gov/articles/PMC10517878/).
The paper experimentally validates its own acquisition; its effects are not
transferable numerical estimates of AIDIA's effects.

Actual fragment interference requires more than precursor co-occurrence:
[Keller et al., SWATHProphet](https://pmc.ncbi.nlm.nih.gov/articles/PMC4424409/).

## Baseline contract

User clarification: the primary comparator is the user's **initial fixed DIA
method reconstructed from the original acquisition inputs**. It uses a constant
m/z range and equal physical window widths throughout acquisition. Existing KDE
is a secondary research comparator, not the result-page default.

Reuse first-page instrument/resolution/injection-time settings, original MS2
window count and its calculated CT/DPPP. Following the user's confirmation,
the first page accepts an optional original m/z range, defaulting to 400-1000.
The implemented reference uses contiguous equal-width windows without overlap:
W=(mz_end-mz_start)/N. The UI displays the implied width and this assumption.
An original overlap input is a future extension, not part of this change. Do not use observed m/z extrema as a silent replacement
for the acquisition range. No method-file upload is required for this main flow.

Capture all original acquisition inputs and timing output when Execute is pressed.
The before summary currently reads the live cycle_time_result(); it must instead
use the saved original snapshot so later input edits do not change a completed
comparison. Original window count is supplied by the user and must not be
re-derived by dividing CT by MS2 scan time.

If an actual method file is later supplied, its physical windows are an optional
alternative. The main comparison is labelled input-defined original fixed method;
it is not a measured before/after experiment with newly acquired raw data.

The main user flow diagnoses the original DPPP and recommends acquisition setting
changes, so original and optimized CT/N need not match. Keep their actual recorded
values and expose changes in the existing cards; do not replace the original
method with one forced to have the optimized N. Describe this as the whole
recommended-method change, without attributing all effects to m/z geometry alone.
For a secondary research comparison isolating geometry, fix CT, scan settings,
N per cycle and staggered mode. In both cases use the same input/filtering and
evaluation time/population, and report coverage exclusions.
Never infer unknown original windows from peptide coordinates and call them the
method used to acquire the data.

Evaluate every final CSV schedule. Do not transfer a candidate's rt_group labels
to another method. Use the same time grid or exposure weighting across candidates;
an unweighted average over CSV rows changes meaning when K changes.

## Minimal, interpretable result metrics

- Eligible identified precursor coverage: apex/representative-RT inclusion in the
  actual schedule, with numerator and denominator. Separately show common,
  newly included and excluded precursor sets. This is not a predicted ID count.
- Paired estimated co-isolation burden: for targets covered by both methods,
  count other eligible identified precursors sharing a physical window at the
  target RT under a specified elution-interval model. Competitors come from the
  full evaluation precursor table, not only the common target set. Display
  median and P95 burden, paired differences and the shared-set size.
- Time-weighted physical isolation width: report the actual schedule's widths,
  counting overlapping acquisitions as separate exposures when appropriate.
  This describes selectivity/geometry and is not a measured sensitivity gain.
- Signal coverage: input quantity inside the schedule divided by total eligible
  quantity, with the quantity column and normalization displayed. Complement with
  coverage of low-intensity targets to expose selection trade-offs.
- Sampling feasibility: CT/N and modeled DPPP. If CT and FWHM are held fixed,
  the formula alone cannot imply increased DPPP from an m/z placement change.
- Optional stability: held-out-run deltas and the existing boundary-loss proxy.
  Without independent runs, label results as evaluation on design input.

For a burden metric P, relative change is 100*(1-P_new/P_reference) only when
P_reference>0. Otherwise display absolute changes and no relative percentage.
Use fixed thresholds across methods for overload rates; each method's own P95
or own median cannot define a comparable overloaded-window fraction.

An isolated loss in coverage must not be hidden behind lower burden. Prefer
separate metrics or Pareto candidates over an unsupported overall efficiency score.
Results can show an improvement, a trade-off, no material change, or deterioration.

## Limits and validation

The input table omits unidentified ions/background and reflects the method and
search that generated it. A modeled overlap count is not a rigorous lower bound
on actual simultaneous isolation when timing, peak shapes and false IDs are uncertain.
Do not convert burden reductions into detection, quantification CV, LOD, or S/N gains.

Use recorded peak start/stop intervals if valid and retained. Otherwise use one
explicit FWHM-derived interval model with fixed units on both sides; report sensitivity
to that interval choice. It is unnecessary to posit a Gaussian intensity shape for
the first implementation. Include peaks intersecting a bin even if their apex is
outside it. For staggered data, evaluate physical cycle 1/2 exposures separately;
do not claim demultiplexed separation from nominal half-width geometry alone.

To avoid rewarding its own KDE, validate window geometry against held-out precursor
coordinates/intervals rather than only the fitted density surface. Any tuning of
KDE bandwidth, K, smoothing or method choice uses training/validation data; independent
test runs are needed for an unbiased final generalization claim.

## Current code findings

- Shiny BEFORE summarizes input data and current planning controls, not a baseline method.
- Shiny calls plot_temporal_density(evaluation_result) without a baseline argument.
- The plot already accepts baseline_density, and the report path computes a naive
  baseline. However .compute_baseline_density estimates N from diagnosis CT divided
  by MS2 time, uses bin-specific observed m/z extrema and the optimized RT bins.
  It does not guarantee matched timing/N or reproduce a measured reference method.
- Existing temporal density assumes RT.Apex +/- FWHM (total width 2*FWHM), uses
  unit inference rather than explicit metadata, and prefilters by apex-in-bin.
  The latter excludes cross-boundary elution. The singleton mean uses untruncated
  duration. These must be addressed before interpreting K-dependent comparisons.
- Existing plot overload rates use >2*the candidate's median, and the evaluator
  has a candidate-specific P95 threshold. These are within-result diagnostics,
  not fixed-reference improvement metrics.

## Results layout — reuse first

The prior standalone four-card proposal is a future layout reference, not the
initial implementation target. Preserve the current results-page structure.

| Existing element | Reuse / minimum addition |
| --- | --- |
| CT, DPPP, window-count cards | Retain; show original -> optimized values from saved data. CT already shows a relative change. |
| Acquisition Capacity Diagnostics | Retain capacity/target diagnostics; do not duplicate them as new efficiency cards. |
| BEFORE / AFTER summaries | BEFORE describes the input-defined fixed method, not only the precursor table; preserve dataset context separately. |
| m/z Range Summary | Reuse to show original constant range/width and optimized range/width. |
| Precursor Distribution Across Windows | Reuse existing plotting infrastructure; add baseline distribution with consistent evaluation RT intervals. |
| Precursor Temporal Density | Primary improvement area: original vs optimized values, difference, shared-target burden and retained/lost targets. |
| Detailed Results | Put extra P95, signal and run-level metrics here rather than adding another dashboard row. |

plot_temporal_density() already accepts baseline_density; Shiny does not supply
it. That interface and the equal-width plotting work in plot_precursor_load_balance()
are reusable, but their baseline construction must be replaced by the shared
original-method snapshot. Route report and Shiny comparisons through the same
baseline/evaluation contract instead of retaining independent baseline factories.

Start the co-elution panel with a compact original / optimized / change summary,
then show comparable curves or paired distributions using shared axes. Preserve
the detailed RT-faceted plot as an optional view. Show coverage alongside burden
so dropping targets is visible. Label values as estimated from the input precursor
data; worsening values must remain visible. Fix original baseline construction
and interval accounting before reporting reduction percentages.

Implementation order: (1) original acquisition snapshot and missing range/overlap
inputs, (2) shared fixed baseline and consistent evaluator, (3) connect the existing
co-elution panel, (4) fill original/new annotations in existing summaries/cards.
This evaluation work can support existing strategies before 2D-KDE exists. It does
not require changing the paper's m/z/RT optimization algorithms.

The [interactive layout mockup](acquisition-comparison-mockup.html) deliberately
contains no invented result values. The user considers it useful as a later
reference; it is not a Shiny integration or the immediate replacement layout.


## Implemented baseline correction (2026-09-10)

- First-page optional original m/z start/end default to 400/1000. N comes from
  the original window-count input; 40 windows imply 15 m/z width. Original range
  settings do not constrain the optimized method's m/z range.
- Execute captures range, N, width, acquisition controls, and calculated timing
  in both the plan and completed result. Strategy replay preserves the snapshot.
  The BEFORE summary reads saved timing rather than live controls.
- A shared baseline factory replaces all three data-extrema/CT-derived factories.
  It repeats identical original m/z edges over the candidate RT intervals solely
  for evaluation/display. It does not make the original acquisition RT-dependent.
- Shiny temporal-density and report comparisons use the same original reference.
  Legacy results without original settings omit the reference. Existing cards
  and plot layouts are retained. Zero reference medians use absolute differences.
- This correction retains the existing apex-filtered, FWHM-based temporal proxy
  and per-window summary. It does not implement shared-target burden, interval
  boundary corrections, paired coverage panels, or measured acquisition gains.
  Median/CV differences are descriptive estimates, not overall efficacy scores.

Validation: scoped fixed-reference, strategy replay/Shiny execution, temporal
proxy, and method-delivery tests passed. Shiny UI construction and app-file R
syntax checks passed. Browser rendering and instrument acquisition were not tested.

Pre-push verification: the full test suite passed 1311 assertions with zero
failures or errors; four tests were skipped because their data fixtures were
unavailable. Warnings concerned package build versions and deprecated test/API
usage. Shiny UI construction and main/app R syntax checks also passed.
