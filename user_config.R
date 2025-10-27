# =============================================================================
# DIA Window Optimization Configuration
# Default settings for initial testing
# =============================================================================

# Instrument Configuration
INSTRUMENT_TYPE <- "orbitrap"    # Traditional Orbitrap
MS1_TIME <- 0.05                 # 50ms for MS1
MS2_TIME <- 0.02                 # 20ms per MS2 window

# DPPP Target Settings
TARGET_DPPP <- 7.0               # Quantification mode (recommended)
DPPP_TOLERANCE <- 0.5            # ±0.5 DPPP acceptable
SATISFACTION_TARGET <- 0.85      # 85% of precursors should meet target

# Window Generation Parameters
WINDOW_COUNTS <- list(
  "30min" = 40,                   # 40 windows for 30min gradient
  "60min" = 60,                   # 60 windows for 60min gradient
  "90min" = 80                    # 80 windows for 90min gradient
)
WINDOW_MODE <- "variable"        # Density-based distribution
OVERLAP_PERCENT <- 0.05          # 5% overlap between windows
MIN_WIDTH <- 2                   # Minimum 2 Da width
MAX_WIDTH <- 80                  # Maximum 80 Da width

# RT Segmentation Strategy
RT_SEGMENTS <- list(
  "30min" = 3,                    # 3 RT segments (~10 min each)
  "60min" = 4,                    # 4 RT segments (~15 min each)
  "90min" = 5                     # 5 RT segments (~18 min each)
)
RT_OVERLAP <- 0.5                # 0.5 min overlap between RT segments

# m/z Range Optimization
MZ_STRATEGY <- "smoothing"       # DynamicDIA-style smoothing

# AGC Target
AGC_TARGET <- 800                # Standard for Orbitrap DIA

# Output Configuration
BASE_OUTPUT_DIR <- "results_complete_pipeline"

cat("\n✓ Default configuration loaded from: user_config.R\n")