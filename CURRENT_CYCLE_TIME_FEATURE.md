# Current Cycle Time Configuration Feature

## Overview

`current_cycle_time` 필드를 설정 파일에 추가하여, 사용자가 DIA-NN 데이터가 수집된 실제 cycle time을 명시할 수 있도록 했습니다. 이 값은 Stage 2 (DPPP Diagnosis)에서 현재 실험 조건의 DPPP 특성을 정확히 분석하는데 사용됩니다.

## Changes Made

### 1. Configuration File Update

**File**: [config/optimization_config.json](config/optimization_config.json)

Added new field under `input_data`:
```json
"input_data": {
  "input_files": [...],
  "current_cycle_time": null,
  "_comment_current_cycle_time": "Current cycle time in seconds (e.g., 1.5). If null, auto-estimated from gradient length. Used for Stage 2 DPPP diagnosis."
}
```

**Behavior**:
- `null` (default): Auto-estimate cycle time from gradient length
  - 30min gradient → 1.2 sec
  - 60min gradient → 1.6 sec
  - 90min gradient → 2.0 sec
- Numeric value (e.g., `1.5`): Use specified cycle time for Stage 2 DPPP diagnosis

### 2. Pipeline Updates

#### run_with_config.R

**Lines 57, 131-138**: Added cycle time handling
```r
# Line 57: Extract from config
current_cycle_time_config <- config$input_data$current_cycle_time  # NULL = auto-estimate

# Lines 131-138: Use config value or auto-estimate
if (!is.null(current_cycle_time_config)) {
  initial_cycle_time <- current_cycle_time_config
  cat(sprintf("Using configured cycle time: %.3f sec\n", initial_cycle_time))
} else {
  initial_cycle_time <- estimate_cycle_time(gradient_name)
  cat(sprintf("Estimated cycle time: %.3f sec (auto-detected from gradient)\n", initial_cycle_time))
}
```

#### main.R

**Lines 30, 46, 73-74, 157-168**: Added cycle time parameter and handling
```r
# Line 30: Added parameter documentation
#' @param current_cycle_time Current cycle time in seconds (NULL = auto-estimate from gradient)

# Line 46: Added parameter to function signature
run_complete_pipeline <- function(
  ...,
  current_cycle_time = NULL,
  ...
)

# Lines 73-74: Display in configuration header
cat(sprintf("  Current cycle time: %s\n",
            ifelse(is.null(current_cycle_time), "Auto-detect", sprintf("%.3f sec", current_cycle_time))))

# Lines 157-168: Use provided value or auto-estimate
if (!is.null(current_cycle_time)) {
  initial_cycle_time <- current_cycle_time
  if (verbose) {
    cat(sprintf("Using provided cycle time: %.3f sec\n", initial_cycle_time))
  }
} else {
  initial_cycle_time <- estimate_cycle_time(gradient_name)
  if (verbose) {
    cat(sprintf("Estimated cycle time: %.3f sec (auto-detected from gradient)\n", initial_cycle_time))
  }
}
```

## Usage Examples

### Example 1: Auto-detection (Default)

**Configuration**: [config/optimization_config.json](config/optimization_config.json)
```json
"input_data": {
  "input_files": ["data/30min_report.parquet"],
  "current_cycle_time": null
}
```

**Output**:
```
Stage 2: Optimization Planning
─────────────────────────────────────────────────────────────
Estimated cycle time: 1.200 sec (auto-detected from gradient)
```

### Example 2: User-Specified Cycle Time

**Configuration**: [config/example_with_cycle_time.json](config/example_with_cycle_time.json)
```json
"input_data": {
  "input_files": ["data/30min_report.parquet"],
  "current_cycle_time": 1.5
}
```

**Output**:
```
Stage 2: Optimization Planning
─────────────────────────────────────────────────────────────
Using configured cycle time: 1.500 sec
```

### Example 3: main.R Direct Function Call

```r
# With auto-detection (default)
results <- run_complete_pipeline(
  data_dir = "data",
  current_cycle_time = NULL  # Auto-detect
)

# With user-specified cycle time
results <- run_complete_pipeline(
  data_dir = "data",
  current_cycle_time = 1.5  # Use 1.5 sec
)
```

## Testing

**Test Script**: [test_cycle_time_config.R](test_cycle_time_config.R)

Run test:
```r
source("test_cycle_time_config.R")
```

This will test both scenarios:
1. Auto-detection mode (null)
2. User-specified mode (1.5 sec)

## Why This Feature Matters

### Stage 2 DPPP Diagnosis Accuracy

Stage 2 calculates the current DPPP distribution and satisfaction ratio using:

```
DPPP = (1.7 × FWHM_seconds) / cycle_time_seconds
```

**Impact of Accurate Cycle Time**:
- ✅ **Correct cycle time** → Accurate DPPP diagnosis → Optimal window count recommendation
- ❌ **Wrong cycle time** → Incorrect DPPP calculation → Suboptimal optimization

**Example**:
```
Given: FWHM = 0.1 minutes = 6 seconds

With cycle_time = 1.2 sec (auto-estimated):
  DPPP = (1.7 × 6) / 1.2 = 8.5

With cycle_time = 1.5 sec (actual):
  DPPP = (1.7 × 6) / 1.5 = 6.8  ← Correct!
```

This difference affects:
1. **Satisfaction ratio calculation** (% of precursors meeting target DPPP)
2. **Window count recommendation** (optimal number of windows per RT bin)
3. **Cycle time feasibility** (whether target satisfaction is achievable)

## Recommendations

1. **Always use actual cycle time when known**
   - Check method file or raw file metadata
   - Instrument method settings
   - DIA-NN processing log

2. **Auto-detection is reasonable for**
   - Initial exploration
   - Standard gradient methods
   - When exact cycle time is unknown

3. **User-specified is critical for**
   - Non-standard methods
   - Custom isolation schemes
   - Validation studies
   - Publication-quality optimization

## Related Files

- [config/optimization_config.json](config/optimization_config.json) - Main configuration
- [config/example_with_cycle_time.json](config/example_with_cycle_time.json) - Example with 1.5 sec
- [run_with_config.R](run_with_config.R) - JSON-based pipeline
- [main.R](main.R) - Direct function call pipeline
- [test_cycle_time_config.R](test_cycle_time_config.R) - Test script

---

**Version**: 1.0
**Date**: 2025-10-31
**Status**: ✅ Complete and Tested
