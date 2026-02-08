# Development Tests

**Purpose**: Active development test scripts for various features and modules

**Status**: Development/Testing (Not Production-Ready)

---

## 📋 Test Categories

### Pipeline Tests (6 files)
- `test_complete_pipeline.R` - Complete end-to-end pipeline
- `test_final_workflow.R` - Final workflow validation
- `test_modules_1_2_3.R` - Modules 1, 2, 3 integration
- `test_redesigned_modules.R` - Redesigned module tests
- `test_refactored_workflow.R` - Refactored workflow tests
- `test_integration_mock.R` - Mock integration testing

### Data & Export Tests (3 files)
- `test_csv_export.R` - CSV export functionality
- `test_raw_metadata_integration.R` - Raw file metadata integration
- `test_thermo_format.R` - Thermo method file format

### Real Data Tests (3 files)
- `test_real_data.R` - Real data processing
- `test_real_data_8windows.R` - 8-window configuration test
- `test_real_data_8windows_simplified.R` - Simplified 8-window test

### Module-Specific Tests (4 files)
- `test_dppp_score_correlation.R` - DPPP score correlation analysis
- `test_scan_time_recommendation.R` - Scan time recommendation logic
- `test_window_generation.R` - Window generation algorithms
- `test_stage4_real_data.R` - Stage 4 visualization with real data

### Visualization Tests (2 files)
- `test_fwhm_visualization.R` - FWHM visualization
- `test_heatmap_simple.R` - Simple heatmap generation

---

## 🎯 Test Status

These tests are:
- 🔄 **Active development** - May be updated frequently
- ⚠️ **Not production tests** - Use for feature development
- 📊 **Varied quality** - Some may be outdated
- 🧪 **Experimental** - Testing new features and approaches

## ✅ Production Test

For production validation, use:
- **Quick smoke test**: `../../test_refactoring_quick.R`
- **Full pipeline test**: `../../run_with_config.R` (with test config)

## 📝 Notes

- Some tests may use deprecated APIs or old module names
- Tests may not follow current JSON configuration system
- Useful for understanding feature evolution and edge cases
- May contain valuable test scenarios for future formal test suite

---

**Last Updated**: 2025-10-29
**Version**: 2.1
