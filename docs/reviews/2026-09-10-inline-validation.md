# Sampling layout and local validation

Follow-up to the purpose-oriented controls, in the same Shiny UX worktree.

## Changes

- Peak sampling target distributes the parallel acquisition count and DPPP check across the available row. The sequential layout also spreads its numeric target, percentage slider, and presets across the row.
- Removed the Shiny-only maximum of 10 from `min_isolation_width`. The old UI declared `min = 1, max = 10`; the preceding validation change copied this UI range into preflight. It was not a KDE constraint.
- Preflight now uses the optimizer's `ABSOLUTE_MIN_WIDTH_DA` (1 m/z), with the existing requirement that the minimum be strictly below `max_width_da`. The optimizer and its algorithms are unchanged.
- Validation messages identify their input field and appear directly below its control row. The invalid input is highlighted and associated with the message using `aria-invalid` and `aria-describedby`. Fixing the value removes both the message and its accessibility state.
- Next/Confirm focuses the first invalid input and opens any containing disclosure. Page 1 upload/acquisition errors use the same presentation. The footer gives only a short reminder, rather than repeating distant field-specific messages.
- Background Greedy constraint errors preserve a field identifier when returned from the worker, so automatic-count errors appear beside Total m/z span or Max width. Confirm focuses a known invalid field without rerunning the same failed request. Unattributed computation errors remain next to the preview they prevent.

## Validation

R parsing and the `shiny-intent-controls`, `shiny-live-preview`, `strategy-comparison`, and `method-delivery` test groups cover canonical KDE computation with minimum width 12, lower-bound and min/max conflicts, field identifiers, and confirmed-result preservation.

Desktop browser checks use 12,000 synthetic precursors. They cover both acquisition layouts, inline upload errors, KDE minimum 12, invalid width recovery, automatic Greedy errors, focus, and expansion of a collapsed RT setting when it needs correction.

- [Parallel sampling layout](2026-09-10-inline-validation-assets/02-sampling-balanced.png)
- [KDE minimum width 12](2026-09-10-inline-validation-assets/03-kde-minimum-12.png)
- [Width error beside the controls](2026-09-10-inline-validation-assets/04-width-error-inline.png)
- [Automatic Greedy error beside Total m/z span](2026-09-10-inline-validation-assets/05-worker-error-inline.png)
- [Sequential sampling layout](2026-09-10-inline-validation-assets/06-sequential-sampling.png)
- [Upload error beside the file control](2026-09-10-inline-validation-assets/01-upload-inline.png)
