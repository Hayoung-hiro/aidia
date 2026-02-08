# Realistic Astral Narrow-DIA Window Design
# Apply real-world constraints for practical implementation

source('main.R')

cat('=== REALISTIC ASTRAL NARROW-DIA DESIGN ===\n')

# Astral realistic constraints
constraints <- list(
  min_window_width = 2.0,      # 최소 2 m/z isolation window (user requirement)
  max_scan_rate = 100,         # 현실적 scan rate limit (Hz)
  max_windows = 300,           # 실용적 window 수 제한
  mz_range = 600,              # 400-1000 m/z = 600 Da range
  target_dppp = 1.5
)

cat('Applied Constraints:\n')
cat(sprintf('- Minimum window width: %.1f m/z\n', constraints$min_window_width))
cat(sprintf('- Maximum scan rate: %d Hz\n', constraints$max_scan_rate))
cat(sprintf('- Maximum windows: %d\n', constraints$max_windows))
cat(sprintf('- m/z range: %d Da\n', constraints$mz_range))

# Calculate maximum possible windows based on constraints
max_windows_by_width <- floor(constraints$mz_range / constraints$min_window_width)
max_windows_by_rate <- constraints$max_windows

max_practical_windows <- min(max_windows_by_width, max_windows_by_rate)

cat(sprintf('\nMaximum practical windows: %d\n', max_practical_windows))
cat(sprintf('(Limited by: %s)\n', 
            ifelse(max_windows_by_width < max_windows_by_rate, 
                   'minimum window width', 'scan rate/practicality'))

# Calculate required cycle time for max windows
# Using Astral actual timing
ms1_time <- 5
ms2_time <- 3

required_cycle_time_ms <- ms1_time + (max_practical_windows * ms2_time)
required_cycle_time_sec <- required_cycle_time_ms / 1000
required_scan_rate <- 1 / required_cycle_time_sec

cat(sprintf('\nFor %d windows:\n', max_practical_windows))
cat(sprintf('Required cycle time: %.1f ms (%.3f sec)\n', 
            required_cycle_time_ms, required_cycle_time_sec))
cat(sprintf('Required scan rate: %.1f Hz\n', required_scan_rate))

# Check if this meets DPPP requirements
median_fwhm <- 3.1  # seconds (from previous analysis)
achieved_dppp <- median_fwhm / required_cycle_time_sec

cat(sprintf('Achieved DPPP: %.2f (target: %.1f)\n', 
            achieved_dppp, constraints$target_dppp))

# If DPPP is too high, calculate optimal window count for target DPPP
if (achieved_dppp > constraints$target_dppp) {
  cat('\nDPPP too high, calculating optimal window count...\n')
  
  target_cycle_time_ms <- (median_fwhm / constraints$target_dppp) * 1000
  optimal_windows <- floor((target_cycle_time_ms - ms1_time) / ms2_time)
  optimal_window_width <- constraints$mz_range / optimal_windows
  optimal_scan_rate <- 1000 / target_cycle_time_ms
  
  cat(sprintf('Target cycle time: %.1f ms\n', target_cycle_time_ms))
  cat(sprintf('Optimal windows: %d\n', optimal_windows))
  cat(sprintf('Average window width: %.1f m/z\n', optimal_window_width))
  cat(sprintf('Scan rate: %.1f Hz\n', optimal_scan_rate))
  
  # Check constraints
  if (optimal_window_width >= constraints$min_window_width && 
      optimal_scan_rate <= constraints$max_scan_rate &&
      optimal_windows <= constraints$max_windows) {
    cat('✅ All constraints satisfied!\n')
    final_windows <- optimal_windows
    final_width <- optimal_window_width
    final_dppp <- constraints$target_dppp
  } else {
    cat('❌ Constraints violated, using constrained solution:\n')
    final_windows <- max_practical_windows
    final_width <- constraints$mz_range / final_windows
    final_dppp <- achieved_dppp
    
    if (optimal_window_width < constraints$min_window_width) {
      cat(sprintf('- Window width %.1f < minimum %.1f m/z\n', 
                  optimal_window_width, constraints$min_window_width))
    }
    if (optimal_scan_rate > constraints$max_scan_rate) {
      cat(sprintf('- Scan rate %.1f > maximum %d Hz\n', 
                  optimal_scan_rate, constraints$max_scan_rate))
    }
  }
} else {
  final_windows <- max_practical_windows
  final_width <- constraints$mz_range / final_windows
  final_dppp <- achieved_dppp
}

cat('\n=== FINAL REALISTIC DESIGN ===\n')
cat(sprintf('Windows: %d\n', final_windows))
cat(sprintf('Average window width: %.1f m/z\n', final_width))
cat(sprintf('DPPP: %.2f\n', final_dppp))
cat(sprintf('Cycle time: %.1f ms\n', ms1_time + final_windows * ms2_time))
cat(sprintf('Scan rate: %.1f Hz\n', 1000 / (ms1_time + final_windows * ms2_time)))

# Test with actual implementation
cat('\n=== TESTING WITH ACTUAL IMPLEMENTATION ===\n')

result <- main_optimization(
  proteome_file = 'D:/Projects/DPPP_Window_isolation/DIANN-Output/report.parquet',
  instrument_preset = 'astral',
  target_dppp = constraints$target_dppp,
  rt_segments = 1,
  window_mode = 'dynamic',
  overlap_mode = 'fixed',
  overlap_value = 1,
  ms1_time = ms1_time,
  ms2_time = ms2_time,
  min_window_width = constraints$min_window_width,
  max_window_width = 50,  # Reasonable upper limit
  fixed_window = TRUE,    # Use fixed window count to respect constraints
  fixed_n_windows = final_windows,
  create_plots = FALSE
)

cat(sprintf('Implementation result: %d windows, DPPP %.2f\n', 
            result$windows$n_windows, result$windows$dppp))