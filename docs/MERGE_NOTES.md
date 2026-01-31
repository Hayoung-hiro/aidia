# Branch Merge Notes

## Quality Score Feature DEPRECATED (v2.3)

### Deprecation Reason

Quality Score was removed because it measured **method configuration metrics**, not **actual DIA analysis quality**.

The tool generates MS methods, and the actual analysis quality (precursor IDs, quantification CV%, etc.) can only be determined by:
1. Running the DIA method on the instrument
2. Analyzing with DIA-NN
3. Comparing results

A score based on window configuration characteristics was misleading - it could suggest one strategy is "better" than another when actual performance depends on the sample and experimental conditions.

### Replacement: Strategy Characteristics

Instead of evaluative scoring, we now provide **descriptive characteristics**:

| Old (Quality Score) | New (Strategy Characteristics) |
|---------------------|--------------------------------|
| "Quality Score: 81.4%" | Window width: mean 25.3 Da, CV 15% |
| "Coverage: 98%" | Precursors per window: mean 45, range 12-120 |
| "Uniformity: Good" | Flags: uniform_widths=TRUE, balanced_precursors=TRUE |
| Evaluative judgment | Factual description |

### Files Changed

| File | Change Type | Description |
|------|-------------|-------------|
| `R/stage3/stage3_quality_score.R` | **DEPRECATED** | Delete or archive |
| `R/plots/plot_quality_score.R` | **DEPRECATED** | Delete or archive |
| `tests/manual/test_quality_score.R` | **DEPRECATED** | Delete or archive |
| `R/stage3/stage3_strategy_characteristics.R` | **NEW** | Descriptive metrics (replacement) |
| `R/stage3_window_optimization.R` | MODIFIED | Uses strategy_characteristics instead |
| `R/stage4_visualization.R` | MODIFIED | Plot 9 (Quality Score) removed |
| `shiny_app/app.R` | MODIFIED | Quality Score display removed |

### New Functions

```r
# R/stage3/stage3_strategy_characteristics.R
calculate_strategy_characteristics(windows, precursor_data, strategy)
generate_strategy_comparison(characteristics_list)
print_strategy_characteristics(characteristics, verbose)
get_strategy_description(strategy)
```

### Usage Example

```r
# After optimize_windows()
result <- optimize_windows(validated_data, plan, mz_strategy = "quantile")

# Access strategy characteristics (descriptive, not evaluative)
chars <- result$strategy_characteristics

# Window width info
chars$width_characteristics$mean_da  # 25.3
chars$width_characteristics$cv_pct   # 15.2

# Precursor distribution
chars$precursor_distribution$mean_per_window  # 45.2
chars$precursor_distribution$cv_pct           # 32.1

# Descriptive flags (not quality judgments)
chars$flags$uniform_widths        # TRUE
chars$flags$balanced_precursors   # TRUE
```

---

## Auto IT Mode Feature (feat: 8c0b8cf, fbfab5f)

### Overview
Orbitrap Auto IT (Sweet Spot) mode default + Custom IT override UI.

### Files Changed

| File | Change Type | Description |
|------|-------------|-------------|
| `config/instruments.json` | MODIFIED | All Orbitrap presets `ms2_time: "auto"` |
| `R/stage2_optimization_planning.R` | MODIFIED | `ms2_time_override` parameter added |
| `R/instrument_utils.R` | MODIFIED | Efficiency calculation functions |
| `shiny_app/app.R` | MODIFIED | Custom IT override UI |

### Key Functions

```r
# R/instrument_utils.R
calculate_ms2_scan_time(resolution, injection_time_ms, ...)
generate_efficiency_report(resolution, current_it_ms, analyzer, language)
resolve_injection_time(ms2_time, resolution, analyzer)
```

---

## Merge Strategy

### Recommended Order

1. **First**: Auto IT Mode (`8c0b8cf`, `fbfab5f`)
   - Infrastructure change, merge first

2. **Second**: Quality Score deprecation (current changes)
   - Delete Quality Score files
   - Add Strategy Characteristics

### Files to Delete

These files are deprecated and should be deleted:
- `R/stage3/stage3_quality_score.R`
- `R/plots/plot_quality_score.R`
- `tests/manual/test_quality_score.R`

---

## Test Commands

```bash
# Test Strategy Characteristics
Rscript -e "source('R/stage3_window_optimization.R'); print('Strategy characteristics loaded')"

# Full pipeline test
Rscript tests/manual/test_full_pipeline.R

# Analyzer types test
Rscript tests/manual/test_analyzer_types.R
```
