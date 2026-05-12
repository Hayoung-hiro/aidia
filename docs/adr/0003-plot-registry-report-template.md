# Plot Registry with Report Templates

Refactored `generate_visualizations()` (v0.4.1) from a 437-line imperative
plot-generation function into a registry-driven dispatcher.
`R/plot_registry.R` defines `PLOT_REGISTRY` (one entry per plot or
multi-strategy template) and `REPORT_TEMPLATES` (`full`, `minimal`). The
orchestrator filters entries by template, builds a lazy
`build_visualization_context()` that computes only the prerequisites the
selected entries declare, then loops over entries with S3-style dispatch
on each entry's `generate(ctx)` closure.

Multi-strategy plots (`app_b_<strategy>_*`) use `expand_over = "strategies"`
to expand dynamically based on `ctx$windows_list` keys, so a user running
only 3 strategies produces 3 plots per template instead of 5.

The new `report_template = "full"` parameter (default) preserves identical
output to v0.4.0 — all 44 baseline plot keys, byte-equivalent generation.
The `"minimal"` template selects 7 essential plots and runs in ~12 seconds
versus ~42 seconds for `"full"` (~70% faster), enabling responsive Shiny
preview workflows that previously required the full pipeline.

## Rejected alternative — pure imperative orchestrator

The simpler alternative was to leave plot generation in the orchestrator
and add an `if (report_template == "minimal")` guard around each plot.
We rejected it because the conditional logic would multiply with each new
template, the section codes embedded in plot keys would remain duplicated
across `generate_visualizations()` and `create_pdf_report()`, and adding
a new plot would still require touching the orchestrator. The registry
makes "add a plot" a single insertion into `PLOT_REGISTRY`.

## Backward compatibility

`generate_visualizations()` retains its full v0.4.0 signature; the new
`report_template` parameter defaults to `"full"`. main.R, the Shiny app,
and any external caller continue to produce identical output. The PDF
assembly in `create_pdf_report()` consumes the `plots` list by key, so
key naming is preserved — `s1_*`, `s2_*`, `s3_*`, `app_a_*`, `app_b_*`,
`app_d_*` continue to work unchanged.

## `requires` is "compute", not "block"

A subtle design point: `entry$requires` lists prerequisites that
`build_visualization_context()` should compute, but it does NOT block
plot generation when those fields end up `NULL` (e.g., when
`evaluate_windows()` fails). To express a hard requirement, set
`when = function(ctx) !is.null(ctx$some_field)` explicitly. This keeps
`plot_temporal_density()` callable with `baseline_density = NULL` (the
plot has a graceful fallback) while still triggering its computation
when possible.
