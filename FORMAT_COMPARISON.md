# Module 3D Format Comparison: Legacy vs Thermo Fusion Lumos

## Summary
Module 3D has been updated to support the **Thermo Fusion Lumos** instrument format while maintaining backward compatibility with the legacy format.

## Key Changes

### Function Signature Update
```r
export_windows_to_csv(
  window_result,
  output_file,
  instrument_type = "astral",
  strategy = "unknown",
  include_metadata = TRUE,
  format = "thermo",        # NEW: "thermo" or "legacy"
  agc_target = 800          # NEW: AGC target for Thermo format
)
```

## Format Comparison

### Thermo Fusion Lumos Format (NEW - Default)

**Primary Columns (Required for instrument):**
| Column | Value | Description |
|--------|-------|-------------|
| `Compound` | "" | Empty for DIA |
| `Formula` | "" | Empty for DIA |
| `Adduct` | "(no adduct)" | Standard for DIA |
| `m/z` | 405.0 | **CENTER** of isolation window |
| `z` | 1 | Charge state |
| `t start (min)` | 0.0 | RT start time |
| `t stop (min)` | 90.0 | RT stop time |
| `Isolation Window (m/z)` | 10.0 | Window width |
| `Normalized AGC Target (%)` | 800 | AGC setting |

**Metadata Columns (Preserved for analysis):**
- `Start (m/z)` - Window start m/z
- `End (m/z)` - Window end m/z
- `Window_ID` - Unique identifier
- `RT_Segment_ID` - RT bin identifier
- `RT_Center` - RT midpoint
- `RT_Width` - RT duration
- `N_Precursors` - Precursor count
- `Overlap_Prev/Next` - Overlap flags
- `Instrument` - Instrument type
- `Generation_Method` - Strategy used
- `Window_Type` - Fixed/Variable

### Legacy Format (Backward Compatible)

**Column Order:**
```
Window_ID, RT_Segment_ID, RT_Start, RT_End, RT_Center, RT_Width,
Start, End, Center, Width, N_Precursors, Overlap_Prev, Overlap_Next,
Instrument, Generation_Method, Window_Type
```

## Example Output Comparison

### Thermo Format (First Row)
```csv
Compound,Formula,Adduct,m/z,z,t start (min),t stop (min),Isolation Window (m/z),Normalized AGC Target (%),...
,,(no adduct),405,1,0,90,10,800,...
```

### Legacy Format (First Row)
```csv
Window_ID,RT_Segment_ID,RT_Start,RT_End,RT_Center,RT_Width,Start,End,Center,Width,...
1,1,0,45,22.5,45,400,410,405,10,...
```

## Important Notes

### m/z Column Represents CENTER
The `m/z` column in Thermo format represents the **CENTER** of the isolation window, not the start:
- Window at m/z = 405 with width = 10
- Actual range: [400, 410] m/z
- This is the standard DIA window definition

### Default Format Change
- **New default**: `format = "thermo"` for instrument compatibility
- **Legacy support**: Use `format = "legacy"` for backward compatibility
- All existing pipelines should be reviewed for format compatibility

### AGC Target
- Default: 800% (standard for Orbitrap DIA)
- Adjustable via `agc_target` parameter
- Instrument-specific optimization may be needed

## Usage Examples

### Export for Thermo Instrument
```r
# Default behavior - Thermo format
export_windows_to_csv(
  window_result = stage3d_result,
  output_file = "method.csv"
)
```

### Export Legacy Format
```r
# Explicit legacy format for analysis tools
export_windows_to_csv(
  window_result = stage3d_result,
  output_file = "analysis.csv",
  format = "legacy"
)
```

### Custom AGC Target
```r
# Adjust AGC for specific experiments
export_windows_to_csv(
  window_result = stage3d_result,
  output_file = "method_high_agc.csv",
  agc_target = 1000
)
```

## Testing Results

✅ All required Thermo columns present
✅ Column order matches instrument requirements
✅ Value formatting correct (1 decimal place)
✅ Backward compatibility maintained
✅ Metadata preserved for downstream analysis

## Files Modified

- `R/stage3_window_optimization/module3d_window_generation.R`
  - `export_windows_to_csv()` - Added format parameter and Thermo format support
  - `export_all_results_to_csv()` - Updated to pass format parameter

## Test Files Created

- `test_thermo_format.R` - Comprehensive format testing
- `test_output_thermo.csv` - Example Thermo format output
- `test_output_legacy.csv` - Example legacy format output

---

**Status**: ✅ Complete and tested
**Date**: 2025-10-24
**Version**: Module 3D v2.0 (Thermo Format Support)