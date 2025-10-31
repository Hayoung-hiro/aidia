# Scripts - Development & Analysis Tools

**Purpose**: Development, analysis, diagnostic, and experimental scripts

**Status**: Development/Testing (Not Production-Ready)

---

## 📁 Folder Structure

### `analysis/` - Data Analysis Scripts (4 files)

One-off analysis scripts for exploring data characteristics and algorithm behavior.

**Scripts**:
- `analyze_fwhm_detailed.R` - Detailed FWHM distribution analysis
- `analyze_fwhm_simple.R` - Simple FWHM statistics
- `analyze_report.R` - DIA-NN report analysis
- `dppp_threshold_analysis.R` - DPPP threshold investigation

**Usage**: Ad-hoc analysis, not part of production pipeline

---

### `diagnostics/` - Diagnostic Utilities (8 files)

Tools for diagnosing issues, validating calculations, and comparing approaches.

**Scripts**:
- `calc_required_ct_70.R` - Calculate required cycle time for 70% satisfaction
- `compare_instruments.R` - Compare instrument configurations
- `diagnose_dppp_complete.R` - Complete DPPP diagnostic
- `diagnose_dppp_fixed_cycle.R` - Fixed cycle time DPPP analysis
- `diagnose_satisfaction_70.R` - Satisfaction ratio diagnostics
- `diagnose_window_count.R` - Window count calculation diagnostics
- `trace_modules.R` - Module execution tracing
- `workflow_validation_fixes.R` - Workflow validation and fixes

**Usage**: Debugging, validation, troubleshooting

---

### `experimental/` - Experimental Pipelines (6 files)

Alternative pipeline implementations and experimental workflows.

**Scripts**:
- `run_complete_test.R` - Complete test pipeline
- `run_comprehensive_pipeline.R` - Comprehensive workflow variant
- `run_dppp_optimized_pipeline.R` - DPPP-optimized workflow
- `run_full_pipeline.R` - Full pipeline variant
- `run_integrated_pipeline.R` - Integrated workflow
- `run_refactored_batch.R` - Refactored batch processing

**Usage**: Experimental features, alternative approaches, testing variants

**Note**: These may be outdated or superseded by `run_with_config.R`

---

## 🚫 Not for Production Use

These scripts are:
- ❌ Not maintained for production use
- ❌ May use outdated APIs or deprecated functions
- ❌ May not follow current architecture (JSON config system)
- ✅ Useful for development and debugging
- ✅ May contain useful code snippets or approaches

## ✅ Production Alternative

For production workflows, use:
- **Main entry point**: `../run_with_config.R`
- **Quick test**: `../test_refactoring_quick.R`
- **Configuration**: `../configure_pipeline.R`
- **Validation**: `../validate_config.R`

---

**Last Updated**: 2025-10-29
**Version**: 2.1
