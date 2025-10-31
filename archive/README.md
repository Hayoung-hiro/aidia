# Archive - Historical & Deprecated Code

**Purpose**: Preserve deprecated and legacy code for reference

**Status**: 🗄️ Archived (Not for Use)

---

## 📁 Folder Structure

### `deprecated_modules/` - Replaced by Refactored Code

Code that was **replaced during v2.1 refactoring** (JSON configuration system).

#### `deprecated_modules/R/` (12 files)

**Replaced by `stage2_optimization_planning.R`**:
- `stage2_dppp_diagnosis.R` - Old Stage 2 (DPPP diagnosis only)
- `dppp_analyzer_enhanced.R` - Enhanced DPPP analyzer
- `dppp_score_analysis.R` - DPPP score analysis
- `fwhm_analyzer.R` - Standalone FWHM analyzer
- `fwhm_visualization.R` - Standalone FWHM visualization

**Superseded modules**:
- `dppp_calculator_backup.R` - Backup of DPPP calculator
- `smoothing_utils.R` - Old smoothing utilities
- `user_config_generator.R` - Pre-JSON config generator
- `utils.R` - Legacy utilities (replaced by utils_common.R)
- `optimizer.R` - Old optimizer
- `dynamicDIA_example.R` - Example script (not a module)
- `raw_metadata_extractor.R` - Old version (use _improved)

#### `deprecated_modules/config/` (1 file)

- `instruments.R` - **R-based config** (replaced by `config/instruments.json`)

**Deprecation Reason**: v2.1 introduced JSON configuration system and refactored Stage 2 to integrate DPPP diagnosis with window count determination.

---

### `legacy_scripts/` - Pre-JSON Configuration Era (7 files)

Scripts from **before v2.1 JSON configuration system**.

**Old Entry Points**:
- `main.R` - Old main entry point (replaced by `run_with_config.R`)
- `user_verification_script.R` - Old user workflow
- `example_full_workflow.R` - Old example workflow

**Old Configuration System**:
- `user_config.R` - Hard-coded user configuration
- `user_config_custom.R` - Custom configuration variant

**Old Utilities**:
- `view_results.R` - Simple result viewer
- `create_test_data.R` - Test data generator

**Deprecation Reason**: Moved to JSON-based configuration for better version control, validation, and user experience.

---

## ⚠️ Important Notes

### Do NOT Use This Code

This code is archived for:
- ✅ **Reference**: Understanding evolution of the codebase
- ✅ **Documentation**: Historical context for design decisions
- ✅ **Recovery**: Emergency recovery if needed
- ❌ **Not for production**: Outdated, unsupported, may have bugs
- ❌ **Not maintained**: No updates or fixes

### Modern Alternatives

| Archived Code | Modern Alternative |
|---------------|-------------------|
| `stage2_dppp_diagnosis.R` | `R/stage2_optimization_planning.R` |
| `instruments.R` | `config/instruments.json` |
| `main.R` | `run_with_config.R` |
| `user_config.R` | `config/optimization_config.json` |
| `utils.R` | `R/utils_common.R` |

### Key Changes in v2.1

1. **Configuration System**:
   - Old: R scripts with hard-coded values
   - New: JSON files with validation

2. **Stage 2 Architecture**:
   - Old: Separate DPPP diagnosis (stage2_dppp_diagnosis.R)
   - New: Integrated DPPP + window count (stage2_optimization_planning.R)

3. **Hardware Specifications**:
   - Old: Mixed in user config or R scripts
   - New: Centralized in instruments.json

4. **CSV Output**:
   - Old: 21 columns, cycle time added in main script
   - New: 22 columns, complete in stage3 module

---

## 🔍 If You Need This Code

**Contact**: Project maintainer before using any archived code

**Alternatives**:
1. Check if feature exists in current production code
2. Review REFACTORING_SUMMARY.md for changes
3. Submit feature request if functionality is missing

---

**Archived Date**: 2025-10-29
**Superseded By**: Version 2.1 (JSON Configuration + Refactored Architecture)
**Retention Policy**: Keep indefinitely for historical reference
