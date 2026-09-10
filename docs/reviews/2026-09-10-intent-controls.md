# Purpose-oriented controls and navigation feedback

Implemented in `Hayoung-hiro/shiny-workflow-ux`, on top of the confirmed/live-preview work and the pending page 1/3 theme changes.

## Navigation

- Removed the unused global bs4Dash tooltip switch (`help = NULL`). Contextual `?` disclosures remain beside the controls they explain.
- Next and sidebar navigation use the same prerequisites. Missing `report.parquet`, failed uploads, and incomplete acquisition settings explain what to fix beside the page 1 action.
- Configure lists incomplete fields, incompatible Greedy span/count combinations, and worker errors beside Confirm. Confirmation requested during calculation displays a waiting message; it opens Results when that matching calculation completes.
- Invalid edits do not start a calculation using fallback defaults. Existing confirmed methods remain downloadable until a new result is confirmed. New input data still invalidates prior results.

## Control audit

| Area | User-facing change | Canonical meaning |
|---|---|---|
| Greedy | Enter **Total m/z span**, with a compact count-to-width readout | `min_width_da = span / resolved_window_count`. Manual uses the selected count; Auto uses `plan_optimization()`'s actual count. |
| Greedy search | Search step and smoothing are under Search details | Search step changes starting-position resolution, not span. Smoothing remains the existing postprocessor. |
| Isolation widths | Separate individual Max width from total span; hide the editable minimum for Greedy | The minimum is derived for Greedy. Other strategies retain their existing minimum target. Max width remains the individual-window cap. |
| Quantile | Sliders for low/high m/z tail exclusion, in percent; display retained percentage | `lower = excluded_low / 100`, `upper = 1 - excluded_high / 100`. Asymmetric exclusions and existing ranges are preserved. |
| KDE | Density cutoff, distinct from minimum precursor inclusion | Cutoff remains a fraction of KDE peak height, not a precursor percentage. |
| Coverage | Precursor inclusion target | Selection inclusion is distinguished from final generated-window coverage. |
| RT grouping | Automatic duration / Detect distribution changes / Choose duration | Existing `fixed` / `adaptive` / `custom` values and algorithms remain. |
| Outlier | Existing SD threshold retained | Already expresses the rule as mean m/z plus/minus a multiple of SD; no parameter conversion needed. |

KDE + Density remains the default strategy. Greedy's newly explicit span starts at 200 m/z. Section Reset restores the new controls from the confirmed snapshot, or defaults before confirmation.

The 100 m/z / 50 windows example maps to `min_width_da = 2`. It does not promise every generated Density window is 2 m/z wide. Existing density generation, smoothing, and boundary digitization can affect actual widths and final range boundaries. The help distinguishes the search span from those outputs.

No scientific algorithms or S3 object contracts were changed. The Shiny adapter calls the existing constructors and optimizer. Comparisons retain the confirmed run's shared resolved count and width constraints; a hidden Greedy span does not introduce independent comparison settings. Legacy Shiny input lists without the new fields remain supported by the adapter.

## Validation

- R parsing and `shiny-intent-controls`, `shiny-live-preview`, `strategy-comparison`, `method-delivery` tests pass.
- Real canonical optimization verifies 100/50 gives a 100 m/z unsmoothed search span and the same windows, parameters, selection, and statistics as the legacy `min_width_da = 2` invocation. Runtime metadata is excluded from equality checks.
- Automatic count conversion, asymmetric Quantile percentages, missing uploads, failed-upload messages, blank acquisition/setup fields, invalid span constraints, snapshot preservation, and recovery are covered by tests.
- Desktop Edge checks pass with 12,000 synthetic precursors: Next/sidebar guards, 100/50 mapping, invalid and blank span recovery, confirmed CSV preservation, section Reset, asymmetric Quantile sliders, and automatic count constraints. No browser JavaScript or Shiny output errors were observed. User data and scientific performance are outside this UX check.

## Screenshots

- [Missing file guidance](2026-09-10-intent-controls-assets/01-missing-file.png)
- [Greedy: 100 m/z with 50 windows](2026-09-10-intent-controls-assets/02-greedy-100-over-50.png)
- [Incompatible span guidance](2026-09-10-intent-controls-assets/03-invalid-span.png)
- [Quantile tail percentages](2026-09-10-intent-controls-assets/04-quantile-tail-percentages.png)
- [Automatic count constraint](2026-09-10-intent-controls-assets/05-auto-span-guidance.png)
- [Greedy with automatic count](2026-09-10-intent-controls-assets/06-greedy-auto-count.png)
