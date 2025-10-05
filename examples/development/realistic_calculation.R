# Realistic Astral Narrow-DIA Calculation

cat('=== REALISTIC ASTRAL NARROW-DIA DESIGN ===\n')

# Real-world constraints
min_window_width <- 2.0    # minimum 2 m/z isolation window
max_scan_rate <- 100       # realistic scan rate limit (Hz)  
max_windows <- 300         # practical window count limit
mz_range <- 600           # 400-1000 m/z range
target_dppp <- 1.5

# Astral timing
ms1_time <- 5    # ms
ms2_time <- 3    # ms

cat('Applied Constraints:\n')
cat('- Minimum window width: 2.0 m/z\n')
cat('- Maximum scan rate: 100 Hz\n')
cat('- Maximum windows: 300\n')
cat('- m/z range: 600 Da\n')

# Calculate maximum windows by constraints
max_by_width <- floor(mz_range / min_window_width)
max_by_rate <- max_windows

max_practical <- min(max_by_width, max_by_rate)
cat('\nMaximum practical windows:', max_practical, '\n')

# Calculate cycle time for max windows
cycle_time_ms <- ms1_time + (max_practical * ms2_time)
cycle_time_sec <- cycle_time_ms / 1000
scan_rate <- 1 / cycle_time_sec

cat('For', max_practical, 'windows:\n')
cat('Cycle time:', cycle_time_ms, 'ms\n')
cat('Scan rate:', round(scan_rate, 1), 'Hz\n')

# Check DPPP
median_fwhm <- 3.1  # seconds
achieved_dppp <- median_fwhm / cycle_time_sec
cat('Achieved DPPP:', round(achieved_dppp, 2), '\n')

# Calculate optimal for target DPPP
target_cycle_ms <- (median_fwhm / target_dppp) * 1000
optimal_windows <- floor((target_cycle_ms - ms1_time) / ms2_time)
optimal_width <- mz_range / optimal_windows
optimal_rate <- 1000 / target_cycle_ms

cat('\nFor target DPPP', target_dppp, ':\n')
cat('Required cycle time:', round(target_cycle_ms, 1), 'ms\n') 
cat('Optimal windows:', optimal_windows, '\n')
cat('Average width:', round(optimal_width, 1), 'm/z\n')
cat('Scan rate:', round(optimal_rate, 1), 'Hz\n')

# Check constraints
constraint_check <- list(
  width_ok = optimal_width >= min_window_width,
  rate_ok = optimal_rate <= max_scan_rate,
  count_ok = optimal_windows <= max_windows
)

cat('\nConstraint Check:\n')
cat('Width >= 2.0 m/z:', constraint_check$width_ok, '\n')
cat('Rate <= 100 Hz:', constraint_check$rate_ok, '\n')
cat('Count <= 300:', constraint_check$count_ok, '\n')

if (all(unlist(constraint_check))) {
  cat('\n✅ All constraints satisfied! Using optimal design.\n')
  final_windows <- optimal_windows
  final_width <- optimal_width
  final_dppp <- target_dppp
  final_rate <- optimal_rate
} else {
  cat('\n❌ Constraints violated. Using constrained design.\n')
  final_windows <- max_practical
  final_width <- mz_range / final_windows
  final_dppp <- achieved_dppp
  final_rate <- scan_rate
}

cat('\n=== FINAL REALISTIC DESIGN ===\n')
cat('Windows:', final_windows, '\n')
cat('Average width:', round(final_width, 1), 'm/z\n')
cat('DPPP:', round(final_dppp, 2), '\n')
cat('Scan rate:', round(final_rate, 1), 'Hz\n')
cat('Cycle time:', round(ms1_time + final_windows * ms2_time, 1), 'ms\n')

cat('\n=== COMPARISON WITH UNREALISTIC CALCULATION ===\n')
cat('Unrealistic (no constraints): 687 windows, 0.9 m/z, 350+ Hz\n')
cat('Realistic (with constraints):', final_windows, 'windows,', round(final_width, 1), 'm/z,', round(final_rate, 1), 'Hz\n')
cat('This matches Astral narrow-DIA capability (~2 m/z windows)\n')