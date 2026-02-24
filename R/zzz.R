# zzz.R - Loaded last by R during package build
# Declares non-standard evaluation (NSE) variables to suppress R CMD check NOTEs
# about "no visible binding for global variable".

utils::globalVariables(c(
  # Column names from DIA-NN data
  "Precursor.Mz", "Precursor.Id", "RT.Apex", "RT.Start", "FWHM", "FWHM_sec",
  "Precursor.Quantity", "Protein.Group", "Q.Value", "Global.Q.Value",
  "Lib.Q.Value", "PG.Q.Value", "PG.MaxLFQ.Quality", "Quantity.Quality",
  "Channel.Q.Value", "Intensity_CV_pct",

  # Window/optimization columns
  "rt_segment_id", "rt_start", "rt_end", "rt_label", "rt_group", "rt_center",
  "rt_midpoint", "rt_bin_start",
  "mz_start", "mz_end", "mz_center", "mz_min", "mz_max", "mz_width", "mz_seq",
  "window_width", "window_id", "window_index", "width", "width_seq", "width_type",
  "original_width", "optimized_width", "original_min", "original_max",
  "reduction_pct", "Original", "Optimized",

  # Strategy/plotting
  "strategy", "strategy_internal", "strategy_label",
  "Coverage", "Coverage_Pct", "Mean Width", "Mean_Width_Da",
  "Windows", "Range Utilization", "Range_Utilization", "Strategy",
  "coverage_ratio", "n_precursors", "pct",

  # Plot aesthetics/variables
  "x", "y", "xend", "yend", "color", "state", "label", "value",
  "value_display", "value_norm", "metric", "rt", "mz", "density",
  "normalized_density", "scaled", "significant", "satisfaction_pct",
  "cycle_time", "current_dppp", "expected_dppp", "dppp",
  "condition", "range_type", "ks_stat",

  # Export columns
  "Compound", "Formula", "Adduct", "m/z", "z", "t start (min)", "t stop (min)",
  "Start (m/z)", "End (m/z)", "Isolation Window (m/z)", "Normalized AGC Target (%)",
  "RT_Center", "RT_Width", "RT_Segment_ID", "Window_ID", "Window_Type",
  "Generation_Method", "Recommended_Cycle_Time_Sec", "Overlap_Prev", "Overlap_Next",
  "Instrument", "N_Precursors",

  # Replicate handling
  "n_replicates",

  # Functions that appear as NSE
  "deframe", "load_raw_metadata", "hist", "read.delim"
))
