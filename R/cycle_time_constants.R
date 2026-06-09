# cycle_time_constants.R - Analyzer timing constants for cycle time computation
#
# Physics constants and fallback defaults used by R/cycle_time.R. Extracted from
# cycle_time.R (v0.4.x) to keep the computation module focused on math + sync.
# These are kept as R constants (NOT JSON) because several serve as
# function-definition-time fallback defaults when instruments.json omits a value
# (e.g. overhead_factor = DEFAULT_OVERHEAD_FACTOR) -- a JSON-only home would
# create a package load-order chicken-and-egg.
#
# See docs/adr/0001-keep-parallel-sync-logic-in-cycle-time.md.


# =============================================================================
# Constants: Resolution-Transient Time Mapping (Orbitrap)
# =============================================================================
# Theoretical relationship: Transient Time proportional to Resolution
# These values are for Orbitrap analyzers (Thermo Fisher)
# Reference: Orbitrap physics - higher resolution requires longer transient
#
# Source: https://proteomicsresource.washington.edu/instruments/orbitrapexploris480.php

#' Orbitrap Resolution to Transient Time Mapping
#'
#' Standard mapping for Thermo Orbitrap analyzers.
#' Transient time is the ion detection time in the Orbitrap.
#'
#' @format Named numeric vector (resolution -> transient_time_ms)
#' @keywords internal
ORBITRAP_TRANSIENT_TIME_MS <- c(
  "7500"   = 16,
  "15000"  = 32,
  "30000"  = 64,
  "45000"  = 96,
  "60000"  = 128,
  "120000" = 256,
  "240000" = 512,
  "480000" = 1024
)

# =============================================================================
# Constants: Astral Analyzer (Multi-Reflection TOF)
# =============================================================================
# The Astral analyzer is NOT an Orbitrap - it's a Multi-Reflection TOF
# Key characteristics:
#   - Fixed resolution: 80,000 @ m/z 524 (cannot be changed)
#   - Scan rate depends on injection time (NOT resolution)
#   - Parallel architecture: ion accumulation overlaps with detection
#   - Max rate: 200 Hz (5ms/scan) with up to 3ms IT
#
# Source: https://proteomicsresource.washington.edu/instruments/astral.php
# Reference: Anal. Chem. 2023 (PMC10603608)
#
# Timing breakdown at 200 Hz:
#   - Total cycle: 5 ms (1000/200)
#   - Non-parallelizable stages: ~4.5 ms
#   - Max IT at 200 Hz: ~3 ms (60% duty cycle)
#   - Parallelization allows IT to overlap with detection/processing

#' Astral Analyzer Fixed Parameters
#'
#' The Astral uses a Multi-Reflection TOF design with fixed resolution.
#' Scan rate is determined by injection time, not resolution.
#'
#' @keywords internal
ASTRAL_FIXED_RESOLUTION <- 80000  # Fixed at m/z 524

#' Astral Detection Time (ms)
#'
#' Fixed detection time for the Astral MR-TOF analyzer.
#' Unlike Orbitrap, this doesn't change with resolution (fixed at 80K).
#' The MR-TOF has ~2.5ms detection time in standard operation.
#'
#' @keywords internal
ASTRAL_DETECTION_TIME_MS <- 2.5

#' Astral Minimum Cycle Time (ms)
#'
#' The minimum time per scan at maximum speed (200 Hz).
#' This includes all parallelized operations.
#'
#' @keywords internal
ASTRAL_MIN_CYCLE_TIME_MS <- 5.0  # 1000 / 200 Hz

# NOTE (v0.4.1+): A static ASTRAL_IT_TO_SCANRATE lookup table was removed here.
# It was unused dead code AND diverged from the canonical formula at high IT
# (e.g. it claimed IT=20ms -> 25 Hz, while the formula gives ~45 Hz). Astral
# IT -> scan-rate is computed in ONE place only: calculate_ms2_scan_time()
# (analyzer = "astral"), where t_scan = 5 ms for IT <= 3 ms (200 Hz parallel),
# else IT + buffer. Do NOT reintroduce a parallel lookup table (two sources of truth).

#' Default Orbitrap 240K Transient Time (ms)
#'
#' Fallback value when resolution lookup returns NA.
#' 240K is the default MS1 resolution for Astral instruments.
#' @keywords internal
ORBITRAP_240K_TRANSIENT_MS <- 512

#' Default MS1 Overhead (ms)
#'
#' Fallback value when instrument JSON does not specify ms1_overhead_ms.
#' Based on typical C-trap/IRM timing for modern Orbitrap instruments.
#' @keywords internal
DEFAULT_MS1_OVERHEAD_MS <- 10.0


# =============================================================================
# Constants: Overhead Modeling
# =============================================================================
# delta (overhead) includes:
#   - Ion transfer time between mass analyzers
#   - C-trap fill/empty time
#   - Orbitrap stabilization time
#   - HCD cell operation time
#   - Data transfer overhead
#
# Typical values:
#   - delta ~= 0.15-0.25 x Transient Time (15-25% overhead)
#   - Minimum delta ~= 3-5 ms for modern instruments

#' Default Overhead Factor
#'
#' Overhead as fraction of transient time.
#' Conservative estimate for stable operation.
#' @keywords internal
DEFAULT_OVERHEAD_FACTOR <- 0.20  # 20% of transient time

#' Minimum Overhead (ms)
#'
#' Hardware minimum overhead regardless of transient time.
#' Accounts for ion transfer and settling times.
#' @keywords internal
MINIMUM_OVERHEAD_MS <- 5.0
