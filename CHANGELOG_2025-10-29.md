# Changelog - 2025-10-29

## Version 2.1 - Configuration System Refactoring

### 🎯 Major Changes

#### 1. max_windows Migration to Instrument Config
- **Changed**: Moved `max_windows` from user config to instrument hardware spec
- **Location**: `config/optimization_config.json` → `config/instruments.json`
- **Rationale**: Window count limit is hardware constraint, not user preference
- **Files Modified**: 13 total (6 core + 7 config)

#### 2. 22nd Column Generation in Stage 3
- **Changed**: CSV column generation moved to appropriate module
- **Location**: `run_with_config.R` → `R/stage3_window_optimization.R`
- **Rationale**: Stage 3 responsible for complete CSV output
- **Function**: Added `optimization_plan` parameter to `export_windows_to_csv()`

#### 3. Instrument max_windows Values Corrected
- **Orbitrap**: 500 → 150 (realistic sequential limit)
- **Orbitrap Exploris**: 500 → 400
- **Fusion Lumos**: 500 → 300
- **Astral**: 300 (unchanged, narrow-DIA)
- **Note**: Values pending vendor specification verification

### 📝 Configuration Changes

#### Removed from User Configs (7 files)
```json
// REMOVED:
"window_count_constraints": {
  "max_windows": 500
}
```

#### Added to Instrument Config (9 instruments)
```json
// ADDED:
"fusion_lumos": {
  "max_windows": 300,  // Hardware limit
  ...
}
```

### 🔧 Code Changes

#### R/instrument_utils.R
- Added `max_windows` to required fields
- Added validation: 50-1000 range

#### R/stage2_optimization_planning.R
- Removed `max_windows` parameter
- Added: Read from instrument config
```r
max_windows <- instrument_config$max_windows
```

#### R/stage3_window_optimization.R
- Added `optimization_plan` parameter
- Added 22nd column generation:
```r
Recommended_Cycle_Time_Sec = round(recommended_cycle_time, 1)
```

#### R/config_loader.R
- Removed Section 6 (window_count_constraints validation)
- Renumbered subsequent sections

### ✅ Validation

**Test**: `test_refactoring_quick.R`
- Input: 22,047 precursors (30min gradient)
- Instrument: Fusion Lumos (max_windows=300)
- Output: 34 windows, 22 columns ✅
- Cycle time: 1.2 sec (recommended) ✅

### 📚 Documentation

**New**:
- `REFACTORING_SUMMARY.md` - Complete refactoring guide

**Updated**:
- `CLEANUP_SUMMARY.md` - Added refactoring section
- `CHANGELOG_2025-10-29.md` - This file

**Pending**:
- `DEVELOPMENT.md` - Reflect JSON system
- `CLAUDE.md` - Update architecture
- `API_SPECIFICATION.md` - 22-column CSV spec

### 🎯 Next Steps

1. Full pipeline test (24 CSVs)
2. Complete Stage 4 visualization
3. Update remaining documentation
4. Package preparation

---

**Status**: Core Refactoring Complete ✅
**Version**: 2.1
**Date**: 2025-10-29
