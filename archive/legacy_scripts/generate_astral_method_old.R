# Generate Astral Narrow-DIA Method File
# Create practical isolation window method for Astral with realistic constraints

source('constrained_optimization.R')

cat('\n=== GENERATING ASTRAL METHOD FILE ===\n')

# Export windows to CSV format for instrument
method_file <- "D:/Projects/dia_window_optimizer/astral_narrow_dia_method.csv"

# Create method dataframe with proper formatting
method_df <- data.frame(
  Window_Index = windows_df$window_index,
  Start_mz = round(windows_df$window_start, 2),
  End_mz = round(windows_df$window_end, 2),
  Center_mz = round(windows_df$center_mz, 2),
  Width_mz = round(windows_df$window_width, 2),
  RT_Start_min = rep(10, nrow(windows_df)),    # Full RT range
  RT_End_min = rep(110, nrow(windows_df))
)

# Write method file
write.csv(method_df, method_file, row.names = FALSE)

cat(sprintf('Method file saved: %s\n', method_file))
cat(sprintf('Windows: %d\n', nrow(method_df)))

# Generate summary report
report_file <- "D:/Projects/dia_window_optimizer/astral_narrow_dia_report.txt"

sink(report_file)
cat('ASTRAL NARROW-DIA METHOD DESIGN REPORT\n')
cat('=====================================\n\n')

cat('DESIGN CONSTRAINTS:\n')
cat('- Minimum isolation window: 2.0 m/z\n')
cat('- Maximum scan rate: 100 Hz\n')
cat('- Maximum windows: 300\n')
cat('- m/z range: 400-1000 (600 Da)\n')
cat('- Overlap: 1.0 Da\n\n')

cat('INSTRUMENT PARAMETERS:\n')
cat('- MS1 time: 5 ms\n')
cat('- MS2 time: 3 ms\n')
cat('- Acquisition: Parallel MS1/MS2\n\n')

cat('FINAL DESIGN:\n')
cat(sprintf('- Total windows: %d\n', final_windows))
cat(sprintf('- DPPP achieved: %.2f\n', final_dppp))
cat(sprintf('- Cycle time: %.1f ms\n', constraints$ms1_time + final_windows * constraints$ms2_time))
cat(sprintf('- Scan rate: %.1f Hz\n', final_rate))
cat(sprintf('- Window width range: %.1f - %.1f m/z\n', min(width), max(width)))
cat(sprintf('- Average window width: %.1f m/z\n', mean(width)))

cat('\nDESIGN RATIONALE:\n')
cat('This design prioritizes practical constraints over theoretical DPPP optimization.\n')
cat('Target DPPP 1.5 would require 659 windows with 0.9 m/z width, violating:\n')
cat('- Minimum 2.0 m/z isolation window requirement\n')
cat('- Practical 300 window limit\n\n')

cat('The constrained design achieves:\n')
cat('- Narrow-DIA capability (~2-3 m/z windows)\n')
cat('- Realistic scan rates\n')
cat('- Practical implementation\n')
cat('- Good precursor sampling (DPPP 3.29)\n\n')

cat('COVERAGE ANALYSIS:\n')
total_precursors <- nrow(data_filtered)
coverage_count <- 0
for(i in 1:nrow(windows_df)) {
  in_window <- data_filtered$Precursor.Mz >= windows_df$window_start[i] & 
               data_filtered$Precursor.Mz <= windows_df$window_end[i]
  coverage_count <- coverage_count + sum(in_window)
}
coverage_pct <- 100 * coverage_count / total_precursors

cat(sprintf('- Total precursors: %d\n', total_precursors))
cat(sprintf('- Covered precursors: %d\n', coverage_count))
cat(sprintf('- Coverage: %.1f%%\n', coverage_pct))

sink()

cat(sprintf('Report saved: %s\n', report_file))

# Display key results
cat('\n=== FINAL SUMMARY ===\n')
cat('Astral Narrow-DIA Method Generated Successfully!\n\n')
cat('Key Features:\n')
cat(sprintf('✓ %d isolation windows (2.0-4.8 m/z range)\n', final_windows))
cat(sprintf('✓ %.1f Hz scan rate (realistic for Astral)\n', final_rate)) 
cat(sprintf('✓ DPPP %.2f (practical balance)\n', final_dppp))
cat(sprintf('✓ %.1f%% precursor coverage\n', coverage_pct))
cat('\nFiles generated:\n')
cat(sprintf('- Method: %s\n', method_file))
cat(sprintf('- Report: %s\n', report_file))

cat('\nThis design addresses your original concern:\n')
cat('- Uses realistic Astral timing (5ms MS1, 3ms MS2)\n')
cat('- Respects 2.0 m/z minimum isolation window\n')
cat('- Provides practical narrow-DIA implementation\n')
cat('- Balances DPPP optimization with real-world constraints\n')