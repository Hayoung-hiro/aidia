# =============================================================================
# Interactive Configuration Helper for DIA Window Optimization
# =============================================================================
# Run this script to create your personalized configuration
# =============================================================================

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║  DIA Window Optimization - Configuration Helper                 ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Function to get user input with default
get_input <- function(prompt, default = NULL) {
  if (!is.null(default)) {
    cat(sprintf("%s [default: %s]: ", prompt, default))
  } else {
    cat(sprintf("%s: ", prompt))
  }
  input <- readline()
  if (input == "" && !is.null(default)) {
    return(default)
  }
  return(input)
}

# Function to get numeric input
get_numeric <- function(prompt, default = NULL) {
  val <- get_input(prompt, default)
  return(as.numeric(val))
}

cat("Please provide your configuration parameters:\n")
cat("═══════════════════════════════════════════════\n\n")

# 1. Instrument Configuration
cat("1. INSTRUMENT CONFIGURATION\n")
cat("---------------------------\n")
cat("Available instruments:\n")
cat("  1) astral (50-100 Hz, parallel acquisition)\n")
cat("  2) exploris (25-40 Hz, sequential)\n")
cat("  3) orbitrap (8-12 Hz, traditional)\n")
cat("  4) timstof\n")
instrument_choice <- get_input("Select instrument (1-4)", "3")
INSTRUMENT_TYPE <- c("astral", "exploris", "orbitrap", "timstof")[as.numeric(instrument_choice)]
cat(sprintf("  → Selected: %s\n", INSTRUMENT_TYPE))

MS1_TIME <- get_numeric("MS1 scan time (seconds)", "0.05")
MS2_TIME <- get_numeric("MS2 scan time per window (seconds)", "0.02")

# 2. DPPP Target Settings
cat("\n2. DPPP TARGET SETTINGS\n")
cat("-----------------------\n")
cat("DPPP modes:\n")
cat("  1) Quantification (DPPP = 7.0) - Recommended\n")
cat("  2) Identification (DPPP = 1.5) - Maximum IDs\n")
cat("  3) Balanced (DPPP = 4.0) - Compromise\n")
cat("  4) Custom\n")
dppp_choice <- get_input("Select DPPP mode (1-4)", "1")
if (dppp_choice == "4") {
  TARGET_DPPP <- get_numeric("Enter custom DPPP target", "7.0")
} else {
  TARGET_DPPP <- c(7.0, 1.5, 4.0, 7.0)[as.numeric(dppp_choice)]
}
cat(sprintf("  → Target DPPP: %.1f\n", TARGET_DPPP))

DPPP_TOLERANCE <- get_numeric("DPPP tolerance (±)", "0.5")
SATISFACTION_TARGET <- get_numeric("Satisfaction target (0-1)", "0.85")

# 3. Window Generation Parameters
cat("\n3. WINDOW GENERATION PARAMETERS\n")
cat("--------------------------------\n")
cat("Window counts per gradient:\n")
W_30MIN <- get_numeric("Windows for 30min gradient", "40")
W_60MIN <- get_numeric("Windows for 60min gradient", "60")
W_90MIN <- get_numeric("Windows for 90min gradient", "80")

cat("\nWindow mode:\n")
cat("  1) Variable (density-based) - Recommended\n")
cat("  2) Fixed (equal width)\n")
mode_choice <- get_input("Select window mode (1-2)", "1")
WINDOW_MODE <- c("variable", "fixed")[as.numeric(mode_choice)]
cat(sprintf("  → Mode: %s\n", WINDOW_MODE))

OVERLAP_PERCENT <- get_numeric("Overlap percentage (0-0.1)", "0.05")
MIN_WIDTH <- get_numeric("Minimum window width (Da)", "2")
MAX_WIDTH <- get_numeric("Maximum window width (Da)", "80")

# 4. RT Segmentation
cat("\n4. RT SEGMENTATION STRATEGY\n")
cat("---------------------------\n")
RT_30MIN <- get_numeric("RT segments for 30min", "3")
RT_60MIN <- get_numeric("RT segments for 60min", "4")
RT_90MIN <- get_numeric("RT segments for 90min", "5")
RT_OVERLAP <- get_numeric("RT overlap between segments (min)", "0.5")

# 5. m/z Range Optimization
cat("\n5. M/Z RANGE OPTIMIZATION\n")
cat("-------------------------\n")
cat("Available strategies:\n")
cat("  1) Smoothing (DynamicDIA-style) - Recommended\n")
cat("  2) Quantile (percentile-based)\n")
cat("  3) Coverage (maximize coverage)\n")
cat("  4) Outlier (remove outliers)\n")
strategy_choice <- get_input("Select strategy (1-4)", "1")
MZ_STRATEGY <- c("smoothing", "quantile", "coverage", "outlier")[as.numeric(strategy_choice)]
cat(sprintf("  → Strategy: %s\n", MZ_STRATEGY))

# 6. AGC Target
cat("\n6. AGC TARGET\n")
cat("-------------\n")
AGC_TARGET <- get_numeric("Normalized AGC Target (%)", "800")

# 7. Output Directory
cat("\n7. OUTPUT CONFIGURATION\n")
cat("-----------------------\n")
BASE_OUTPUT_DIR <- get_input("Base output directory", "results_complete_pipeline")

# Generate configuration file
cat("\n\n═══════════════════════════════════════════════\n")
cat("Generating configuration file...\n")

config_content <- sprintf('# =============================================================================
# DIA Window Optimization Configuration
# Generated: %s
# =============================================================================

# Instrument Configuration
INSTRUMENT_TYPE <- "%s"
MS1_TIME <- %g
MS2_TIME <- %g

# DPPP Target Settings
TARGET_DPPP <- %g
DPPP_TOLERANCE <- %g
SATISFACTION_TARGET <- %g

# Window Generation Parameters
WINDOW_COUNTS <- list(
  "30min" = %d,
  "60min" = %d,
  "90min" = %d
)
WINDOW_MODE <- "%s"
OVERLAP_PERCENT <- %g
MIN_WIDTH <- %g
MAX_WIDTH <- %g

# RT Segmentation Strategy
RT_SEGMENTS <- list(
  "30min" = %d,
  "60min" = %d,
  "90min" = %d
)
RT_OVERLAP <- %g

# m/z Range Optimization
MZ_STRATEGY <- "%s"

# AGC Target
AGC_TARGET <- %d

# Output Configuration
BASE_OUTPUT_DIR <- "%s"

cat("\\n✓ Configuration loaded from: user_config.R\\n")
',
Sys.Date(),
INSTRUMENT_TYPE,
MS1_TIME,
MS2_TIME,
TARGET_DPPP,
DPPP_TOLERANCE,
SATISFACTION_TARGET,
W_30MIN, W_60MIN, W_90MIN,
WINDOW_MODE,
OVERLAP_PERCENT,
MIN_WIDTH,
MAX_WIDTH,
RT_30MIN, RT_60MIN, RT_90MIN,
RT_OVERLAP,
MZ_STRATEGY,
AGC_TARGET,
BASE_OUTPUT_DIR)

# Save configuration
writeLines(config_content, "user_config.R")
cat("✓ Configuration saved to: user_config.R\n")

# Display summary
cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║                    CONFIGURATION SUMMARY                        ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat(sprintf("Instrument:     %s\n", INSTRUMENT_TYPE))
cat(sprintf("DPPP Target:    %.1f ± %.1f\n", TARGET_DPPP, DPPP_TOLERANCE))
cat(sprintf("Window Mode:    %s\n", WINDOW_MODE))
cat(sprintf("Window Counts:  30min=%d, 60min=%d, 90min=%d\n", W_30MIN, W_60MIN, W_90MIN))
cat(sprintf("RT Segments:    30min=%d, 60min=%d, 90min=%d\n", RT_30MIN, RT_60MIN, RT_90MIN))
cat(sprintf("m/z Strategy:   %s\n", MZ_STRATEGY))
cat(sprintf("Output Dir:     %s\n", BASE_OUTPUT_DIR))

cat("\n✅ Configuration complete!\n\n")
cat("To run the pipeline with your configuration:\n")
cat("  1. Edit test_complete_pipeline.R\n")
cat("  2. Replace the configuration section with: source('user_config.R')\n")
cat("  3. Run: Rscript test_complete_pipeline.R\n")
cat("\nOr run directly:\n")
cat("  source('user_config.R')\n")
cat("  source('test_complete_pipeline.R')\n")