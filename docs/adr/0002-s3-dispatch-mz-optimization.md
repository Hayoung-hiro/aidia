# Use S3 dispatch with GLOBAL/LOCAL hierarchy for m/z optimization strategies

Refactored `optimize_mz_ranges()` (v0.4.1) from a flat `if/else` dispatcher with
30+ unpacked parameters into an S3 generic with two intermediate classes
(`global_strategy_config`, `local_strategy_config`) under a parent
`strategy_config` class. GLOBAL strategies (greedy, kde) override
`optimize_mz_ranges` directly; LOCAL strategies (quantile, coverage, outlier)
inherit per-RT-bin iteration from the LOCAL parent method and only implement
`compute_mz_range_for_bin()`. Smoothing is extracted as a separate
`apply_smoothing()` S3 generic with no-op methods for kde and coverage
(which do not support boundary smoothing).

This eliminates the strategy-prefixed field-name workaround
(`greedy_apply_smoothing` / `quantile_apply_smoothing` /
`outlier_apply_smoothing` all unified through dispatch) and makes adding a new
LOCAL strategy require exactly two additions: an `xxx_config()` constructor
and a `compute_mz_range_for_bin.xxx_config()` method.

## Rejected alternative — flat 5-method dispatch (no GLOBAL/LOCAL hierarchy)

The simpler alternative was five sibling `optimize_mz_ranges.X_config()`
methods with no intermediate class. We rejected it because LOCAL strategies
share the per-bin iteration scaffolding (empty-bin fallback, coverage
recalculation, result assembly); without the hierarchy that scaffolding would
be duplicated three times. The 2-level hierarchy earns its keep when a fourth
LOCAL strategy is added: the new method only contains the strategy-specific
m/z bound computation, not the loop.

## Backward compatibility

`optimize_windows()` retains the flat-parameter API and emits
`.Deprecated()` when called without an explicit `strategy_config`. Flat
parameters are scheduled for removal in v0.6.0. Callers (main.R, Shiny app,
external scripts) continue to work unchanged until then.
