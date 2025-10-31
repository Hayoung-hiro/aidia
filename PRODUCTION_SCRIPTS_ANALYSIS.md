# Production Scripts Analysis & Folder Organization Plan

**Date**: 2025-10-29
**Purpose**: Identify production-ready scripts and organize project structure

---

## 📊 Current State Analysis

### Statistics
- **Root folder**: 47 R scripts
- **R/ folder**: 27 R scripts
- **Total**: 74 R scripts
- **Status**: Highly cluttered, needs organization

---

## 🎯 Production-Ready Scripts (Core System v2.1)

### 1. **Core Pipeline Modules** (R/ folder) - ✅ Production Ready

#### Stage 1: Data Validation
- ✅ `R/stage1_data_validation.R` - Main Stage 1 module
- ✅ `R/data_loader.R` - DIA-NN data loading
- ✅ `R/raw_metadata_extractor_improved.R` - Raw file metadata (optional)

#### Stage 2: Optimization Planning
- ✅ `R/stage2_optimization_planning.R` - **Main Stage 2 module (Refactored v2.1)**
  - Integrates DPPP diagnosis + window count determination
  - Uses JSON configuration system
  - Reads max_windows from instruments.json

#### Stage 3: Window Optimization
- ✅ `R/stage3_window_optimization.R` - **Main Stage 3 module (Refactored v2.1)**
  - Generates complete 22-column CSV
  - Includes Recommended_Cycle_Time_Sec
  - 4 m/z strategies × 2 window modes

#### Stage 4: Visualization & Reporting
- ✅ `R/stage4_visualization.R` - Main Stage 4 module
- 🟡 `R/visualizer.R` - Helper functions (legacy, may need update)

#### Supporting Modules
- ✅ `R/utils_common.R` - Common utilities (validation, UI, stats)
- ✅ `R/dppp_calculator.R` - DPPP calculation engine
- ✅ `R/rt_segmentation.R` - RT binning (time-based)
- ✅ `R/window_generator.R` - Variable window generation
- ✅ `R/dynamicDIA.R` - Smoothing algorithms (Savitzky-Golay)
- ✅ `R/method_writer.R` - Method file export

#### Configuration System
- ✅ `R/config_loader.R` - JSON config loader & validator
- ✅ `R/instrument_utils.R` - Instrument config management
- ✅ `config/instruments.json` - Hardware specifications (NEW v2.1)

**Total Production Modules**: 15 files

---

### 2. **Main Entry Points** (Root folder) - ✅ Production Ready

#### Primary Workflow
- ✅ `run_with_config.R` - **Main production script**
  - Batch processing with JSON config
  - Generates 3 files × 4 strategies × 2 modes = 24 CSVs
  - Production-ready orchestration

#### Configuration Management
- ✅ `validate_config.R` - Config file validator
- ✅ `configure_pipeline.R` - Interactive config generator

#### Quick Testing
- ✅ `test_refactoring_quick.R` - Quick verification script
  - Validates refactored system
  - Single file × single strategy × single mode
  - Good for smoke testing

**Total Production Entry Points**: 4 files

---

## 🔧 Development/Testing Scripts (To Be Organized)

### 3. **Legacy/Deprecated Modules** (R/ folder) - 🗄️ Archive

These were replaced by refactored Stage 2:

- 🗄️ `R/stage2_dppp_diagnosis.R` - Replaced by stage2_optimization_planning.R
- 🗄️ `R/dppp_analyzer_enhanced.R` - Legacy analyzer
- 🗄️ `R/dppp_score_analysis.R` - Old scoring system
- 🗄️ `R/fwhm_analyzer.R` - Standalone FWHM analysis
- 🗄️ `R/fwhm_visualization.R` - Standalone visualization
- 🗄️ `R/dppp_calculator_backup.R` - Backup copy

**Action**: Move to `archive/deprecated_modules/`

---

### 4. **Development/Testing Scripts** (Root folder) - 📦 Development

#### Test Scripts (Active Development)
- 📦 `test_complete_pipeline.R`
- 📦 `test_csv_export.R`
- 📦 `test_dppp_score_correlation.R`
- 📦 `test_final_workflow.R`
- 📦 `test_fwhm_visualization.R`
- 📦 `test_heatmap_simple.R`
- 📦 `test_integration_mock.R`
- 📦 `test_modules_1_2_3.R`
- 📦 `test_raw_metadata_integration.R`
- 📦 `test_real_data.R`
- 📦 `test_real_data_8windows.R`
- 📦 `test_real_data_8windows_simplified.R`
- 📦 `test_redesigned_modules.R`
- 📦 `test_refactored_workflow.R`
- 📦 `test_scan_time_recommendation.R`
- 📦 `test_stage4_real_data.R`
- 📦 `test_thermo_format.R`
- 📦 `test_window_generation.R`

**Action**: Move to `tests/development/`

#### Analysis Scripts (One-off Analysis)
- 📦 `analyze_fwhm_detailed.R`
- 📦 `analyze_fwhm_simple.R`
- 📦 `analyze_report.R`
- 📦 `dppp_threshold_analysis.R`

**Action**: Move to `scripts/analysis/`

#### Pipeline Variants (Experimental)
- 📦 `run_complete_test.R`
- 📦 `run_comprehensive_pipeline.R`
- 📦 `run_dppp_optimized_pipeline.R`
- 📦 `run_full_pipeline.R`
- 📦 `run_integrated_pipeline.R`
- 📦 `run_refactored_batch.R`

**Action**: Move to `scripts/experimental/`

#### Diagnostic/Utility Scripts
- 📦 `calc_required_ct_70.R`
- 📦 `compare_instruments.R`
- 📦 `diagnose_dppp_complete.R`
- 📦 `diagnose_dppp_fixed_cycle.R`
- 📦 `diagnose_satisfaction_70.R`
- 📦 `diagnose_window_count.R`
- 📦 `trace_modules.R`
- 📦 `workflow_validation_fixes.R`

**Action**: Move to `scripts/diagnostics/`

#### Old/Legacy Scripts
- 🗄️ `main.R` - Old entry point (before JSON system)
- 🗄️ `user_verification_script.R` - Old workflow
- 🗄️ `user_config.R` - Old config system
- 🗄️ `user_config_custom.R` - Old config system
- 🗄️ `view_results.R` - Simple viewer
- 🗄️ `create_test_data.R` - Test data generator
- 🗄️ `example_full_workflow.R` - Old example

**Action**: Move to `archive/legacy_scripts/`

#### Supporting R/ Scripts (Utility)
- 📦 `R/smoothing_utils.R` - Utility functions
- 📦 `R/user_config_generator.R` - Old config generator
- 📦 `R/utils.R` - Legacy utilities (check if still used)
- 📦 `R/optimizer.R` - Old optimizer (check if deprecated)
- 📦 `R/dynamicDIA_example.R` - Example script
- 📦 `R/raw_metadata_extractor.R` - Old version (use _improved)

**Action**: Review and move to appropriate folders

---

## 📁 Proposed Folder Structure

```
dia_window_optimizer/
├── R/                              # ✅ PRODUCTION Core Modules (15 files)
│   ├── stage1_data_validation.R
│   ├── stage2_optimization_planning.R
│   ├── stage3_window_optimization.R
│   ├── stage4_visualization.R
│   ├── config_loader.R
│   ├── instrument_utils.R
│   ├── data_loader.R
│   ├── dppp_calculator.R
│   ├── rt_segmentation.R
│   ├── window_generator.R
│   ├── dynamicDIA.R
│   ├── method_writer.R
│   ├── raw_metadata_extractor_improved.R
│   ├── utils_common.R
│   └── visualizer.R
│
├── config/                         # ✅ PRODUCTION Configuration
│   ├── instruments.json
│   ├── optimization_config.json
│   ├── optimization_config_template.json
│   ├── test_config.json
│   └── presets/
│       ├── quant_mode_85pct.json
│       ├── id_mode_70pct.json
│       ├── fusion_lumos_standard.json
│       └── astral_narrow_dia.json
│
├── scripts/                        # 🆕 Development & Analysis Scripts
│   ├── analysis/                   # Analysis scripts
│   │   ├── analyze_fwhm_detailed.R
│   │   ├── analyze_fwhm_simple.R
│   │   ├── analyze_report.R
│   │   └── dppp_threshold_analysis.R
│   │
│   ├── diagnostics/                # Diagnostic utilities
│   │   ├── calc_required_ct_70.R
│   │   ├── compare_instruments.R
│   │   ├── diagnose_dppp_complete.R
│   │   ├── diagnose_dppp_fixed_cycle.R
│   │   ├── diagnose_satisfaction_70.R
│   │   ├── diagnose_window_count.R
│   │   ├── trace_modules.R
│   │   └── workflow_validation_fixes.R
│   │
│   └── experimental/               # Experimental pipeline variants
│       ├── run_complete_test.R
│       ├── run_comprehensive_pipeline.R
│       ├── run_dppp_optimized_pipeline.R
│       ├── run_full_pipeline.R
│       ├── run_integrated_pipeline.R
│       └── run_refactored_batch.R
│
├── tests/                          # Testing scripts
│   ├── development/                # Active development tests
│   │   ├── test_complete_pipeline.R
│   │   ├── test_csv_export.R
│   │   ├── test_dppp_score_correlation.R
│   │   ├── test_final_workflow.R
│   │   ├── test_fwhm_visualization.R
│   │   ├── test_heatmap_simple.R
│   │   ├── test_integration_mock.R
│   │   ├── test_modules_1_2_3.R
│   │   ├── test_raw_metadata_integration.R
│   │   ├── test_real_data.R
│   │   ├── test_real_data_8windows.R
│   │   ├── test_real_data_8windows_simplified.R
│   │   ├── test_redesigned_modules.R
│   │   ├── test_refactored_workflow.R
│   │   ├── test_scan_time_recommendation.R
│   │   ├── test_stage4_real_data.R
│   │   ├── test_thermo_format.R
│   │   └── test_window_generation.R
│   │
│   └── mocks/                      # Mock data generators
│       └── (existing mock files)
│
├── archive/                        # 🗄️ Historical/Deprecated
│   ├── deprecated_modules/         # Replaced by refactored code
│   │   ├── R/
│   │   │   ├── stage2_dppp_diagnosis.R
│   │   │   ├── dppp_analyzer_enhanced.R
│   │   │   ├── dppp_score_analysis.R
│   │   │   ├── fwhm_analyzer.R
│   │   │   ├── fwhm_visualization.R
│   │   │   ├── dppp_calculator_backup.R
│   │   │   ├── smoothing_utils.R
│   │   │   ├── user_config_generator.R
│   │   │   ├── utils.R
│   │   │   ├── optimizer.R
│   │   │   ├── dynamicDIA_example.R
│   │   │   └── raw_metadata_extractor.R
│   │   └── config/
│   │       └── instruments.R
│   │
│   └── legacy_scripts/             # Pre-JSON configuration era
│       ├── main.R
│       ├── user_verification_script.R
│       ├── user_config.R
│       ├── user_config_custom.R
│       ├── view_results.R
│       ├── create_test_data.R
│       └── example_full_workflow.R
│
├── examples/                       # 📦 Example workflows
│   └── raw_metadata_workflow_example.R
│
├── docs/                           # 📚 Documentation
├── data/                           # 📊 Test data
├── plots/                          # 📈 Output plots
│
├── run_with_config.R               # ✅ PRODUCTION Main entry point
├── validate_config.R               # ✅ PRODUCTION Config validator
├── configure_pipeline.R            # ✅ PRODUCTION Config generator
├── test_refactoring_quick.R        # ✅ PRODUCTION Quick smoke test
│
├── README.md                       # Main documentation
├── DEVELOPMENT.md                  # Development guide
├── CLAUDE.md                       # Claude Code guidance
├── REFACTORING_SUMMARY.md          # Latest refactoring
├── CLEANUP_SUMMARY.md              # Cleanup & refactoring history
└── CHANGELOG_2025-10-29.md         # Recent changes
```

---

## 🎯 Production-Ready Script Summary

### Core System (v2.1 - JSON Configuration + Refactored)

**Main Entry Points** (4 files):
1. ✅ `run_with_config.R` - Batch processing with JSON config
2. ✅ `validate_config.R` - Config validation
3. ✅ `configure_pipeline.R` - Interactive setup
4. ✅ `test_refactoring_quick.R` - Quick smoke test

**Core Modules** (15 files in R/):
1. ✅ `stage1_data_validation.R` - Stage 1: Data validation
2. ✅ `stage2_optimization_planning.R` - Stage 2: DPPP + window count
3. ✅ `stage3_window_optimization.R` - Stage 3: 22-column CSV generation
4. ✅ `stage4_visualization.R` - Stage 4: Plots & reports
5. ✅ `config_loader.R` - JSON config system
6. ✅ `instrument_utils.R` - Instrument management
7. ✅ `data_loader.R` - Data loading
8. ✅ `dppp_calculator.R` - DPPP calculations
9. ✅ `rt_segmentation.R` - RT binning
10. ✅ `window_generator.R` - Variable windows
11. ✅ `dynamicDIA.R` - Smoothing
12. ✅ `method_writer.R` - CSV export
13. ✅ `raw_metadata_extractor_improved.R` - Raw metadata
14. ✅ `utils_common.R` - Common utilities
15. ✅ `visualizer.R` - Plotting helpers

**Configuration** (9 files):
- ✅ `config/instruments.json` + 8 user config files

**Total Production-Ready**: **28 files**

---

## 📋 Organization Action Plan

### Phase 1: Create New Folders ✅
```bash
mkdir -p scripts/{analysis,diagnostics,experimental}
mkdir -p tests/development
mkdir -p archive/{deprecated_modules/R,deprecated_modules/config,legacy_scripts}
```

### Phase 2: Move Development Scripts
- Move 18 test scripts → `tests/development/`
- Move 4 analysis scripts → `scripts/analysis/`
- Move 6 experimental pipelines → `scripts/experimental/`
- Move 8 diagnostic scripts → `scripts/diagnostics/`

### Phase 3: Archive Deprecated Code
- Move 12 deprecated R modules → `archive/deprecated_modules/R/`
- Move old config → `archive/deprecated_modules/config/`
- Move 7 legacy scripts → `archive/legacy_scripts/`

### Phase 4: Clean Root Folder
- Keep only 4 production entry points in root
- All other scripts moved to organized folders

### Phase 5: Documentation
- Create README.md in each new folder
- Update DEVELOPMENT.md with new structure
- Update CLAUDE.md with folder purposes

---

## ✅ Benefits of This Organization

1. **Clear Production Status**
   - 28 production-ready files clearly identified
   - Easy to package for distribution

2. **Reduced Clutter**
   - Root folder: 47 scripts → 4 scripts (91% reduction)
   - Clear separation of production vs development

3. **Better Development Workflow**
   - Test scripts organized by purpose
   - Easy to find experimental code
   - Clear archive of deprecated code

4. **Maintainability**
   - Easy to onboard new developers
   - Clear history through archive
   - No accidental use of deprecated code

5. **Package Preparation**
   - Production code isolated in R/
   - Easy to create NAMESPACE
   - Clear for DESCRIPTION file

---

**Next Steps**: Execute organization plan with user approval
