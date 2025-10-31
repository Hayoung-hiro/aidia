# fwhm_analyzer.R - Advanced FWHM analysis for DIA window optimization

library(dplyr)
library(ggplot2)
library(stats)

#' Comprehensive FWHM analysis with multi-dimensional insights and metadata integration
#'
#' @param data DIA-NN data frame (possibly with metadata)
#' @param rt_segments Number of RT segments for analysis
#' @param mz_bins Number of m/z bins for analysis
#' @return List with comprehensive FWHM analysis results
analyze_fwhm_comprehensive <- function(data, rt_segments = 10, mz_bins = 20) {

  cat("\n=== Comprehensive FWHM Analysis ===\n")

  # Check for metadata integration
  has_metadata <- "Metadata.Available" %in% names(data)
  if (has_metadata) {
    metadata_coverage <- sum(data$Metadata.Available, na.rm = TRUE) / nrow(data) * 100
    cat(sprintf("Raw metadata available for %.1f%% of data\n", metadata_coverage))
  }

  # Filter valid FWHM data
  valid_data <- data %>%
    filter(!is.na(FWHM), FWHM > 0, FWHM < 10) %>%  # Remove unrealistic FWHM values
    mutate(FWHM_seconds = FWHM * 60)  # Convert to seconds

  # Add confidence-weighted FWHM if metadata is available
  if (has_metadata && "FWHM.Confidence" %in% names(valid_data)) {
    valid_data <- valid_data %>%
      mutate(FWHM_weighted_seconds = FWHM_seconds * FWHM.Confidence)
    cat(sprintf("Analyzing %d precursors with metadata-enhanced FWHM data\n", nrow(valid_data)))
  } else {
    cat(sprintf("Analyzing %d precursors with valid FWHM data\n", nrow(valid_data)))
  }
  
  # Basic statistics
  basic_stats <- calculate_basic_fwhm_stats(valid_data)
  
  # RT-dependent analysis
  rt_analysis <- analyze_fwhm_by_rt(valid_data, rt_segments)
  
  # m/z-dependent analysis
  mz_analysis <- analyze_fwhm_by_mz(valid_data, mz_bins)
  
  # Intensity-dependent analysis
  intensity_analysis <- analyze_fwhm_by_intensity(valid_data)
  
  # Charge state analysis
  charge_analysis <- analyze_fwhm_by_charge(valid_data)
  
  # Distribution modeling
  distribution_analysis <- model_fwhm_distribution(valid_data)
  
  # Robust statistics with outlier detection
  robust_stats <- calculate_robust_fwhm_stats(valid_data)
  
  # Strategic recommendations
  strategies <- recommend_fwhm_strategies(basic_stats, rt_analysis, mz_analysis)
  
  cat("FWHM analysis complete!\n")
  
  return(list(
    data = valid_data,
    basic_stats = basic_stats,
    rt_analysis = rt_analysis,
    mz_analysis = mz_analysis,
    intensity_analysis = intensity_analysis,
    charge_analysis = charge_analysis,
    distribution_analysis = distribution_analysis,
    robust_stats = robust_stats,
    strategies = strategies
  ))
}

#' Calculate basic FWHM statistics with optional metadata weighting
#'
#' @param data Filtered DIA-NN data
#' @return List with basic statistics
calculate_basic_fwhm_stats <- function(data) {

  # Check if metadata weighting is available
  has_weighted <- "FWHM_weighted_seconds" %in% names(data)
  has_confidence <- "FWHM.Confidence" %in% names(data)

  stats <- list(
    n_precursors = nrow(data),
    mean = mean(data$FWHM_seconds),
    median = median(data$FWHM_seconds),
    sd = sd(data$FWHM_seconds),
    min = min(data$FWHM_seconds),
    max = max(data$FWHM_seconds),
    q25 = quantile(data$FWHM_seconds, 0.25),
    q75 = quantile(data$FWHM_seconds, 0.75),
    q95 = quantile(data$FWHM_seconds, 0.95),
    q05 = quantile(data$FWHM_seconds, 0.05),
    iqr = IQR(data$FWHM_seconds),
    cv = sd(data$FWHM_seconds) / mean(data$FWHM_seconds) * 100
  )

  # Add metadata-weighted statistics
  if (has_weighted && has_confidence) {
    total_confidence <- sum(data$FWHM.Confidence, na.rm = TRUE)
    stats$weighted_mean = sum(data$FWHM_weighted_seconds, na.rm = TRUE) / total_confidence
    stats$confidence_range = c(min(data$FWHM.Confidence, na.rm = TRUE),
                              max(data$FWHM.Confidence, na.rm = TRUE))
    stats$avg_confidence = mean(data$FWHM.Confidence, na.rm = TRUE)

    # Calculate metadata coverage
    if ("Metadata.Available" %in% names(data)) {
      stats$metadata_coverage = sum(data$Metadata.Available, na.rm = TRUE) / nrow(data) * 100
    }
  }

  cat(sprintf("Basic FWHM Statistics:\n"))
  cat(sprintf("  Median: %.2f sec (%.3f min)\n", stats$median, stats$median/60))
  cat(sprintf("  Mean ± SD: %.2f ± %.2f sec\n", stats$mean, stats$sd))

  if (has_weighted) {
    cat(sprintf("  Weighted mean: %.2f sec\n", stats$weighted_mean))
    cat(sprintf("  Confidence range: %.2f - %.2f\n",
                stats$confidence_range[1], stats$confidence_range[2]))
  }

  cat(sprintf("  Range: %.2f - %.2f sec\n", stats$min, stats$max))
  cat(sprintf("  IQR: %.2f - %.2f sec\n", stats$q25, stats$q75))
  cat(sprintf("  CV: %.1f%%\n", stats$cv))

  if (has_confidence && "metadata_coverage" %in% names(stats)) {
    cat(sprintf("  Metadata coverage: %.1f%%\n", stats$metadata_coverage))
  }

  return(stats)
}

#' Analyze FWHM distribution across RT segments
#' 
#' @param data Filtered DIA-NN data
#' @param rt_segments Number of RT segments
#' @return List with RT-dependent analysis
analyze_fwhm_by_rt <- function(data, rt_segments) {
  
  # Define RT breaks
  rt_range <- range(data$RT.Start)
  rt_breaks <- seq(rt_range[1], rt_range[2], length.out = rt_segments + 1)
  
  # Assign RT segments
  data$rt_segment <- cut(data$RT.Start, breaks = rt_breaks, 
                        labels = 1:rt_segments, include.lowest = TRUE)
  
  # Calculate statistics per segment
  rt_stats <- data %>%
    group_by(rt_segment) %>%
    summarise(
      rt_start = min(RT.Start),
      rt_end = max(RT.Start),
      n_precursors = n(),
      median_fwhm = median(FWHM_seconds),
      mean_fwhm = mean(FWHM_seconds),
      sd_fwhm = sd(FWHM_seconds),
      q25_fwhm = quantile(FWHM_seconds, 0.25),
      q75_fwhm = quantile(FWHM_seconds, 0.75),
      cv_fwhm = sd(FWHM_seconds) / mean(FWHM_seconds) * 100,
      .groups = 'drop'
    ) %>%
    mutate(
      rt_mid = (rt_start + rt_end) / 2,
      segment_id = as.numeric(rt_segment)
    )
  
  # Calculate RT trend
  rt_trend <- calculate_rt_trend(rt_stats)
  
  cat(sprintf("RT Analysis (%d segments):\n", rt_segments))
  cat(sprintf("  FWHM range: %.2f - %.2f sec across RT\n", 
              min(rt_stats$median_fwhm), max(rt_stats$median_fwhm)))
  cat(sprintf("  RT trend: %s (%.4f sec/min)\n", rt_trend$direction, rt_trend$slope * 60))
  
  return(list(
    stats = rt_stats,
    trend = rt_trend,
    segments = rt_segments
  ))
}

#' Analyze FWHM distribution across m/z ranges
#' 
#' @param data Filtered DIA-NN data
#' @param mz_bins Number of m/z bins
#' @return List with m/z-dependent analysis
analyze_fwhm_by_mz <- function(data, mz_bins) {
  
  # Define m/z breaks
  mz_range <- range(data$Precursor.Mz)
  mz_breaks <- seq(mz_range[1], mz_range[2], length.out = mz_bins + 1)
  
  # Assign m/z bins
  data$mz_bin <- cut(data$Precursor.Mz, breaks = mz_breaks, 
                    labels = 1:mz_bins, include.lowest = TRUE)
  
  # Calculate statistics per bin
  mz_stats <- data %>%
    group_by(mz_bin) %>%
    summarise(
      mz_start = min(Precursor.Mz),
      mz_end = max(Precursor.Mz),
      n_precursors = n(),
      median_fwhm = median(FWHM_seconds),
      mean_fwhm = mean(FWHM_seconds),
      sd_fwhm = sd(FWHM_seconds),
      q25_fwhm = quantile(FWHM_seconds, 0.25),
      q75_fwhm = quantile(FWHM_seconds, 0.75),
      .groups = 'drop'
    ) %>%
    mutate(
      mz_mid = (mz_start + mz_end) / 2,
      bin_id = as.numeric(mz_bin)
    ) %>%
    filter(n_precursors >= 10)  # Minimum precursors for reliable statistics
  
  # Calculate m/z trend
  mz_trend <- calculate_mz_trend(mz_stats)
  
  cat(sprintf("m/z Analysis (%d bins):\n", nrow(mz_stats)))
  cat(sprintf("  FWHM range: %.2f - %.2f sec across m/z\n", 
              min(mz_stats$median_fwhm), max(mz_stats$median_fwhm)))
  cat(sprintf("  m/z trend: %s (%.5f sec/Da)\n", mz_trend$direction, mz_trend$slope))
  
  return(list(
    stats = mz_stats,
    trend = mz_trend,
    bins = mz_bins
  ))
}

#' Analyze FWHM by intensity quartiles
#' 
#' @param data Filtered DIA-NN data
#' @return List with intensity-dependent analysis
analyze_fwhm_by_intensity <- function(data) {
  
  # Skip if no intensity data
  if (!"Precursor.Quantity" %in% names(data)) {
    cat("No intensity data available for analysis\n")
    return(NULL)
  }
  
  # Define intensity quartiles
  intensity_quartiles <- quantile(data$Precursor.Quantity, 
                                 probs = c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE)
  
  data$intensity_quartile <- cut(data$Precursor.Quantity, 
                                breaks = intensity_quartiles,
                                labels = c("Q1", "Q2", "Q3", "Q4"),
                                include.lowest = TRUE)
  
  # Calculate statistics per quartile
  intensity_stats <- data %>%
    group_by(intensity_quartile) %>%
    summarise(
      n_precursors = n(),
      median_fwhm = median(FWHM_seconds),
      mean_fwhm = mean(FWHM_seconds),
      sd_fwhm = sd(FWHM_seconds),
      median_intensity = median(Precursor.Quantity, na.rm = TRUE),
      .groups = 'drop'
    )
  
  cat("Intensity Analysis:\n")
  for (i in 1:nrow(intensity_stats)) {
    cat(sprintf("  %s: FWHM = %.2f sec (n=%d)\n", 
                intensity_stats$intensity_quartile[i],
                intensity_stats$median_fwhm[i],
                intensity_stats$n_precursors[i]))
  }
  
  return(intensity_stats)
}

#' Analyze FWHM by charge state
#' 
#' @param data Filtered DIA-NN data
#' @return List with charge-dependent analysis
analyze_fwhm_by_charge <- function(data) {
  
  # Skip if no charge data
  if (!"Precursor.Charge" %in% names(data)) {
    cat("No charge state data available for analysis\n")
    return(NULL)
  }
  
  # Calculate statistics per charge state
  charge_stats <- data %>%
    group_by(Precursor.Charge) %>%
    summarise(
      n_precursors = n(),
      median_fwhm = median(FWHM_seconds),
      mean_fwhm = mean(FWHM_seconds),
      sd_fwhm = sd(FWHM_seconds),
      .groups = 'drop'
    ) %>%
    filter(n_precursors >= 10)  # Minimum for reliable statistics
  
  cat("Charge State Analysis:\n")
  for (i in 1:nrow(charge_stats)) {
    cat(sprintf("  Charge %d: FWHM = %.2f sec (n=%d)\n", 
                charge_stats$Precursor.Charge[i],
                charge_stats$median_fwhm[i],
                charge_stats$n_precursors[i]))
  }
  
  return(charge_stats)
}

#' Model FWHM distribution and test goodness of fit
#' 
#' @param data Filtered DIA-NN data
#' @return List with distribution analysis
model_fwhm_distribution <- function(data) {
  
  fwhm_values <- data$FWHM_seconds
  
  # Simple distribution analysis without fitdistr
  distributions <- list(
    normal = list(name = "Normal"),
    lognormal = list(name = "Log-Normal"),
    gamma = list(name = "Gamma")
  )
  
  # Calculate basic distribution properties
  mean_val <- mean(fwhm_values)
  var_val <- var(fwhm_values)
  
  # Simple assessment based on mean/variance ratio
  cv <- sqrt(var_val) / mean_val
  
  if (cv < 0.3) {
    best_dist <- "normal"
  } else if (cv > 0.8) {
    best_dist <- "gamma"
  } else {
    best_dist <- "lognormal"
  }
  
  distributions[[best_dist]]$selected <- TRUE
  
  cat(sprintf("Distribution Analysis:\n"))
  cat(sprintf("  CV: %.2f, Best fit: %s\n", cv, distributions[[best_dist]]$name))
  
  return(list(
    distributions = distributions,
    best_distribution = best_dist,
    cv = cv
  ))
}

#' Calculate robust statistics with outlier detection
#' 
#' @param data Filtered DIA-NN data
#' @return List with robust statistics
calculate_robust_fwhm_stats <- function(data) {
  
  fwhm_values <- data$FWHM_seconds
  
  # Median Absolute Deviation
  mad_value <- mad(fwhm_values)
  
  # Outlier detection using MAD
  median_fwhm <- median(fwhm_values)
  outlier_threshold <- 3 * mad_value
  outliers <- abs(fwhm_values - median_fwhm) > outlier_threshold
  
  # Robust statistics (excluding outliers)
  clean_fwhm <- fwhm_values[!outliers]
  
  robust_stats <- list(
    median = median(clean_fwhm),
    mad = mad_value,
    trimmed_mean_10 = mean(clean_fwhm, trim = 0.1),
    trimmed_mean_20 = mean(clean_fwhm, trim = 0.2),
    n_outliers = sum(outliers),
    outlier_percentage = sum(outliers) / length(fwhm_values) * 100,
    clean_n = length(clean_fwhm),
    q25_robust = quantile(clean_fwhm, 0.25),
    q75_robust = quantile(clean_fwhm, 0.75),
    q95_robust = quantile(clean_fwhm, 0.95)
  )
  
  cat(sprintf("Robust Statistics:\n"))
  cat(sprintf("  Outliers detected: %d (%.1f%%)\n", 
              robust_stats$n_outliers, robust_stats$outlier_percentage))
  cat(sprintf("  Robust median: %.2f sec\n", robust_stats$median))
  cat(sprintf("  MAD: %.2f sec\n", robust_stats$mad))
  
  return(robust_stats)
}

#' Recommend FWHM strategies based on analysis
#' 
#' @param basic_stats Basic FWHM statistics
#' @param rt_analysis RT-dependent analysis
#' @param mz_analysis m/z-dependent analysis
#' @return List with strategy recommendations
recommend_fwhm_strategies <- function(basic_stats, rt_analysis, mz_analysis) {
  
  strategies <- list(
    conservative = list(
      name = "Conservative",
      fwhm_percentile = 0.95,
      description = "Use 95th percentile FWHM for maximum reliability"
    ),
    balanced = list(
      name = "Balanced", 
      fwhm_percentile = 0.75,
      description = "Use 75th percentile FWHM for balanced performance"
    ),
    aggressive = list(
      name = "Aggressive",
      fwhm_percentile = 0.50,
      description = "Use median FWHM for maximum efficiency"
    )
  )
  
  # Calculate FWHM values for each strategy
  for (strategy in names(strategies)) {
    percentile <- strategies[[strategy]]$fwhm_percentile
    strategies[[strategy]]$fwhm_value <- basic_stats[[paste0("q", percentile * 100)]]
  }
  
  # Add adaptive strategy if RT variation is significant
  rt_variation <- (max(rt_analysis$stats$median_fwhm) - min(rt_analysis$stats$median_fwhm)) / 
                  basic_stats$median
  
  if (rt_variation > 0.2) {  # >20% variation across RT
    strategies$adaptive <- list(
      name = "RT-Adaptive",
      fwhm_percentile = "variable",
      description = "Use RT-segment specific FWHM values",
      rt_variation = rt_variation
    )
  }
  
  # Recommend best strategy
  if (basic_stats$cv > 30) {
    recommended <- "conservative"
  } else if (basic_stats$cv < 15) {
    recommended <- "aggressive"
  } else {
    recommended <- "balanced"
  }
  
  cat(sprintf("Strategy Recommendations:\n"))
  cat(sprintf("  Recommended: %s (CV = %.1f%%)\n", 
              strategies[[recommended]]$name, basic_stats$cv))
  
  if (exists("adaptive", strategies)) {
    cat(sprintf("  RT variation detected: %.1f%% - consider adaptive strategy\n", 
                rt_variation * 100))
  }
  
  strategies$recommended <- recommended
  
  return(strategies)
}

#' Calculate RT trend in FWHM
#' 
#' @param rt_stats RT statistics data frame
#' @return List with trend analysis
calculate_rt_trend <- function(rt_stats) {
  
  if (nrow(rt_stats) < 3) {
    return(list(direction = "insufficient_data", slope = 0))
  }
  
  # Linear regression
  lm_fit <- lm(median_fwhm ~ rt_mid, data = rt_stats)
  slope <- coef(lm_fit)[2]
  
  direction <- if (abs(slope) < 0.001) {
    "stable"
  } else if (slope > 0) {
    "increasing" 
  } else {
    "decreasing"
  }
  
  return(list(
    direction = direction,
    slope = slope,
    r_squared = summary(lm_fit)$r.squared
  ))
}

#' Calculate m/z trend in FWHM
#' 
#' @param mz_stats m/z statistics data frame  
#' @return List with trend analysis
calculate_mz_trend <- function(mz_stats) {
  
  if (nrow(mz_stats) < 3) {
    return(list(direction = "insufficient_data", slope = 0))
  }
  
  # Linear regression
  lm_fit <- lm(median_fwhm ~ mz_mid, data = mz_stats)
  slope <- coef(lm_fit)[2]
  
  direction <- if (abs(slope) < 0.00001) {
    "stable"
  } else if (slope > 0) {
    "increasing"
  } else {
    "decreasing"
  }
  
  return(list(
    direction = direction,
    slope = slope,
    r_squared = summary(lm_fit)$r.squared
  ))
}

#' Get FWHM value based on strategy
#' 
#' @param fwhm_analysis Result from analyze_fwhm_comprehensive
#' @param strategy Strategy name ("conservative", "balanced", "aggressive", "adaptive")
#' @param rt_segment RT segment number (for adaptive strategy)
#' @return FWHM value in seconds
get_strategy_fwhm <- function(fwhm_analysis, strategy = "balanced", rt_segment = NULL) {
  
  if (strategy == "adaptive" && !is.null(rt_segment)) {
    # Return RT-segment specific FWHM
    rt_stats <- fwhm_analysis$rt_analysis$stats
    if (rt_segment <= nrow(rt_stats)) {
      return(rt_stats$median_fwhm[rt_segment])
    }
  }
  
  # Return strategy-based FWHM
  if (strategy %in% names(fwhm_analysis$strategies)) {
    return(fwhm_analysis$strategies[[strategy]]$fwhm_value)
  }
  
  # Default to balanced
  return(fwhm_analysis$strategies$balanced$fwhm_value)
}

#' Create FWHM analysis visualization plots
#' 
#' @param fwhm_analysis Result from analyze_fwhm_comprehensive
#' @param save_plots Whether to save plots to files
#' @param plot_dir Directory to save plots
#' @return List of ggplot objects
visualize_fwhm_analysis <- function(fwhm_analysis, save_plots = FALSE, plot_dir = "plots") {
  
  library(ggplot2)
  library(gridExtra)
  library(viridis)
  
  plots <- list()
  
  # 1. Overall FWHM distribution
  plots$distribution <- ggplot(fwhm_analysis$data, aes(x = FWHM_seconds)) +
    geom_histogram(bins = 50, fill = "steelblue", alpha = 0.7, color = "white") +
    geom_vline(xintercept = fwhm_analysis$basic_stats$median, 
               color = "red", linetype = "dashed", size = 1) +
    geom_vline(xintercept = fwhm_analysis$basic_stats$q25, 
               color = "orange", linetype = "dotted") +
    geom_vline(xintercept = fwhm_analysis$basic_stats$q75, 
               color = "orange", linetype = "dotted") +
    labs(
      title = "FWHM Distribution",
      subtitle = sprintf("Median: %.2f sec, IQR: %.2f - %.2f sec", 
                        fwhm_analysis$basic_stats$median,
                        fwhm_analysis$basic_stats$q25,
                        fwhm_analysis$basic_stats$q75),
      x = "FWHM (seconds)",
      y = "Count"
    ) +
    theme_minimal()
  
  # 2. RT-dependent FWHM
  if (!is.null(fwhm_analysis$rt_analysis)) {
    plots$rt_trend <- ggplot(fwhm_analysis$rt_analysis$stats, 
                            aes(x = rt_mid, y = median_fwhm)) +
      geom_line(color = "steelblue", size = 1) +
      geom_point(color = "steelblue", size = 2) +
      geom_ribbon(aes(ymin = q25_fwhm, ymax = q75_fwhm), 
                  alpha = 0.3, fill = "steelblue") +
      labs(
        title = "FWHM Variation Across Retention Time",
        subtitle = sprintf("Trend: %s (R² = %.3f)", 
                          fwhm_analysis$rt_analysis$trend$direction,
                          fwhm_analysis$rt_analysis$trend$r_squared),
        x = "Retention Time (minutes)",
        y = "Median FWHM (seconds)"
      ) +
      theme_minimal()
  }
  
  # 3. m/z-dependent FWHM
  if (!is.null(fwhm_analysis$mz_analysis)) {
    plots$mz_trend <- ggplot(fwhm_analysis$mz_analysis$stats, 
                            aes(x = mz_mid, y = median_fwhm)) +
      geom_line(color = "forestgreen", size = 1) +
      geom_point(color = "forestgreen", size = 2) +
      geom_ribbon(aes(ymin = q25_fwhm, ymax = q75_fwhm), 
                  alpha = 0.3, fill = "forestgreen") +
      labs(
        title = "FWHM Variation Across m/z Range",
        subtitle = sprintf("Trend: %s (R² = %.3f)", 
                          fwhm_analysis$mz_analysis$trend$direction,
                          fwhm_analysis$mz_analysis$trend$r_squared),
        x = "Precursor m/z",
        y = "Median FWHM (seconds)"
      ) +
      theme_minimal()
  }
  
  # 4. Strategy comparison
  strategy_data <- data.frame(
    Strategy = names(fwhm_analysis$strategies)[1:3],
    FWHM_Value = c(
      fwhm_analysis$strategies$conservative$fwhm_value,
      fwhm_analysis$strategies$balanced$fwhm_value,
      fwhm_analysis$strategies$aggressive$fwhm_value
    ),
    Percentile = c("95th", "75th", "50th"),
    Recommended = c(
      fwhm_analysis$strategies$recommended == "conservative",
      fwhm_analysis$strategies$recommended == "balanced",
      fwhm_analysis$strategies$recommended == "aggressive"
    )
  )
  
  plots$strategies <- ggplot(strategy_data, aes(x = Strategy, y = FWHM_Value, 
                                               fill = Recommended)) +
    geom_col(alpha = 0.7) +
    geom_text(aes(label = sprintf("%.2f s\n(%s)", FWHM_Value, Percentile)), 
              vjust = -0.5) +
    scale_fill_manual(values = c("FALSE" = "lightgray", "TRUE" = "gold")) +
    labs(
      title = "FWHM Strategy Comparison",
      subtitle = sprintf("Recommended: %s", 
                        fwhm_analysis$strategies[[fwhm_analysis$strategies$recommended]]$name),
      x = "Strategy",
      y = "FWHM Value (seconds)",
      fill = "Recommended"
    ) +
    theme_minimal() +
    theme(legend.position = "none")
  
  # 5. Intensity vs FWHM (if available)
  if (!is.null(fwhm_analysis$intensity_analysis)) {
    plots$intensity <- ggplot(fwhm_analysis$intensity_analysis, 
                             aes(x = intensity_quartile, y = median_fwhm)) +
      geom_col(fill = "coral", alpha = 0.7) +
      geom_text(aes(label = sprintf("%.2f s", median_fwhm)), vjust = -0.5) +
      labs(
        title = "FWHM by Intensity Quartiles",
        x = "Intensity Quartile",
        y = "Median FWHM (seconds)"
      ) +
      theme_minimal()
  }
  
  # 6. Charge state vs FWHM (if available)
  if (!is.null(fwhm_analysis$charge_analysis)) {
    plots$charge <- ggplot(fwhm_analysis$charge_analysis, 
                          aes(x = factor(Precursor.Charge), y = median_fwhm)) +
      geom_col(fill = "mediumpurple", alpha = 0.7) +
      geom_text(aes(label = sprintf("%.2f s", median_fwhm)), vjust = -0.5) +
      labs(
        title = "FWHM by Charge State",
        x = "Precursor Charge",
        y = "Median FWHM (seconds)"
      ) +
      theme_minimal()
  }
  
  # Save plots if requested
  if (save_plots) {
    if (!dir.exists(plot_dir)) {
      dir.create(plot_dir, recursive = TRUE)
    }
    
    for (plot_name in names(plots)) {
      filename <- file.path(plot_dir, paste0("fwhm_", plot_name, ".png"))
      ggsave(filename, plots[[plot_name]], width = 10, height = 6, dpi = 300)
      cat(sprintf("Saved plot: %s\n", filename))
    }
  }
  
  return(plots)
}

#' Print FWHM analysis summary
#' 
#' @param fwhm_analysis Result from analyze_fwhm_comprehensive
print_fwhm_summary <- function(fwhm_analysis) {
  
  cat("\n╔════════════════════════════════════════════╗\n")
  cat("║           FWHM ANALYSIS SUMMARY           ║\n")
  cat("╚════════════════════════════════════════════╝\n\n")
  
  # Basic statistics
  stats <- fwhm_analysis$basic_stats
  cat("📊 Basic Statistics:\n")
  cat(sprintf("  • Precursors analyzed: %d\n", stats$n_precursors))
  cat(sprintf("  • Median FWHM: %.2f seconds (%.3f minutes)\n", stats$median, stats$median/60))
  cat(sprintf("  • Coefficient of Variation: %.1f%%\n", stats$cv))
  cat(sprintf("  • Range: %.2f - %.2f seconds\n", stats$min, stats$max))
  
  # Distribution analysis
  if (!is.null(fwhm_analysis$distribution_analysis)) {
    best_dist <- fwhm_analysis$distribution_analysis$best_distribution
    cat(sprintf("  • Best distribution fit: %s\n", 
                fwhm_analysis$distribution_analysis$distributions[[best_dist]]$name))
  }
  
  # RT trend
  if (!is.null(fwhm_analysis$rt_analysis)) {
    rt_trend <- fwhm_analysis$rt_analysis$trend
    # TODO(human): Add safety check for r_squared field
    if (!is.null(rt_trend$r_squared) && length(rt_trend$r_squared) > 0) {
      cat(sprintf("\n🕒 RT Trend: %s (R² = %.3f)\n", rt_trend$direction, rt_trend$r_squared))
      if (rt_trend$r_squared > 0.5) {
        cat("  → Significant RT-dependent variation detected\n")
        cat("  → Consider using adaptive FWHM strategy\n")
      }
    } else {
      cat(sprintf("\n🕒 RT Trend: %s (R² not available)\n", rt_trend$direction))
    }
  }
  
  # m/z trend
  if (!is.null(fwhm_analysis$mz_analysis)) {
    mz_trend <- fwhm_analysis$mz_analysis$trend
    cat(sprintf("⚖️  m/z Trend: %s (R² = %.3f)\n", mz_trend$direction, mz_trend$r_squared))
  }
  
  # Strategy recommendations
  cat("\n🎯 Strategy Recommendations:\n")
  recommended <- fwhm_analysis$strategies$recommended
  for (strategy_name in c("conservative", "balanced", "aggressive")) {
    strategy <- fwhm_analysis$strategies[[strategy_name]]
    marker <- if (strategy_name == recommended) "✅" else "  "
    cat(sprintf("%s %s: %.2f sec (%s)\n", 
                marker, strategy$name, strategy$fwhm_value, strategy$description))
  }
  
  # Adaptive strategy
  if ("adaptive" %in% names(fwhm_analysis$strategies)) {
    cat(sprintf("🔄 RT-Adaptive: Available (%.1f%% RT variation)\n", 
                fwhm_analysis$strategies$adaptive$rt_variation * 100))
  }
  
  # Robust statistics
  if (!is.null(fwhm_analysis$robust_stats)) {
    robust <- fwhm_analysis$robust_stats
    if (robust$outlier_percentage > 5) {
      cat(sprintf("\n⚠️  Outliers detected: %.1f%% (consider robust statistics)\n", 
                  robust$outlier_percentage))
    }
  }
  
  cat("\n═══════════════════════════════════════════\n")
}