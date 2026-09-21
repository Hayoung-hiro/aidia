# Review & export redesign

The Results page follows three questions: where the delivered method acquires,
what acquisition trade-offs it makes, and how it distributes precursor load.
The sidebar and page heading both use **Review & export**.

## Download placement and consistent disclosures

The page presents Confirmed method, Download, then Compare with original.
The individual method download and All formats (ZIP) are adjacent, with the
format schema still visible below. All Results disclosures share the same
font, spacing and expand/collapse marker, including Advanced acquisition
diagnostics. The isotope boundary plot remains unchanged.

## Delivered acquisition regions

The previous comparison drew optimization-bin extents. Export joins neighboring
RT bins at their midpoint and rounds those boundaries to two decimals, so gaps
in the old picture did not represent gaps in the delivered Thermo method.

Thermo CSV and Results now share `.prepare_thermo_windows()`: contiguous RT
boundaries, optional run start/end extension, and four-decimal center/width
rounding. The RT/mz comparison and Inspect windows use this delivered geometry;
precursor loads and coverage are recounted against acquisition intervals instead
of earlier optimization-bin labels. The original fixed method is evaluated on
the same final RT intervals. Other export formats have no RT columns; nearby
text identifies the schedule as the Thermo file, also present in the ZIP.

The default outline joins only sub-0.00015 m/z seams arising from independent
CSV center/width rounding. Individual-window mode draws exact delivered bounds.
Both panels retain identical input backgrounds, axes and color scales.

## Acquisition trade-offs

The combined covered/target-met score was removed. The table shows original,
designed, and signed change for median DPPP, cycle time, total cycles, MS1 scans,
MS2 scans, windows per cycle, and average isolation width.

Analysis seconds = 60 times (last input report RT apex - first RT apex).
Cycles = analysis seconds / saved cycle time; MS1 total = cycles times MS1 scans
per cycle; MS2 total = cycles times MS2 windows per cycle. Thus a 40-minute span
at 2 s and 3 s gives 1200 and 800 cycles (and MS1 scans for one MS1 per cycle).
Changing export run extensions does not change this report-based duration.
These are model estimates; DPPP uses the same input median FWHM for both arms.
Parallel MS1 is explicitly labeled, because zero is a concurrency flag rather
than zero acquired scans. Staggered window counts use one cycle, not both.

## Precursor load balance

Results reuses the report's `plot_precursor_load_balance()` with final method
geometry, supporting all RT groups, pooled per-window loads, or one RT group.
Empty windows remain included. The audit corrected three presentation/accounting
issues in the shared report function: an all-empty baseline was omitted because
its CV is undefined; explicit RT memberships were ignored; and random vertical
jitter could move zero-count points away from zero. Jitter is now reproducible
and horizontal only. Pooled CV is labeled as descriptive because it includes
abundance differences between RT groups, not solely within-group balance.

Duplicate optimization and per-window plots were removed from Results. Window
inspection remains next to downloads. Capacity diagnostics stays collapsed.

## Verification

- Minimal RT-gap repro: old display 10-18 / 20-30 vs CSV 10-19 / 19-30;
  after the fix, both match 10-19 / 19-30.
- Related export, accounting and Results suites: 263 assertions passed.
- Full suite: 1474 assertions passed, zero failures/errors, four missing-fixture
  skips. Final Results-only checks after display polish: 51 passed.
- Regression checks cover the 40-minute example, immutable report duration,
  RT and m/z CSV parity, run extension, boundary rounding, shared plot scales,
  empty baseline, explicit membership, deterministic jitter and draft isolation.
- Headless Edge, 1440 x 1000: 12,000 synthetic precursors, Exploris, confirmed
  result, all load views, exact contiguous CSV schedule, optional 0-70 min
  extension, Inspect windows, generic-format explanation and unchanged CSV
  after draft edits. No browser or Shiny output errors.

- Final layout browser check: all four comparison disclosures expand/collapse
  with matching computed styles; download buttons are adjacent and precede
  comparison; ZIP contains three CSV formats, including an exact match to the
  individually downloaded Thermo method. No browser or Shiny output errors.
- User confirmed all functionality works before requesting commit and push.

Screenshots use synthetic input, not experimental validation. The first two
capture comparison behavior before the final download-placement adjustment:

- [Final method and trade-offs](2026-09-21-results-assets/04-final-method-and-tradeoffs.png)
- [Run extension](2026-09-21-results-assets/05-final-method-with-run-extension.png)

- [Final download placement](2026-09-21-results-assets/06-download-before-review.png)
- [Consistent comparison rows](2026-09-21-results-assets/07-matching-comparison-rows.png)
