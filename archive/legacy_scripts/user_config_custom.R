# =============================================================================
# DIA Window Optimization Configuration - User Specified
# Created: 2024-10-24
# =============================================================================

# Instrument Configuration (사용자 지정)
INSTRUMENT_TYPE <- "orbitrap"    # Orbitrap 지정
MS1_TIME <- 0.100                # 100ms for MS1 scan
MS2_TIME <- 0.050                # 50ms per MS2 window

# DPPP Target Settings (사용자 지정)
TARGET_DPPP <- 7.0               # Quantification mode
DPPP_TOLERANCE <- 0.5            # ±0.5 DPPP
SATISFACTION_TARGET <- 0.70      # 70% satisfaction ratio

# Window Generation Parameters
# RT 기반으로 window 수 자동 계산 (5분 segments 기준)
WINDOW_COUNTS <- list(
  "30min" = 30,                   # ~30 windows (adjusted for 5min segments)
  "60min" = 48,                   # ~48 windows (adjusted for 5min segments)
  "90min" = 72                    # ~72 windows (adjusted for 5min segments)
)
WINDOW_MODE <- "variable"        # Variable (density-based)
OVERLAP_PERCENT <- 0.0           # No overlap (사용자 지정: overlap 없음)
MIN_WIDTH <- 2                   # Minimum 2 Da
MAX_WIDTH <- 80                  # Maximum 80 Da

# RT Segmentation Strategy (사용자 지정: 5분 segments)
# 5분 단위로 segmentation
RT_SEGMENTS <- list(
  "30min" = 4,                    # 20min range / 5min = 4 segments
  "60min" = 7,                    # 35min range / 5min = 7 segments
  "90min" = 13                    # 65min range / 5min = 13 segments
)
RT_OVERLAP <- 0.0                # No RT overlap

# m/z Range Optimization
# 4가지 모두 테스트하기 위한 설정
MZ_STRATEGIES <- c("quantile", "smoothing", "coverage", "outlier")

# AGC Target
AGC_TARGET <- 800                # Standard for Orbitrap DIA

# Output Configuration
BASE_OUTPUT_DIR <- "results_user_specified"

cat("\n✓ User-specified configuration loaded\n")
cat("  • Orbitrap with 100ms MS1, 50ms MS2\n")
cat("  • Target DPPP: 7.0 (70% satisfaction)\n")
cat("  • 5-minute RT segments\n")
cat("  • No window overlap\n")
cat("  • Testing all 4 m/z strategies\n\n")