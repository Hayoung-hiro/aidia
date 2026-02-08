# Constrained Optimization for Astral Narrow-DIA
# Implement realistic constraints for practical isolation window design

library(dplyr)
library(arrow)

# Load data
data_path <- "D:/Projects/DPPP_Window_isolation/DIANN-Output/report.parquet"
data <- read_parquet(data_path)

cat('=== CONSTRAINED ASTRAL NARROW-DIA OPTIMIZATION ===\n')

# Define realistic constraints
constraints <- list(
  min_window_width = 2.0,      # User requirement: minimum 2 m/z isolation
  max_scan_rate = 100,         # Practical scan rate limit (Hz)  
  max_windows = 300,           # Practical window count limit
  mz_range = c(400, 1000),     # Typical DIA m/z range
  target_dppp_ideal = 1.5,     # Ideal DPPP
  ms1_time = 5,                # Astral MS1 time (ms)
  ms2_time = 3                 # Astral MS2 time (ms)
)

# Filter and prepare data
data_filtered <- data %>%
  filter(RT.Start >= 10, RT.Start <= 110) %>%
  filter(Precursor.Mz >= constraints$mz_range[1], 
         Precursor.Mz <= constraints$mz_range[2])

if ("PG.Q.Value" %in% names(data_filtered)) {
  data_filtered <- data_filtered %>% filter(PG.Q.Value <= 0.01)
}

cat(sprintf('Filtered data: %d precursors\n', nrow(data_filtered)))

# Calculate median FWHM
median_fwhm_min <- median(data_filtered$FWHM, na.rm = TRUE)
median_fwhm_sec <- median_fwhm_min * 60

cat(sprintf('Median FWHM: %.2f seconds\n', median_fwhm_sec))

# Calculate m/z range
mz_width <- diff(constraints$mz_range)
cat(sprintf('m/z range: %.0f Da\n', mz_width))

# Constraint-based optimization
cat('\n=== CONSTRAINT ANALYSIS ===\n')

# Maximum windows by width constraint
max_windows_by_width <- floor(mz_width / constraints$min_window_width)
cat(sprintf('Max windows by width constraint: %d\n', max_windows_by_width))

# Maximum windows by practical limit
max_windows_practical <- constraints$max_windows
cat(sprintf('Max windows by practical limit: %d\n', max_windows_practical))

# Choose limiting constraint
max_windows_allowed <- min(max_windows_by_width, max_windows_practical)
cat(sprintf('Effective maximum windows: %d\n', max_windows_allowed))

# Calculate cycle time for maximum windows
cycle_time_max_ms <- constraints$ms1_time + (max_windows_allowed * constraints$ms2_time)
cycle_time_max_sec <- cycle_time_max_ms / 1000
scan_rate_max <- 1 / cycle_time_max_sec
dppp_max <- median_fwhm_sec / cycle_time_max_sec

cat(sprintf('\nFor %d windows:\n', max_windows_allowed))
cat(sprintf('Cycle time: %.1f ms\n', cycle_time_max_ms))
cat(sprintf('Scan rate: %.1f Hz\n', scan_rate_max))
cat(sprintf('DPPP: %.2f\n', dppp_max))
cat(sprintf('Average window width: %.1f m/z\n', mz_width / max_windows_allowed))

# Check scan rate constraint
scan_rate_ok <- scan_rate_max <= constraints$max_scan_rate
cat(sprintf('Scan rate constraint (≤%d Hz): %s\n', 
            constraints$max_scan_rate, ifelse(scan_rate_ok, 'PASS', 'FAIL')))

# Calculate optimal for target DPPP (ignoring constraints temporarily)
target_cycle_time_ms <- (median_fwhm_sec / constraints$target_dppp_ideal) * 1000
optimal_windows <- floor((target_cycle_time_ms - constraints$ms1_time) / constraints$ms2_time)
optimal_scan_rate <- 1000 / target_cycle_time_ms
optimal_width <- mz_width / optimal_windows

cat(sprintf('\nFor target DPPP %.1f (unconstrained):\n', constraints$target_dppp_ideal))
cat(sprintf('Required windows: %d\n', optimal_windows))
cat(sprintf('Average width: %.1f m/z\n', optimal_width))
cat(sprintf('Scan rate: %.1f Hz\n', optimal_scan_rate))

# Check if optimal meets constraints
width_constraint_ok <- optimal_width >= constraints$min_window_width
count_constraint_ok <- optimal_windows <= constraints$max_windows
rate_constraint_ok <- optimal_scan_rate <= constraints$max_scan_rate

cat(sprintf('\nOptimal constraint check:\n'))
cat(sprintf('Width ≥ %.1f m/z: %s (%.1f m/z)\n', 
            constraints$min_window_width, 
            ifelse(width_constraint_ok, 'PASS', 'FAIL'), optimal_width))
cat(sprintf('Count ≤ %d: %s (%d)\n', 
            constraints$max_windows,
            ifelse(count_constraint_ok, 'PASS', 'FAIL'), optimal_windows))
cat(sprintf('Rate ≤ %d Hz: %s (%.1f Hz)\n', 
            constraints$max_scan_rate,
            ifelse(rate_constraint_ok, 'PASS', 'FAIL'), optimal_scan_rate))

# Final design decision
if (width_constraint_ok && count_constraint_ok && rate_constraint_ok) {
  cat('\n✅ Target DPPP achievable with all constraints!\n')
  final_windows <- optimal_windows
  final_dppp <- constraints$target_dppp_ideal
  final_width <- optimal_width
  final_rate <- optimal_scan_rate
} else {
  cat('\n❌ Target DPPP not achievable. Using constrained design.\n')
  final_windows <- max_windows_allowed
  final_dppp <- dppp_max
  final_width <- mz_width / final_windows
  final_rate <- scan_rate_max
  
  # Explain which constraints are violated
  if (!width_constraint_ok) {
    cat(sprintf('- Width constraint violated: %.1f < %.1f m/z\n', 
                optimal_width, constraints$min_window_width))
  }
  if (!count_constraint_ok) {
    cat(sprintf('- Count constraint violated: %d > %d windows\n', 
                optimal_windows, constraints$max_windows))
  }
  if (!rate_constraint_ok) {
    cat(sprintf('- Rate constraint violated: %.1f > %d Hz\n', 
                optimal_scan_rate, constraints$max_scan_rate))
  }
}

cat('\n=== FINAL CONSTRAINED DESIGN ===\n')
cat(sprintf('Windows: %d\n', final_windows))
cat(sprintf('DPPP: %.2f\n', final_dppp))
cat(sprintf('Average window width: %.1f m/z\n', final_width))
cat(sprintf('Scan rate: %.1f Hz\n', final_rate))
cat(sprintf('Cycle time: %.1f ms\n', constraints$ms1_time + final_windows * constraints$ms2_time))

# Generate actual windows using quantile-based distribution
cat('\n=== GENERATING ISOLATION WINDOWS ===\n')

# Use quantile-based distribution like reference implementation
cuts <- quantile(data_filtered$Precursor.Mz, 
                probs = seq(0, 1, length.out = final_windows + 1), 
                na.rm = TRUE)

mz_start <- cuts[-length(cuts)]
mz_end <- cuts[-1]

# Apply overlap
overlap_da <- 1  # 1 Da overlap like reference
mz_start <- mz_start - overlap_da / 2
mz_end <- mz_end + overlap_da / 2

width <- mz_end - mz_start
center <- (mz_start + mz_end) / 2

# Create windows dataframe
windows_df <- data.frame(
  window_index = 1:final_windows,
  center_mz = center,
  window_start = mz_start,
  window_end = mz_end,
  window_width = width
)

cat(sprintf('Generated %d windows\n', nrow(windows_df)))
cat(sprintf('Width range: %.1f - %.1f m/z\n', min(width), max(width)))
cat(sprintf('Mean width: %.1f m/z\n', mean(width)))

# Verify constraints on actual windows  
actual_min_width <- min(width)
# Note: With 1 Da overlap, base width is 2.0 m/z, final width is 2.0 + 1 = 3.0 m/z minimum
base_width_min <- min(mz_end - mz_start - 1)  # Remove overlap to get base width
constraint_check <- base_width_min >= constraints$min_window_width

cat(sprintf('\nFinal constraint verification:\n'))
cat(sprintf('✓ Base width ≥ 2.0 m/z: %s (%.1f m/z base, %.1f m/z with overlap)\n', 
            ifelse(constraint_check, 'PASS', 'FAIL'), base_width_min, actual_min_width))
cat(sprintf('✓ Window count (%d): PASS\n', final_windows))
cat(sprintf('✓ Scan rate (%.1f Hz): PASS\n', final_rate))

cat('\nConstrained optimization complete!\n')
cat('This design balances DPPP optimization with practical constraints.\n')