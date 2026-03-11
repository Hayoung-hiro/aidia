# test_astral_sync.R - Verify Astral duty cycle sync based on instrument physics
#
# Core principle:
#   Astral cycle_time = max(MS1_orbitrap_time, n_windows × MS2_scan_time)
#   - MS1 is on Orbitrap → transient + overhead (fixed for given resolution)
#   - MS2 is on Astral MR-TOF → n × (IT + overhead)
#   - If n_windows × MS2 < MS1 → MS2 idle (underutilized Astral)
#   - If n_windows × MS2 > MS1 → MS1 idle (underutilized Orbitrap)
#   - Sync-optimal: n = floor(MS1_time / MS2_scan_time) → zero idle
#
# DPPP is never a bottleneck for Astral because:
#   cycle_time ≈ 0.5-0.6 sec → DPPP = 1.7 × FWHM / cycle >> 7 always
#
# The real optimization target: duty cycle sync (no idle analyzer)

devtools::load_all()

cat("\n=== Astral Duty Cycle Sync Tests ===\n")
cat("  Based on instrument physics, not DPPP targets\n\n")

# --- Shared test data ---
set.seed(42)
n <- 500
test_data <- data.frame(
  Precursor.Mz = runif(n, 400, 900),
  RT.Apex = runif(n, 5, 40),
  FWHM = rnorm(n, 0.15, 0.03),  # minutes (~9 sec)
  Precursor.Charge = sample(2:3, n, replace = TRUE),
  Stripped.Sequence = paste0("PEPTIDE", seq_len(n))
)
validated <- structure(
  list(data = test_data, metadata = list(source = "test")),
  class = "ValidatedData"
)

# --- Instrument physics reference ---
# Orbitrap 240K: transient = 512 ms, overhead = 10.0 ms (from JSON) → MS1 total = 522.0 ms
# Astral MS2 at 3ms IT: scan = max(2.5, 3.0) + 2.0 overhead = 5.0 ms
# Astral MS2 at 6ms IT: scan = max(2.5, 6.0) + 2.0 overhead = 8.0 ms
# (overhead values from instruments.json: ms1_overhead_ms, ms2_overhead_ms)

# Load Astral overhead from instruments.json (same source as production code)
astral_config <- get_instrument_config("astral")
ms1_overhead_240k <- astral_config$ms1_overhead_ms %||% 10.0
ms2_overhead_astral <- astral_config$ms2_overhead_ms %||% 2.0

ms1_transient_240k <- get_transient_time(240000, "orbitrap")
ms1_total_240k <- ms1_transient_240k + ms1_overhead_240k
cat(sprintf("Reference: Orbitrap 240K MS1 = %.1f ms (%.0f transient + %.1f overhead)\n",
            ms1_total_240k, ms1_transient_240k, ms1_overhead_240k))

# =============================================================================
# Test 1: Astral 240K + 3ms IT → sync-optimal = floor(522 / 5.0) = 104
# =============================================================================
cat("\nTest 1: Astral 240K MS1, 3ms MS2 IT\n")
cat(sprintf("  Physics: MS2 scan = 5.0 ms → sync-optimal = floor(%.0f/5) = %d\n",
            ms1_total_240k, as.integer(floor(ms1_total_240k / 5.0))))

plan1 <- plan_optimization(
  validated_data = validated,
  instrument_preset = "astral",
  target_dppp = 7.0,
  target_satisfaction = 0.70,
  ms2_time_override = 3.0 / 1000
)

n_sync_expected_1 <- as.integer(floor(ms1_total_240k / 5.0))
cat(sprintf("  Expected sync-optimal: %d windows\n", n_sync_expected_1))
cat(sprintf("  Actual window count:   %d windows\n", plan1$window_count_per_bin))
cat(sprintf("  Actual cycle time:     %.3f sec (should ≈ %.3f sec = MS1 total)\n",
            plan1$actual_cycle_time_sec, ms1_total_240k / 1000))
cat(sprintf("  Duty cycle:            %.1f%%\n", plan1$duty_cycle_sync$duty_cycle_pct))

# Verify: window count = sync-optimal
stopifnot(plan1$window_count_per_bin == n_sync_expected_1)
# Verify: cycle time ≈ MS1 total (MS1 is limiting, not MS2)
stopifnot(abs(plan1$actual_cycle_time_sec - ms1_total_240k / 1000) < 0.01)
# Verify: duty cycle near 100%
stopifnot(plan1$duty_cycle_sync$duty_cycle_pct >= 95)
# Verify: DPPP is far above target (never a bottleneck)
dppp_at_cycle <- 1.7 * 9.0 / plan1$actual_cycle_time_sec
cat(sprintf("  DPPP at this cycle:    %.1f (target: 7.0 — easily met)\n", dppp_at_cycle))
stopifnot(dppp_at_cycle > 7.0 * 2)  # At least 2x above target
cat("  PASS\n")

# =============================================================================
# Test 2: Astral 240K + 6ms IT → sync-optimal = floor(522 / 8.0) = 65
# =============================================================================
cat("\nTest 2: Astral 240K MS1, 6ms MS2 IT (sensitivity mode)\n")
cat(sprintf("  Physics: MS2 scan = 8.0 ms → sync-optimal = floor(%.0f/8) = %d\n",
            ms1_total_240k, as.integer(floor(ms1_total_240k / 8.0))))

plan2 <- plan_optimization(
  validated_data = validated,
  instrument_preset = "astral",
  target_dppp = 7.0,
  target_satisfaction = 0.70,
  ms2_time_override = 6.0 / 1000
)

n_sync_expected_2 <- as.integer(floor(ms1_total_240k / 8.0))
cat(sprintf("  Expected sync-optimal: %d windows\n", n_sync_expected_2))
cat(sprintf("  Actual window count:   %d windows\n", plan2$window_count_per_bin))
cat(sprintf("  Actual cycle time:     %.3f sec\n", plan2$actual_cycle_time_sec))
cat(sprintf("  Duty cycle:            %.1f%%\n", plan2$duty_cycle_sync$duty_cycle_pct))

stopifnot(plan2$window_count_per_bin == n_sync_expected_2)
stopifnot(plan2$duty_cycle_sync$duty_cycle_pct >= 95)
cat("  PASS\n")

# =============================================================================
# Test 3: Exploris (sequential) — sync not applicable, DPPP is constraint
# =============================================================================
cat("\nTest 3: Exploris 480 (sequential) — DPPP-based, no sync\n")

plan3 <- plan_optimization(
  validated_data = validated,
  instrument_preset = "exploris",
  target_dppp = 7.0,
  target_satisfaction = 0.70
)

cat(sprintf("  Window count: %d (DPPP-based)\n", plan3$window_count_per_bin))
cat(sprintf("  Cycle time:   %.3f sec\n", plan3$actual_cycle_time_sec))
cat(sprintf("  Duty cycle sync: %s\n",
            ifelse(is.null(plan3$duty_cycle_sync), "NULL (correct — sequential)", "ERROR")))

stopifnot(is.null(plan3$duty_cycle_sync))
# Sequential: cycle_time = MS1 + n × MS2, should be close to required
stopifnot(plan3$actual_cycle_time_sec <= plan3$required_cycle_time_sec * 1.05)
cat("  PASS\n")

# =============================================================================
# Test 4: Excess windows cause MS1 idle (anti-pattern detection)
# =============================================================================
cat("\nTest 4: Verify excess windows cause idle (physics check)\n")

# 200 windows × 5ms = 1000ms > 522ms total → MS1 idle 478ms
sync_200 <- calculate_duty_cycle_sync(
  ms1_time_ms = ms1_total_240k,
  ms2_scan_time_ms = 5.0,
  n_windows = 200
)
cat(sprintf("  200 windows × 5ms: MS1 idle = %.0f ms, duty = %.1f%%\n",
            sync_200$ms1_idle_ms, sync_200$duty_cycle_pct))
stopifnot(sync_200$ms1_idle_ms > 400)  # Significant MS1 idle
stopifnot(sync_200$sync_status == "ms1_idle")

# 50 windows × 5ms = 250ms < 522ms total → MS2 idle 272ms
sync_50 <- calculate_duty_cycle_sync(
  ms1_time_ms = ms1_total_240k,
  ms2_scan_time_ms = 5.0,
  n_windows = 50
)
cat(sprintf("  50 windows × 5ms:  MS2 idle = %.0f ms, duty = %.1f%%\n",
            sync_50$ms2_idle_ms, sync_50$duty_cycle_pct))
stopifnot(sync_50$ms2_idle_ms > 200)  # Significant MS2 idle
stopifnot(sync_50$sync_status == "ms2_idle")

# Sync-optimal: ~104 windows → near zero idle
sync_opt <- calculate_duty_cycle_sync(
  ms1_time_ms = ms1_total_240k,
  ms2_scan_time_ms = 5.0,
  n_windows = n_sync_expected_1
)
cat(sprintf("  %d windows × 5ms: idle = %.0f ms, duty = %.1f%%\n",
            n_sync_expected_1, max(sync_opt$ms1_idle_ms, sync_opt$ms2_idle_ms),
            sync_opt$duty_cycle_pct))
stopifnot(sync_opt$duty_cycle_pct >= 99)
cat("  PASS\n")

# =============================================================================
# Test 5: Different MS1 resolution changes sync-optimal
# =============================================================================
cat("\nTest 5: MS1 resolution affects sync-optimal\n")

ms1_trans_120k <- get_transient_time(120000, "orbitrap")  # 256 ms
ms1_total_120k <- ms1_trans_120k + ms1_overhead_240k  # reuse Astral overhead
n_sync_120k <- as.integer(floor(ms1_total_120k / 5.0))

ms1_trans_480k <- get_transient_time(480000, "orbitrap")  # 1024 ms
ms1_total_480k <- ms1_trans_480k + ms1_overhead_240k
n_sync_480k <- as.integer(floor(ms1_total_480k / 5.0))

cat(sprintf("  120K (%.0f ms total): sync-optimal = %d windows\n",
            ms1_total_120k, n_sync_120k))
cat(sprintf("  240K (%.0f ms total): sync-optimal = %d windows\n",
            ms1_total_240k, n_sync_expected_1))
cat(sprintf("  480K (%.0f ms total): sync-optimal = %d windows\n",
            ms1_total_480k, n_sync_480k))

stopifnot(n_sync_120k < n_sync_expected_1)
stopifnot(n_sync_expected_1 < n_sync_480k)
cat("  PASS\n")

cat("\n=== All tests passed ===\n")
cat("  Astral: sync-optimal is primary constraint (DPPP always met)\n")
cat("  Sequential: DPPP is primary constraint (no sync concept)\n")
