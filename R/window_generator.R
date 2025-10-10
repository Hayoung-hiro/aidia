# window_generator.R - Module 4: Interactive Window Method Generator
#
# PURPOSE:
#   Generate isolation window methods based on DPPP analysis, RT segmentation,
#   and density distribution. Supports fixed, variable, and overlapped window types
#   with both static (single RT) and dynamic (RT-dependent) modes.
#
# INTEGRATION:
#   - Module 1: Uses scan_time recommendations and DPPP targets
#   - Module 2: Uses RT segmentation strategies (uniform/density/quantile)
#   - Module 3: Uses RT-dependent density analysis for adaptive sizing
#
# WINDOW TYPES:
#   - Fixed: Equal width windows across m/z range
#   - Variable: Density-based adaptive width (more windows in high-density regions)
#   - Overlapped: Fixed or variable windows with user-defined overlap
#
# MODES:
#   - Static: Single window scheme for entire gradient
#   - Dynamic: RT-dependent window schemes (different windows per RT segment)

library(dplyr)
library(tidyr)

#' Generate Fixed-Width Isolation Windows
#'
#' Creates isolation windows with equal width across the m/z range.
#' Simplest approach, suitable for uniform precursor distribution.
#'
#' @param mz_range Numeric vector c(min, max) for m/z range
#' @param target_window_count Integer number of windows to generate
#' @param overlap_percentage Numeric overlap between windows (0-0.99)
#' @param min_width Numeric minimum window width (Da)
#' @param max_width Numeric maximum window width (Da)
#'
#' @return Data frame with columns: window_id, mz_start, mz_end, mz_center, width
#'
#' @examples
#' windows <- generate_fixed_windows(c(400, 1000), target_window_count = 30)
#' windows_overlap <- generate_fixed_windows(c(400, 1000), 30, overlap_percentage = 0.5)
generate_fixed_windows <- function(mz_range,
                                  target_window_count,
                                  overlap_percentage = 0,
                                  min_width = 2.0,
                                  max_width = 50.0) {

  # Validate inputs
  if (length(mz_range) != 2 || mz_range[1] >= mz_range[2]) {
    stop("mz_range must be c(min, max) with min < max")
  }
  if (target_window_count < 1) {
    stop("target_window_count must be >= 1")
  }
  if (overlap_percentage < 0 || overlap_percentage >= 1) {
    stop("overlap_percentage must be in [0, 1)")
  }

  total_range <- mz_range[2] - mz_range[1]

  # Calculate effective window width considering overlap
  # If overlap = 0.5, windows advance by 0.5 * width
  # Total coverage: start + (n-1) * width * (1 - overlap) + width = end
  # Solving: width = (end - start) / (n - overlap * (n-1))

  if (overlap_percentage > 0) {
    window_width <- total_range / (target_window_count - overlap_percentage * (target_window_count - 1))
  } else {
    window_width <- total_range / target_window_count
  }

  # Apply width constraints
  if (window_width < min_width) {
    warning(sprintf("Calculated width %.2f Da < min_width %.2f Da. Using min_width.",
                   window_width, min_width))
    window_width <- min_width
    # Recalculate window count
    target_window_count <- ceiling(total_range / (window_width * (1 - overlap_percentage)))
  }

  if (window_width > max_width) {
    warning(sprintf("Calculated width %.2f Da > max_width %.2f Da. Using max_width.",
                   window_width, max_width))
    window_width <- max_width
    # Recalculate window count
    target_window_count <- ceiling(total_range / (window_width * (1 - overlap_percentage)))
  }

  # Generate window boundaries
  windows <- data.frame(
    window_id = 1:target_window_count,
    mz_start = numeric(target_window_count),
    mz_end = numeric(target_window_count)
  )

  step_size <- window_width * (1 - overlap_percentage)

  for (i in 1:target_window_count) {
    windows$mz_start[i] <- mz_range[1] + (i - 1) * step_size
    windows$mz_end[i] <- windows$mz_start[i] + window_width
  }

  # Ensure last window covers the range
  windows$mz_end[target_window_count] <- max(windows$mz_end[target_window_count], mz_range[2])

  # Calculate center and width
  windows <- windows %>%
    mutate(
      mz_center = (mz_start + mz_end) / 2,
      width = mz_end - mz_start
    )

  return(windows)
}


#' Generate Variable-Width Isolation Windows (Density-Based)
#'
#' Creates adaptive windows based on precursor density distribution.
#' More windows (narrower) in high-density regions for better selectivity.
#' Fewer windows (wider) in low-density regions for efficiency.
#'
#' @param data Data frame with Precursor.Mz column
#' @param mz_range Numeric vector c(min, max) for m/z range
#' @param target_window_count Integer target number of windows (approximate)
#' @param density_bins Integer number of bins for density calculation
#' @param adaptation_strength Numeric 0-1, strength of density-based adaptation
#' @param min_width Numeric minimum window width (Da)
#' @param max_width Numeric maximum window width (Da)
#' @param overlap_percentage Numeric overlap between windows (0-0.99)
#'
#' @return Data frame with columns: window_id, mz_start, mz_end, mz_center, width, density_score
#'
#' @examples
#' windows <- generate_variable_windows(data, c(400, 1000), 30, adaptation_strength = 0.7)
generate_variable_windows <- function(data,
                                     mz_range,
                                     target_window_count,
                                     density_bins = 100,
                                     adaptation_strength = 0.5,
                                     min_width = 2.0,
                                     max_width = 50.0,
                                     overlap_percentage = 0) {

  # Validate inputs
  if (!"Precursor.Mz" %in% names(data)) {
    stop("data must contain 'Precursor.Mz' column")
  }
  if (adaptation_strength < 0 || adaptation_strength > 1) {
    stop("adaptation_strength must be in [0, 1]")
  }

  # Calculate precursor density across m/z range
  mz_data <- data %>%
    filter(Precursor.Mz >= mz_range[1], Precursor.Mz <= mz_range[2])

  if (nrow(mz_data) == 0) {
    stop("No precursors found in specified m/z range")
  }

  # Create density histogram
  breaks <- seq(mz_range[1], mz_range[2], length.out = density_bins + 1)
  density_hist <- hist(mz_data$Precursor.Mz, breaks = breaks, plot = FALSE)

  # Calculate density score for each bin (normalized 0-1)
  density_scores <- density_hist$counts / max(density_hist$counts)
  bin_centers <- density_hist$mids

  # Adaptive window width calculation
  # High density → narrow windows (min_width)
  # Low density → wide windows (max_width)
  # adaptation_strength controls how much density influences width

  # Inverse relationship: high density → small width multiplier
  width_multipliers <- 1 - (density_scores * adaptation_strength)

  # Map to actual widths
  adaptive_widths <- min_width + width_multipliers * (max_width - min_width)

  # Generate windows by traversing m/z range with adaptive widths
  windows <- list()
  current_mz <- mz_range[1]
  window_id <- 1

  while (current_mz < mz_range[2]) {
    # Find current density bin
    bin_idx <- findInterval(current_mz, breaks)
    bin_idx <- max(1, min(bin_idx, length(adaptive_widths)))

    # Get adaptive width for this region
    current_width <- adaptive_widths[bin_idx]

    # Calculate window end
    mz_end <- min(current_mz + current_width, mz_range[2])

    # Store window
    windows[[window_id]] <- data.frame(
      window_id = window_id,
      mz_start = current_mz,
      mz_end = mz_end,
      mz_center = (current_mz + mz_end) / 2,
      width = mz_end - current_mz,
      density_score = density_scores[bin_idx]
    )

    # Advance position considering overlap
    step_size <- current_width * (1 - overlap_percentage)
    current_mz <- current_mz + step_size
    window_id <- window_id + 1

    # Safety check to prevent infinite loop
    if (window_id > target_window_count * 3) {
      warning("Window generation exceeded 3x target count. Stopping.")
      break
    }
  }

  # Combine all windows
  windows_df <- bind_rows(windows)

  # If window count differs significantly from target, adjust
  actual_count <- nrow(windows_df)
  if (abs(actual_count - target_window_count) / target_window_count > 0.2) {
    message(sprintf("Variable windows: target=%d, actual=%d (%.1f%% difference)",
                   target_window_count, actual_count,
                   100 * (actual_count - target_window_count) / target_window_count))
  }

  return(windows_df)
}


#' Generate RT-Dependent Dynamic Windows
#'
#' Creates RT-segment-specific window schemes. Each RT segment can have
#' different window configurations based on local precursor characteristics.
#'
#' @param data Data frame with Precursor.Mz and RT.Start columns
#' @param rt_segments Data frame from segment_rt_* functions (Module 2)
#' @param window_type Character: "fixed", "variable", or "overlapped"
#' @param target_windows_per_segment Integer or vector of window counts per segment
#' @param overlap_percentage Numeric overlap between windows
#' @param adaptation_strength Numeric for variable windows (0-1)
#' @param min_width Numeric minimum window width (Da)
#' @param max_width Numeric maximum window width (Da)
#'
#' @return List with:
#'   - windows: Data frame with window definitions including rt_segment_id
#'   - segment_summary: Summary statistics per RT segment
#'   - transition_points: RT boundaries where window schemes change
#'
#' @examples
#' rt_segs <- segment_rt_uniform(data, n_segments = 5)
#' dynamic_windows <- generate_rt_dependent_windows(
#'   data, rt_segs, "variable", target_windows_per_segment = 25
#' )
generate_rt_dependent_windows <- function(data,
                                         rt_segments,
                                         window_type = "fixed",
                                         target_windows_per_segment = 25,
                                         overlap_percentage = 0,
                                         adaptation_strength = 0.5,
                                         min_width = 2.0,
                                         max_width = 50.0) {

  # Validate inputs
  required_cols <- c("Precursor.Mz", "RT.Start")
  if (!all(required_cols %in% names(data))) {
    stop("data must contain 'Precursor.Mz' and 'RT.Start' columns")
  }

  # Handle RT segments structure
  # RT segmentation functions return a list with 'stats' component
  # Extract stats dataframe if list structure detected
  if (is.list(rt_segments) && "stats" %in% names(rt_segments)) {
    message("Detected RT segmentation list structure, extracting stats component")
    rt_segments <- rt_segments$stats
  }

  # Validate RT segments structure
  required_rt_cols <- c("rt_start", "rt_end")
  if (!all(required_rt_cols %in% names(rt_segments))) {
    stop(sprintf("rt_segments must contain columns: %s. Found: %s",
                paste(required_rt_cols, collapse = ", "),
                paste(names(rt_segments), collapse = ", ")))
  }

  # Check for segment identifier column (can be 'rt_segment', 'segment', or similar)
  segment_col <- names(rt_segments)[1]  # Use first column as segment identifier
  if (! segment_col %in% c("rt_segment", "segment", "segment_id", "segment_name")) {
    # If first column is not obviously a segment column, look for it
    if ("rt_segment" %in% names(rt_segments)) {
      segment_col <- "rt_segment"
    } else {
      segment_col <- names(rt_segments)[1]  # Default to first column
    }
  }

  window_type <- match.arg(window_type, c("fixed", "variable", "overlapped"))

  # If single target provided, use for all segments
  if (length(target_windows_per_segment) == 1) {
    target_windows_per_segment <- rep(target_windows_per_segment, nrow(rt_segments))
  }

  if (length(target_windows_per_segment) != nrow(rt_segments)) {
    stop("target_windows_per_segment must be single value or match number of RT segments")
  }

  # Join data with RT segments
  # Create segment labels from rt_segments dataframe
  segment_labels <- as.character(rt_segments[[segment_col]])

  data_segmented <- data %>%
    mutate(rt_segment = cut(RT.Start,
                           breaks = c(rt_segments$rt_start, max(rt_segments$rt_end)),
                           labels = segment_labels,
                           include.lowest = TRUE))

  # Generate windows for each RT segment
  all_windows <- list()
  segment_summaries <- list()

  for (i in 1:nrow(rt_segments)) {
    seg_name <- segment_labels[i]
    seg_data <- data_segmented %>% filter(rt_segment == seg_name)

    if (nrow(seg_data) == 0) {
      warning(sprintf("No precursors in RT segment %s, skipping", seg_name))
      next
    }

    # Get m/z range for this segment
    mz_range_seg <- c(min(seg_data$Precursor.Mz), max(seg_data$Precursor.Mz))

    # Generate windows based on type
    if (window_type == "fixed") {
      windows_seg <- generate_fixed_windows(
        mz_range = mz_range_seg,
        target_window_count = target_windows_per_segment[i],
        overlap_percentage = overlap_percentage,
        min_width = min_width,
        max_width = max_width
      )
    } else if (window_type == "variable") {
      windows_seg <- generate_variable_windows(
        data = seg_data,
        mz_range = mz_range_seg,
        target_window_count = target_windows_per_segment[i],
        adaptation_strength = adaptation_strength,
        min_width = min_width,
        max_width = max_width,
        overlap_percentage = overlap_percentage
      )
    } else { # overlapped (treat as fixed with overlap)
      windows_seg <- generate_fixed_windows(
        mz_range = mz_range_seg,
        target_window_count = target_windows_per_segment[i],
        overlap_percentage = max(0.5, overlap_percentage), # Ensure meaningful overlap
        min_width = min_width,
        max_width = max_width
      )
    }

    # Add RT segment information
    # Calculate rt_center if not present
    rt_center_value <- if("rt_center" %in% names(rt_segments)) {
      rt_segments$rt_center[i]
    } else {
      (rt_segments$rt_start[i] + rt_segments$rt_end[i]) / 2
    }

    windows_seg <- windows_seg %>%
      mutate(
        rt_segment_id = i,
        rt_segment_name = seg_name,
        rt_start = rt_segments$rt_start[i],
        rt_end = rt_segments$rt_end[i],
        rt_center = rt_center_value
      )

    all_windows[[i]] <- windows_seg

    # Create segment summary
    segment_summaries[[i]] <- data.frame(
      rt_segment_id = i,
      rt_segment_name = seg_name,
      rt_start = rt_segments$rt_start[i],
      rt_end = rt_segments$rt_end[i],
      n_windows = nrow(windows_seg),
      n_precursors = nrow(seg_data),
      precursors_per_window = nrow(seg_data) / nrow(windows_seg),
      mean_window_width = mean(windows_seg$width),
      mz_range_min = mz_range_seg[1],
      mz_range_max = mz_range_seg[2]
    )
  }

  # Combine all segments
  windows_df <- bind_rows(all_windows)
  summary_df <- bind_rows(segment_summaries)

  # Extract transition points for instrument programming
  transition_points <- rt_segments %>%
    mutate(segment_name = segment_labels) %>%
    select(segment_name, rt_start, rt_end) %>%
    mutate(
      transition_type = "RT_segment_boundary",
      window_scheme_id = row_number()
    )

  return(list(
    windows = windows_df,
    segment_summary = summary_df,
    transition_points = transition_points,
    window_type = window_type,
    n_segments = nrow(rt_segments),
    total_windows = nrow(windows_df)
  ))
}


#' Calculate Window Coverage and Statistics
#'
#' Analyzes how well the generated windows cover the precursor population.
#' Identifies gaps, overlaps, and coverage efficiency.
#'
#' @param data Data frame with Precursor.Mz column
#' @param windows Data frame from generate_*_windows functions
#' @param rt_column Character name of RT column (optional, for RT-dependent analysis)
#'
#' @return List with:
#'   - coverage_stats: Overall coverage statistics
#'   - precursor_assignments: Data frame showing which window each precursor falls into
#'   - gap_regions: m/z regions with no window coverage
#'   - overlap_regions: m/z regions with multiple window overlaps
#'
#' @examples
#' coverage <- calculate_window_coverage(data, windows)
#' print(coverage$coverage_stats)
calculate_window_coverage <- function(data, windows, rt_column = NULL) {

  # Validate inputs
  if (!"Precursor.Mz" %in% names(data)) {
    stop("data must contain 'Precursor.Mz' column")
  }

  required_window_cols <- c("mz_start", "mz_end")
  if (!all(required_window_cols %in% names(windows))) {
    stop("windows must contain 'mz_start' and 'mz_end' columns")
  }

  # Assign each precursor to windows (can be multiple if overlapped)
  precursor_assignments <- data %>%
    select(Precursor.Mz, any_of(rt_column)) %>%
    mutate(precursor_id = row_number()) %>%
    rowwise() %>%
    mutate(
      assigned_windows = list(
        windows %>%
          filter(mz_start <= Precursor.Mz, Precursor.Mz <= mz_end) %>%
          pull(window_id)
      ),
      n_windows_assigned = length(unlist(assigned_windows)),  # Use unlist to handle empty lists
      is_covered = n_windows_assigned > 0
    ) %>%
    ungroup()

  # Calculate coverage statistics
  total_precursors <- nrow(precursor_assignments)
  covered_precursors <- sum(precursor_assignments$is_covered)
  uncovered_precursors <- total_precursors - covered_precursors
  multi_covered <- sum(precursor_assignments$n_windows_assigned > 1)

  coverage_ratio <- covered_precursors / total_precursors
  multi_coverage_ratio <- multi_covered / total_precursors

  # Identify gap regions (m/z ranges with no window coverage)
  mz_range <- range(data$Precursor.Mz)
  all_ranges <- data.frame(
    start = windows$mz_start,
    end = windows$mz_end
  ) %>%
    arrange(start)

  gaps <- data.frame()
  if (nrow(all_ranges) > 0) {
    # Check gap before first window
    if (all_ranges$start[1] > mz_range[1]) {
      gaps <- rbind(gaps, data.frame(
        gap_start = mz_range[1],
        gap_end = all_ranges$start[1],
        gap_width = all_ranges$start[1] - mz_range[1]
      ))
    }

    # Check gaps between consecutive windows
    for (i in 1:(nrow(all_ranges) - 1)) {
      if (all_ranges$end[i] < all_ranges$start[i + 1]) {
        gaps <- rbind(gaps, data.frame(
          gap_start = all_ranges$end[i],
          gap_end = all_ranges$start[i + 1],
          gap_width = all_ranges$start[i + 1] - all_ranges$end[i]
        ))
      }
    }

    # Check gap after last window
    if (all_ranges$end[nrow(all_ranges)] < mz_range[2]) {
      gaps <- rbind(gaps, data.frame(
        gap_start = all_ranges$end[nrow(all_ranges)],
        gap_end = mz_range[2],
        gap_width = mz_range[2] - all_ranges$end[nrow(all_ranges)]
      ))
    }
  }

  # Identify overlap regions
  overlaps <- windows %>%
    arrange(mz_start) %>%
    mutate(
      next_start = lead(mz_start),
      overlap_width = pmax(0, mz_end - next_start, na.rm = TRUE),
      has_overlap = !is.na(overlap_width) & overlap_width > 0
    ) %>%
    filter(has_overlap) %>%
    select(window_id, mz_start, mz_end, next_start, overlap_width)

  # Summary statistics
  coverage_stats <- list(
    total_precursors = total_precursors,
    covered_precursors = covered_precursors,
    uncovered_precursors = uncovered_precursors,
    coverage_ratio = coverage_ratio,
    coverage_percentage = coverage_ratio * 100,
    multi_covered_precursors = multi_covered,
    multi_coverage_ratio = multi_coverage_ratio,
    mean_windows_per_precursor = mean(precursor_assignments$n_windows_assigned[precursor_assignments$is_covered]),
    total_windows = nrow(windows),
    mean_window_width = mean(windows$width),
    total_gaps = nrow(gaps),
    total_gap_width = if(nrow(gaps) > 0) sum(gaps$gap_width) else 0,
    total_overlaps = nrow(overlaps),
    total_overlap_width = if(nrow(overlaps) > 0) sum(overlaps$overlap_width) else 0
  )

  return(list(
    coverage_stats = coverage_stats,
    precursor_assignments = precursor_assignments,
    gap_regions = gaps,
    overlap_regions = overlaps
  ))
}


#' Export Windows to Instrument Method Format
#'
#' Converts generated windows to instrument-compatible format.
#' Supports both static and dynamic (RT-dependent) methods.
#'
#' @param windows Data frame from generate_*_windows functions
#' @param output_file Character path to output CSV file
#' @param instrument_type Character: "astral", "orbitrap_exploris", "orbitrap", "timstof", etc.
#' @param method_name Character name for the method
#' @param include_metadata Logical whether to include method metadata
#'
#' @return Invisible path to output file
#'
#' @examples
#' export_windows_to_method(windows, "optimized_method.csv", "astral", "DIA_optimized_v1")
export_windows_to_method <- function(windows,
                                    output_file,
                                    instrument_type = "astral",
                                    method_name = "DIA_optimized",
                                    include_metadata = TRUE) {

  # Check if RT-dependent (has rt_segment_id column)
  is_dynamic <- "rt_segment_id" %in% names(windows)

  # Prepare method data frame
  if (is_dynamic) {
    method_df <- windows %>%
      select(
        window_id,
        rt_segment = rt_segment_name,
        rt_start,
        rt_end,
        mz_start,
        mz_end,
        mz_center,
        width
      ) %>%
      arrange(rt_start, mz_start)
  } else {
    method_df <- windows %>%
      select(
        window_id,
        mz_start,
        mz_end,
        mz_center,
        width
      ) %>%
      arrange(mz_start)
  }

  # Add instrument-specific columns if needed
  if (tolower(instrument_type) %in% c("astral", "orbitrap_exploris", "orbitrap")) {
    # Thermo-specific: collision energy, AGC target, etc.
    method_df <- method_df %>%
      mutate(
        collision_energy = 30, # Default NCE
        agc_target = "standard"
      )
  }

  # Add metadata header if requested
  if (include_metadata) {
    metadata <- data.frame(
      metadata = c(
        sprintf("# Method Name: %s", method_name),
        sprintf("# Instrument: %s", instrument_type),
        sprintf("# Generated: %s", Sys.time()),
        sprintf("# Total Windows: %d", nrow(method_df)),
        sprintf("# Window Type: %s", if(is_dynamic) "RT-Dependent Dynamic" else "Static"),
        sprintf("# m/z Range: %.1f - %.1f", min(method_df$mz_start), max(method_df$mz_end)),
        if(is_dynamic) sprintf("# RT Segments: %d", length(unique(windows$rt_segment_id))) else NULL,
        "#"
      )
    )

    # Write metadata first
    write.table(metadata, output_file,
               quote = FALSE, row.names = FALSE, col.names = FALSE)

    # Append method data
    write.table(method_df, output_file,
               sep = ",", quote = FALSE, row.names = FALSE,
               append = TRUE)
  } else {
    # Write method data directly
    write.csv(method_df, output_file, row.names = FALSE, quote = FALSE)
  }

  message(sprintf("✓ Window method exported: %s", output_file))
  message(sprintf("  Total windows: %d", nrow(method_df)))
  if (is_dynamic) {
    message(sprintf("  RT segments: %d", length(unique(windows$rt_segment_id))))
    message(sprintf("  RT range: %.1f - %.1f min", min(windows$rt_start), max(windows$rt_end)))
  }
  message(sprintf("  m/z range: %.1f - %.1f", min(method_df$mz_start), max(method_df$mz_end)))
  message(sprintf("  Mean window width: %.2f Da", mean(method_df$width)))

  invisible(output_file)
}


#' Quick Window Generation Wrapper
#'
#' Convenient wrapper function for common window generation workflows.
#' Integrates with Modules 1-3 for complete optimization pipeline.
#'
#' @param data Data frame with DIA-NN output (Precursor.Mz, RT.Start, FWHM)
#' @param window_type Character: "fixed", "variable", or "overlapped"
#' @param mode Character: "static" or "dynamic" (RT-dependent)
#' @param target_dppp Numeric target DPPP value (from Module 1)
#' @param scan_time Numeric scan time in seconds (from Module 1 recommendation)
#' @param n_windows Integer target number of windows
#' @param rt_segments Integer number of RT segments (for dynamic mode)
#' @param rt_mode Character: "uniform", "density", or "quantile" (Module 2)
#' @param overlap_percentage Numeric overlap between windows
#' @param output_file Character path to output method file
#'
#' @return List with windows, coverage statistics, and export path
#'
#' @examples
#' result <- quick_generate_windows(
#'   data, "variable", "dynamic", target_dppp = 1.25, scan_time = 1.8
#' )
quick_generate_windows <- function(data,
                                  window_type = "fixed",
                                  mode = "static",
                                  target_dppp = 1.5,
                                  scan_time = 2.0,
                                  n_windows = 30,
                                  rt_segments = 5,
                                  rt_mode = "uniform",
                                  overlap_percentage = 0,
                                  output_file = "optimized_windows.csv") {

  mode <- match.arg(mode, c("static", "dynamic"))
  rt_mode <- match.arg(rt_mode, c("uniform", "density", "quantile"))

  message(sprintf("\n=== Quick Window Generation ==="))
  message(sprintf("Mode: %s | Type: %s", mode, window_type))
  message(sprintf("Target DPPP: %.2f | Scan time: %.2f sec", target_dppp, scan_time))

  # Get m/z range
  mz_range <- range(data$Precursor.Mz, na.rm = TRUE)
  message(sprintf("m/z range: %.1f - %.1f", mz_range[1], mz_range[2]))

  if (mode == "static") {
    # Generate static windows (single scheme for entire gradient)
    message(sprintf("\nGenerating %d %s windows...", n_windows, window_type))

    if (window_type == "fixed" || window_type == "overlapped") {
      windows <- generate_fixed_windows(
        mz_range = mz_range,
        target_window_count = n_windows,
        overlap_percentage = if(window_type == "overlapped") max(0.5, overlap_percentage) else overlap_percentage
      )
    } else if (window_type == "variable") {
      windows <- generate_variable_windows(
        data = data,
        mz_range = mz_range,
        target_window_count = n_windows,
        adaptation_strength = 0.6,
        overlap_percentage = overlap_percentage
      )
    }

    # Calculate coverage
    message("\nCalculating window coverage...")
    coverage <- calculate_window_coverage(data, windows)

    # Export method
    message("\nExporting window method...")
    export_windows_to_method(windows, output_file, method_name = sprintf("DIA_%s_%s", mode, window_type))

    result <- list(
      windows = windows,
      coverage = coverage,
      method_file = output_file,
      mode = mode,
      window_type = window_type
    )

  } else {
    # Generate dynamic RT-dependent windows
    message(sprintf("\nApplying RT segmentation: %s with %d segments", rt_mode, rt_segments))

    # Load RT segmentation from Module 2
    source("R/rt_segmentation.R")

    if (rt_mode == "uniform") {
      rt_segs <- segment_rt_uniform(data, n_segments = rt_segments)
    } else if (rt_mode == "density") {
      rt_segs <- segment_rt_density(data, n_segments = rt_segments)
    } else {
      rt_segs <- segment_rt_quantile(data, n_segments = rt_segments)
    }

    message(sprintf("RT range: %.1f - %.1f min", min(rt_segs$rt_start), max(rt_segs$rt_end)))

    # Generate RT-dependent windows
    message(sprintf("\nGenerating %s windows for each RT segment...", window_type))
    dynamic_result <- generate_rt_dependent_windows(
      data = data,
      rt_segments = rt_segs,
      window_type = window_type,
      target_windows_per_segment = ceiling(n_windows / rt_segments),
      overlap_percentage = overlap_percentage
    )

    # Calculate coverage
    message("\nCalculating window coverage...")
    coverage <- calculate_window_coverage(data, dynamic_result$windows)

    # Export method
    message("\nExporting RT-dependent window method...")
    export_windows_to_method(
      dynamic_result$windows,
      output_file,
      method_name = sprintf("DIA_dynamic_%s_%s", rt_mode, window_type)
    )

    result <- list(
      windows = dynamic_result$windows,
      segment_summary = dynamic_result$segment_summary,
      transition_points = dynamic_result$transition_points,
      coverage = coverage,
      method_file = output_file,
      mode = mode,
      window_type = window_type,
      rt_mode = rt_mode
    )
  }

  # Print summary
  message("\n=== Generation Summary ===")
  message(sprintf("Total windows: %d", nrow(result$windows)))
  message(sprintf("Coverage: %.1f%%", result$coverage$coverage_stats$coverage_percentage))
  message(sprintf("Mean width: %.2f Da", result$coverage$coverage_stats$mean_window_width))
  if (mode == "dynamic") {
    message(sprintf("RT segments: %d", rt_segments))
    message(sprintf("Windows per segment: %.1f", nrow(result$windows) / rt_segments))
  }
  message(sprintf("\n✓ Method file: %s", output_file))

  return(invisible(result))
}
