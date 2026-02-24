# Scripts - Development & Analysis Tools

**Purpose**: Development, analysis, and utility scripts

**Status**: Development/Testing (Not Production-Ready)

---

## Current Contents

### `dev/` - Development Scripts
- `review_stage4_plots.R` - Review Stage 4 plot outputs

### `utils/` - Utility Scripts
- `validate_window_optimization.R` - Window optimization validation
- `verify_dppp_calculation.R` - DPPP calculation verification

### Root Scripts
- `config_builder.R` - Interactive pipeline builder (legacy)

---

## Production Alternative

For production workflows, use the R package API:
```r
library(aidia)
results <- run_complete_pipeline(data_dir = "data", ...)
```

Or the Shiny app:
```r
aidia::run_aidia_app()
```

---

**Last Updated**: 2026-02-24
**Version**: 3.0
