# aidia 0.5.0 integration

The approved Shiny UX work is integrated with development commit `a5caa53`
(`Hayoung-hiro/AIDIA-main`), including `c7c9ebb`'s original fixed-method baseline
and export charge settings. The UX checkpoint before integration is `579ee32`,
following the live-preview commit `29aab8e`.

## Conflict resolution

- Kept the compact page layouts, live preview controller, contextual validation,
  and confirmed-result delivery from the UX branch.
- Moved original-method construction into the shared snapshot computation used by
  the preview worker. Both the plan and windows retain the same original method,
  including input m/z bounds, count, acquisition controls, and timing.
- Added the original m/z inputs to Prepare's acquisition section and immutable
  request settings. Invalid boundaries are reported next to those inputs.
- Retained the latest original-method summary and baseline temporal-density plot.
- Kept Thermo charge in single-file and ZIP exports and made its example row
  reflect the selected charge.
- Preserved the latest branch's scientific, plotting, export, and research changes.
  The Shiny adapter still calls canonical package functions.
- Corrected the namespace audit to inspect parsed code: explicit `aidia:::`
  references are permitted; bare internal references remain detected even when
  the same symbol also appears in a qualified call.

## Release validation

- Full test suite: **1,407 passed, 0 failures, 0 errors, 4 skipped**. Skips are the
  unavailable CSV example and real-data/baseline fixtures. Existing deprecation
  and package-build-version warnings remain.
- R source parsing and package installation passed.
- Installed-package smoke test loaded the Shiny app and computed the live RT-m/z
  preview with a saved fixed baseline using `library(aidia)`, without `pkgload`.
- Desktop Edge with 12,000 synthetic precursors: version 0.5.0, original range
  450-1050 with 30 windows, saved reference width 20, charge 1/3, unchanged CSV
  columns except z, ZIP parity, preserved confirmed reference after edits, and
  new reference after reconfirmation all passed.

## Continued development

Keep `Hayoung-hiro/shiny-workflow-ux` and its worktree for UX work. A worktree has
its own branch and files; moving main does not disconnect it or update it
automatically. Merge new main commits into this branch before the next integration
and rerun checks where UX and functional changes meet. Commit reviewed milestones
back to main; do not delete or re-create the UX checkout after each merge.

`DESCRIPTION` is version 0.5.0; `NEWS.md` records the UX and integrated method updates.

- [Original-method inputs](2026-09-10-release-050-assets/01-original-method-input.png)
- [Confirmed baseline and charge](2026-09-10-release-050-assets/02-confirmed-baseline-and-charge.png)
- [Reference after reconfirmation](2026-09-10-release-050-assets/03-reconfirmed-baseline.png)
