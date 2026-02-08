# raw_metadata_workflow_example.R - Example workflow for raw file metadata integration

cat("╔══════════════════════════════════════════════╗\n")
cat("║    RAW METADATA INTEGRATION WORKFLOW         ║\n")
cat("║    DIA Window Optimizer Enhanced Example     ║\n")
cat("╚══════════════════════════════════════════════╝\n\n")

# Load required modules
source("R/raw_metadata_extractor.R")
source("R/user_config_generator.R")
source("R/data_loader.R")
source("R/fwhm_analyzer.R")
source("main.R")

# =============================================================================
# STEP 1: Check rawrr Installation and Raw Files
# =============================================================================

cat("=== STEP 1: Environment Check ===\n")

# Check if rawrr is properly configured
rawrr_status <- check_rawrr_status()

if (!rawrr_status) {
  cat("❌ rawrr is not properly configured. Stopping example.\n")
  cat("\nTo continue:\n")
  cat("1. Install Thermo MSFileReader\n")
  cat("2. Ensure .NET Framework is available\n")
  cat("3. Restart R session\n")
  stop("rawrr configuration required")
}

# Check if raw files are available
raw_file_dir <- "rawfile"
if (!dir.exists(raw_file_dir)) {
  cat("❌ Raw file directory not found. Creating directory...\n")
  dir.create(raw_file_dir, recursive = TRUE)
  cat(sprintf("Please place Thermo raw files in: %s\n", raw_file_dir))
  stop("Raw files required for metadata extraction")
}

raw_files <- list.files(raw_file_dir, pattern = "\\.raw$", ignore.case = TRUE)
if (length(raw_files) == 0) {
  cat("❌ No raw files found in rawfile/ directory\n")
  cat(sprintf("Please place Thermo raw files in: %s\n", raw_file_dir))
  stop("Raw files required for metadata extraction")
}

cat(sprintf("✅ Found %d raw files:\n", length(raw_files)))
for (i in seq_along(raw_files)) {
  cat(sprintf("  %d. %s\n", i, raw_files[i]))
}

# =============================================================================
# STEP 2: Extract Raw File Metadata
# =============================================================================

cat("\n=== STEP 2: Raw File Metadata Extraction ===\n")

# Create configuration directory
config_dir <- "config"
if (!dir.exists(config_dir)) {
  dir.create(config_dir, recursive = TRUE)
}

# Extract metadata from all raw files
cat("Extracting metadata from raw files...\n")
raw_metadata <- process_raw_files_batch(
  raw_file_dir = raw_file_dir,
  save_json = TRUE,
  json_output_dir = file.path(config_dir, "metadata")
)

if (length(raw_metadata) == 0) {
  stop("Failed to extract metadata from raw files")
}

cat(sprintf("✅ Successfully extracted metadata from %d files\n", length(raw_metadata)))

# =============================================================================
# STEP 3: Generate User Configuration
# =============================================================================

cat("\n=== STEP 3: Generate User Configuration ===\n")

# Generate user configuration from metadata
user_config_result <- create_user_config_from_raw_files(
  raw_file_dir = raw_file_dir,
  output_dir = config_dir
)

user_config <- user_config_result$user_config
comparison_results <- user_config_result$comparison_results

cat("\n📊 Configuration Generation Summary:\n")
cat(sprintf("  • Source instrument: %s\n", user_config$metadata_source$instrument_model))
cat(sprintf("  • Recommended preset: %s\n", user_config$recommended_settings$primary_preset))
cat(sprintf("  • Confidence level: %s\n", user_config$recommended_settings$confidence_level))

if (length(user_config$recommended_settings$custom_overrides) > 0) {
  cat("  • Custom overrides applied:\n")
  for (setting in names(user_config$recommended_settings$custom_overrides)) {
    cat(sprintf("    - %s: %s\n", setting, user_config$recommended_settings$custom_overrides[[setting]]))
  }
}

# =============================================================================
# STEP 4: Create Enhanced Configuration File
# =============================================================================

cat("\n=== STEP 4: Create Enhanced Configuration ===\n")

# Create enhanced configuration that uses the raw metadata
enhanced_config <- list(
  # Standard parameters
  proteome_file = "path/to/diann_output.parquet",  # User should update this
  mz_range = c(380, 980),
  rt_segments = 5,
  target_dppp = 1.25,

  # Enhanced metadata integration
  enable_raw_metadata = TRUE,
  use_user_config = TRUE,

  # Use recommended instrument preset
  instrument_preset = user_config$recommended_settings$primary_preset,

  # FWHM settings optimized for metadata
  fwhm_strategy = "balanced",
  fwhm_analysis_enabled = TRUE,

  # Window settings
  window_mode = "dynamic",
  min_window_width = 2.0,
  max_window_width = 80.0,
  overlap_mode = "percentage",
  overlap_value = 0.5,

  # RT range
  rt_min = user_config$acquisition_parameters$rt_range_minutes[1],
  rt_max = user_config$acquisition_parameters$rt_range_minutes[2],

  # Other settings
  min_precursors_per_window = 100,

  # Output settings
  output_format = "csv",
  output_path = "optimized_windows_enhanced",
  create_plots = TRUE,
  plot_output = "enhanced_optimization_report.pdf",

  # Metadata information
  metadata_source = user_config$metadata_source,
  generated_from_raw = TRUE
)

# Save enhanced configuration
enhanced_config_file <- file.path(config_dir, "enhanced_config.json")
library(jsonlite)
enhanced_config_json <- toJSON(enhanced_config, pretty = TRUE, auto_unbox = TRUE)
writeLines(enhanced_config_json, enhanced_config_file)

cat(sprintf("✅ Enhanced configuration saved to: %s\n", enhanced_config_file))

# =============================================================================
# STEP 5: Demonstrate Enhanced Data Loading
# =============================================================================

cat("\n=== STEP 5: Enhanced Data Loading Example ===\n")

# This is a demonstration - user would need to provide actual DIA-NN file
demo_diann_file <- "path/to/diann_output.parquet"

cat("📝 Example of enhanced data loading:\n")
cat(sprintf("load_diann_data_enhanced(\n"))
cat(sprintf("  file_path = \"%s\",\n", demo_diann_file))
cat(sprintf("  integrate_raw_metadata = TRUE,\n"))
cat(sprintf("  raw_file_dir = \"%s\"\n", raw_file_dir))
cat(sprintf(")\n\n"))

cat("This would add the following metadata columns:\n")
cat("  • Raw.File.Name\n")
cat("  • Instrument.Model\n")
cat("  • Serial.Number\n")
cat("  • Scan.Rate.Hz\n")
cat("  • Avg.Cycle.Time.Sec\n")
cat("  • MS2.Per.Cycle\n")
cat("  • Acquisition.Duration.Min\n")
cat("  • Metadata.Available\n")
cat("  • FWHM.Confidence\n")

# =============================================================================
# STEP 6: Example Usage Commands
# =============================================================================

cat("\n=== STEP 6: Usage Examples ===\n")

cat("📋 To run the enhanced optimization:\n\n")

cat("# Option 1: Using enhanced configuration file\n")
cat(sprintf("result <- main_optimization(config_file = \"%s\")\n\n", enhanced_config_file))

cat("# Option 2: Direct parameters with metadata integration\n")
cat("result <- main_optimization(\n")
cat("  proteome_file = \"your_diann_output.parquet\",\n")
cat("  instrument_preset = \"astral\",  # or your detected preset\n")
cat("  enable_raw_metadata = TRUE,\n")
cat("  use_user_config = TRUE,\n")
cat("  target_dppp = 1.25\n")
cat(")\n\n")

cat("# Option 3: Generate user config separately\n")
cat("user_config <- create_user_config_from_raw_files()\n")
cat("instrument_config <- apply_user_config_to_instrument(user_config)\n\n")

# =============================================================================
# STEP 7: Validation and Quality Checks
# =============================================================================

cat("\n=== STEP 7: Quality Validation ===\n")

# Check consistency between raw metadata and recommended settings
cat("🔍 Validation checks:\n")

# Scan rate validation
actual_scan_rate <- user_config$instrument_timing$actual_scan_rate_hz
if (!is.na(actual_scan_rate)) {
  cat(sprintf("  ✅ Actual scan rate: %.1f Hz\n", actual_scan_rate))

  # Load recommended preset for comparison
  source("config/instruments.R")
  recommended_preset <- get_instrument_config(user_config$recommended_settings$primary_preset)

  if (actual_scan_rate <= recommended_preset$max_scan_rate) {
    cat(sprintf("  ✅ Within instrument limits (max: %.1f Hz)\n", recommended_preset$max_scan_rate))
  } else {
    cat(sprintf("  ⚠️ Exceeds instrument limits (max: %.1f Hz)\n", recommended_preset$max_scan_rate))
  }
} else {
  cat("  ⚠️ Could not determine actual scan rate\n")
}

# Timing validation
actual_cycle_time <- user_config$instrument_timing$actual_cycle_time_sec
if (!is.na(actual_cycle_time)) {
  cat(sprintf("  ✅ Actual cycle time: %.2f seconds\n", actual_cycle_time))
  if (actual_cycle_time >= 0.5 && actual_cycle_time <= 5.0) {
    cat("  ✅ Cycle time within reasonable range\n")
  } else {
    cat("  ⚠️ Unusual cycle time detected\n")
  }
} else {
  cat("  ⚠️ Could not determine actual cycle time\n")
}

# =============================================================================
# STEP 8: Summary and Next Steps
# =============================================================================

cat("\n=== STEP 8: Summary and Next Steps ===\n")

cat("📋 Workflow completed successfully!\n\n")

cat("Generated files:\n")
cat(sprintf("  • Raw metadata: %s/metadata/\n", config_dir))
cat(sprintf("  • User config: %s/user_config_final.json\n", config_dir))
cat(sprintf("  • Preset comparison: %s/preset_comparison.csv\n", config_dir))
cat(sprintf("  • Enhanced config: %s\n", enhanced_config_file))

cat("\nNext steps:\n")
cat("  1. Update 'proteome_file' path in enhanced_config.json\n")
cat("  2. Run main optimization with enhanced configuration\n")
cat("  3. Compare results with standard optimization\n")
cat("  4. Validate instrument performance predictions\n")

cat("\n🎯 Benefits of metadata integration:\n")
cat("  • More accurate instrument settings\n")
cat("  • Confidence-weighted FWHM analysis\n")
cat("  • Better scan rate predictions\n")
cat("  • Validation against actual performance\n")
cat("  • Reproducible configurations\n")

cat("\n✅ Raw metadata integration workflow complete!\n")

# Optional: Print detailed metadata summary
if (interactive()) {
  cat("\nWould you like to see detailed metadata summary? (y/n): ")
  response <- readline()

  if (tolower(substr(response, 1, 1)) == "y") {
    cat("\n" , "=" , rep("=", 50) , "=", "\n")
    cat("DETAILED METADATA SUMMARY\n")
    cat("=" , rep("=", 50) , "=", "\n")

    for (file_name in names(raw_metadata)) {
      metadata <- raw_metadata[[file_name]]
      cat(sprintf("\nFile: %s\n", file_name))
      cat(sprintf("  Instrument: %s (S/N: %s)\n",
                  metadata$instrument$model,
                  metadata$instrument$serial_number))
      cat(sprintf("  Duration: %.1f minutes\n", metadata$acquisition$duration_minutes))
      cat(sprintf("  Total scans: %d (MS1: %d, MS2: %d)\n",
                  metadata$scan_statistics$total_scans,
                  metadata$scan_statistics$ms1_scans,
                  metadata$scan_statistics$ms2_scans))

      if (!is.null(metadata$scan_cycle_stats)) {
        cat(sprintf("  Scan rate: %.1f Hz\n", metadata$scan_cycle_stats$scan_rate))
        cat(sprintf("  Cycle time: %.2f seconds\n", metadata$scan_cycle_stats$avg_cycle_time))
        cat(sprintf("  MS2 per cycle: %.1f\n", metadata$scan_cycle_stats$ms2_per_cycle))
      }
    }
  }
}