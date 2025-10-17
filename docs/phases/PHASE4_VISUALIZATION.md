# Phase 4: Visualization & Reporting - Development Guide

**Version**: 1.0
**Last Updated**: 2025-10-13
**Status**: 🔴 개발 대기
**Priority**: ⭐⭐ 우선순위 6
**Estimated Duration**: 5-6일

---

## 📋 목차

1. [개요](#개요)
2. [Phase 4 목표](#phase-4-목표)
3. [입출력 스펙](#입출력-스펙)
4. [필수 Visualization](#필수-visualization)
5. [구현 가이드](#구현-가이드)
6. [테스트 전략](#테스트-전략)
7. [Definition of Done](#definition-of-done)

---

## 개요

### Phase 4의 역할

**Visualization & Reporting**은 모든 최적화 결과를 시각화하고 포괄적인 리포트와 method 파일을 생성하는 최종 단계입니다.

**핵심 철학**:
- **포괄적 시각화**: 8가지 필수 plot으로 최적화 품질 평가
- **실행 가능 출력**: Instrument method 파일 (CSV 형식)
- **PDF 리포트**: 모든 plot과 요약 통계를 하나의 문서로

### 입력 데이터

Phase 1-3의 모든 출력:
```r
# Phase 1: Data Validation
validated_data <- create_mock_stage1_output()

# Phase 2: DPPP Diagnosis
diagnosis <- create_mock_stage2_output()

# Phase 3A: Window Count
window_count <- create_mock_stage3a_output()

# Phase 3B: RT Binning
rt_binning <- create_mock_stage3b_output()

# Phase 3C: m/z Range
mz_range <- create_mock_stage3c_output()

# Phase 3D: Window Generation
windows <- create_mock_stage3d_output()
```

### 출력 데이터

```r
VisualizationResult <- structure(
  list(
    plots = list(
      dppp_density = ggplot_object,
      rt_window_size = ggplot_object,
      rt_mz_heatmap = ggplot_object,
      mz_normalized_density = ggplot_object,
      mz_window_width = ggplot_object,
      precursor_coverage_map = ggplot_object,
      window_efficiency = ggplot_object,
      dppp_achievement_heatmap = ggplot_object
    ),

    report_files = list(
      pdf_report = character(),          # Path to comprehensive PDF
      method_file = character(),         # Path to instrument method CSV
      individual_plots = character()     # Vector of individual plot paths
    ),

    summary_statistics = list(
      optimization_metrics = list(...),
      performance_metrics = list(...),
      quality_metrics = list(...)
    ),

    metadata = list(
      generation_timestamp = POSIXct(),
      plot_generation_time = numeric(),
      report_generation_time = numeric()
    )
  ),
  class = c("VisualizationResult", "list")
)
```

---

## Phase 4 목표

### 주요 기능

1. **8가지 필수 Plot 생성**
   - Plot 1: DPPP Density (2D heatmap, RT × m/z)
   - Plot 2: RT Window Size (RT segment별 window 개수)
   - Plot 3: RT × m/z Density Heatmap (precursor 분포)
   - Plot 4: m/z Normalized Density (RT segment별)
   - Plot 5: m/z Window Width (RT-dependent width profile)
   - Plot 6: Precursor Coverage Map (window coverage)
   - Plot 7: Window Efficiency (precursors per window)
   - Plot 8: DPPP Achievement Heatmap (target 달성도)

2. **PDF Report 생성**
   - Multi-panel comprehensive report
   - 모든 plot 포함
   - Summary statistics
   - Optimization parameters

3. **Method File Export**
   - CSV format (Thermo Orbitrap compatible)
   - RT-dependent isolation windows
   - Center m/z, window width, RT ranges

4. **Individual Plot Export**
   - PNG/PDF format
   - High-resolution (300 DPI)
   - Publication-ready quality

### 성공 지표

- [x] 8가지 필수 plot 모두 생성
- [x] PDF report 생성 (multi-panel)
- [x] Method file export (CSV)
- [x] Individual plots export (PNG/PDF)
- [x] Plot generation < 30초
- [x] Report generation < 1분

---

## 입출력 스펙

### Input Specification

```r
# All previous phase outputs
all_results <- list(
  validated_data = validated_data,
  diagnosis = diagnosis,
  window_count = window_count,
  rt_binning = rt_binning,
  mz_range = mz_range,
  windows = windows
)

# User parameters
output_dir <- "output/"
create_pdf <- TRUE
create_individual_plots <- TRUE
plot_format <- "png"                 # "png" or "pdf"
plot_dpi <- 300
```

### Output Specification

```r
# VisualizationResult 구조
viz_result <- generate_visualizations(
  all_results = all_results,
  output_dir = "output/",
  create_pdf = TRUE
)

# 접근 예시
viz_result$plots$dppp_density                    # ggplot object
viz_result$report_files$pdf_report               # "output/report.pdf"
viz_result$report_files$method_file              # "output/method.csv"
viz_result$summary_statistics$optimization_metrics
```

---

## 필수 Visualization

### Plot 1: DPPP Density (2D Heatmap)

**목적**: RT × m/z 공간에서 DPPP 분포 시각화

**데이터**: Phase 2 diagnosis result

**알고리즘**:
```r
plot_dppp_density <- function(diagnosis) {
  # Extract DPPP distribution
  dppp_data <- diagnosis$current_state$dppp_distribution

  # Create 2D heatmap
  p <- ggplot(dppp_data, aes(x = rt, y = mz, fill = dppp_value)) +
    geom_tile() +
    scale_fill_viridis_c(
      option = "magma",
      name = "DPPP",
      limits = c(0, max(dppp_data$dppp_value))
    ) +
    geom_hline(yintercept = c(diagnosis$metadata$target_dppp -
                               diagnosis$metadata$dppp_tolerance,
                               diagnosis$metadata$target_dppp +
                               diagnosis$metadata$dppp_tolerance),
               linetype = "dashed", color = "white", linewidth = 0.8) +
    labs(
      title = "DPPP Distribution Across RT × m/z Space",
      subtitle = sprintf("Target DPPP: %.1f ± %.1f | Satisfaction: %.1f%%",
                        diagnosis$metadata$target_dppp,
                        diagnosis$metadata$dppp_tolerance,
                        diagnosis$current_state$satisfaction_ratio * 100),
      x = "Retention Time (min)",
      y = "Precursor m/z (Da)",
      caption = "White dashed lines = target DPPP ± tolerance"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      legend.position = "right"
    )

  return(p)
}
```

**해석**:
- 빨간색 (high DPPP): Under-sampling
- 파란색 (low DPPP): Over-sampling
- 흰색 선 사이: Target DPPP 범위

---

### Plot 2: RT Window Size

**목적**: RT segment별 할당된 window 개수 시각화

**데이터**: Phase 3D windows result

**알고리즘**:
```r
plot_rt_window_size <- function(windows) {
  # Count windows per RT segment
  rt_summary <- windows$windows %>%
    group_by(rt_segment_id, rt_start, rt_end) %>%
    summarise(
      n_windows = n(),
      mean_width = mean(window_width),
      .groups = "drop"
    ) %>%
    mutate(rt_midpoint = (rt_start + rt_end) / 2)

  # Plot window count
  p <- ggplot(rt_summary, aes(x = rt_midpoint, y = n_windows)) +
    geom_col(fill = "steelblue", alpha = 0.7) +
    geom_text(aes(label = n_windows), vjust = -0.5, size = 3) +
    labs(
      title = "Window Allocation Across RT Segments",
      subtitle = sprintf("Total windows: %d | Mean: %.1f per segment",
                        windows$statistics$total_windows,
                        mean(rt_summary$n_windows)),
      x = "Retention Time (min)",
      y = "Number of Windows",
      caption = "More windows in high-density regions"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      panel.grid.major.x = element_blank()
    )

  return(p)
}
```

**해석**:
- 높은 막대: High precursor density region
- 낮은 막대: Low precursor density region

---

### Plot 3: RT × m/z Density Heatmap

**목적**: Precursor 분포를 2D heatmap으로 시각화

**데이터**: Phase 1 validated_data

**알고리즘**:
```r
plot_rt_mz_density_heatmap <- function(validated_data, bins = 50) {
  # Extract precursor data
  precursor_data <- validated_data$data %>%
    select(RT.Start, Precursor.Mz)

  # Create 2D density
  p <- ggplot(precursor_data, aes(x = RT.Start, y = Precursor.Mz)) +
    stat_density_2d(
      aes(fill = after_stat(density)),
      geom = "raster",
      contour = FALSE,
      bins = bins
    ) +
    scale_fill_viridis_c(option = "plasma", name = "Density") +
    labs(
      title = "Precursor Density Distribution",
      subtitle = sprintf("%d precursors", nrow(precursor_data)),
      x = "Retention Time (min)",
      y = "Precursor m/z (Da)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      legend.position = "right"
    )

  return(p)
}
```

**해석**:
- 밝은 영역: High precursor density
- 어두운 영역: Low precursor density

---

### Plot 4: m/z Normalized Density

**목적**: RT segment별 m/z density profile 비교

**데이터**: Phase 3B rt_binning + Phase 3C mz_range

**알고리즘**:
```r
plot_mz_normalized_density <- function(rt_binning, mz_range) {
  density_profiles <- list()

  for (i in 1:nrow(rt_binning$rt_segments)) {
    segment <- rt_binning$rt_segments[i, ]
    segment_range <- mz_range$mz_ranges[i, ]

    # Get precursor data
    prec_data <- segment$precursor_data[[1]]

    # Calculate density histogram
    hist_result <- hist(
      prec_data$Precursor.Mz,
      breaks = seq(segment_range$mz_min, segment_range$mz_max, by = 10),
      plot = FALSE
    )

    # Normalize density
    normalized_density <- hist_result$density / max(hist_result$density)

    density_profiles[[i]] <- tibble(
      rt_segment = segment$rt_segment_id,
      mz_center = hist_result$mids,
      normalized_density = normalized_density
    )
  }

  density_data <- bind_rows(density_profiles)

  # Plot
  p <- ggplot(density_data, aes(x = mz_center, y = normalized_density,
                                 color = factor(rt_segment))) +
    geom_line(linewidth = 1) +
    scale_color_viridis_d(name = "RT Segment") +
    labs(
      title = "m/z Density Profiles Across RT Segments",
      subtitle = "Normalized to max density per segment",
      x = "Precursor m/z (Da)",
      y = "Normalized Density"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      legend.position = "right"
    )

  return(p)
}
```

**해석**:
- Peak 위치: High precursor concentration
- RT segment별 색상: Time-dependent m/z distribution

---

### Plot 5: m/z Window Width

**목적**: RT-dependent window width profile 시각화

**데이터**: Phase 3D windows result

**알고리즘**:
```r
plot_mz_window_width <- function(windows) {
  # Extract window data
  window_data <- windows$windows %>%
    mutate(rt_midpoint = (rt_start + rt_end) / 2)

  # Plot window width
  p <- ggplot(window_data, aes(x = mz_center, y = window_width,
                                color = rt_midpoint)) +
    geom_point(alpha = 0.6, size = 2) +
    geom_smooth(method = "loess", se = FALSE, color = "black",
                linetype = "dashed", linewidth = 1) +
    scale_color_viridis_c(name = "RT (min)") +
    labs(
      title = "Window Width Distribution Across m/z Range",
      subtitle = sprintf("Range: %.1f - %.1f Da | Mean: %.1f Da",
                        windows$statistics$min_window_width,
                        windows$statistics$max_window_width,
                        windows$statistics$mean_window_width),
      x = "Window Center m/z (Da)",
      y = "Window Width (Da)",
      caption = "Black dashed line = smoothed trend"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      legend.position = "right"
    )

  return(p)
}
```

**해석**:
- 좁은 window: High density region
- 넓은 window: Low density region
- RT color gradient: Time-dependent variation

---

### Plot 6: Precursor Coverage Map

**목적**: Window coverage 시각화 (covered vs uncovered regions)

**데이터**: Phase 3D windows + coverage_analysis

**알고리즘**:
```r
plot_precursor_coverage_map <- function(windows, validated_data) {
  # Extract precursor and window data
  precursor_data <- validated_data$data %>%
    select(RT.Start, Precursor.Mz)

  window_data <- windows$windows

  # Determine coverage for each precursor
  precursor_data <- precursor_data %>%
    rowwise() %>%
    mutate(
      is_covered = any(
        window_data$mz_start <= Precursor.Mz &
        window_data$mz_end >= Precursor.Mz &
        window_data$rt_start <= RT.Start &
        window_data$rt_end >= RT.Start
      )
    ) %>%
    ungroup()

  # Plot coverage
  p <- ggplot(precursor_data, aes(x = RT.Start, y = Precursor.Mz,
                                   color = is_covered)) +
    geom_point(alpha = 0.3, size = 0.5) +
    scale_color_manual(
      values = c("TRUE" = "green", "FALSE" = "red"),
      labels = c("TRUE" = "Covered", "FALSE" = "Not covered"),
      name = "Status"
    ) +
    labs(
      title = "Precursor Coverage Map",
      subtitle = sprintf("Coverage: %.1f%% (%d/%d precursors)",
                        windows$coverage_analysis$coverage_ratio * 100,
                        windows$coverage_analysis$covered_precursors,
                        windows$coverage_analysis$total_precursors),
      x = "Retention Time (min)",
      y = "Precursor m/z (Da)",
      caption = "Green = covered | Red = not covered"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      legend.position = "right"
    )

  return(p)
}
```

**해석**:
- 초록색 점: Covered precursors
- 빨간색 점: Uncovered precursors (gaps)

---

### Plot 7: Window Efficiency

**목적**: Window당 precursor 개수 분포

**데이터**: Phase 3D windows result

**알고리즘**:
```r
plot_window_efficiency <- function(windows) {
  # Extract window efficiency data
  window_data <- windows$windows %>%
    arrange(n_precursors)

  # Plot precursors per window
  p <- ggplot(window_data, aes(x = window_id, y = n_precursors)) +
    geom_col(fill = "coral", alpha = 0.7) +
    geom_hline(yintercept = windows$statistics$mean_precursors_per_window,
               linetype = "dashed", color = "blue", linewidth = 1) +
    annotate("text", x = max(window_data$window_id) * 0.9,
             y = windows$statistics$mean_precursors_per_window * 1.1,
             label = sprintf("Mean: %.1f",
                           windows$statistics$mean_precursors_per_window),
             color = "blue", fontface = "bold") +
    labs(
      title = "Window Efficiency: Precursors per Window",
      subtitle = sprintf("CV: %.3f | Range: %d - %d",
                        windows$statistics$cv_precursors,
                        min(window_data$n_precursors),
                        max(window_data$n_precursors)),
      x = "Window ID (sorted by precursor count)",
      y = "Number of Precursors",
      caption = "Blue dashed line = mean | Low CV = uniform distribution"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      axis.text.x = element_blank(),
      panel.grid.major.x = element_blank()
    )

  return(p)
}
```

**해석**:
- 균일한 높이: Good uniform density (Variable mode)
- 불균일한 높이: Unequal distribution (Fixed mode)
- CV < 0.3: Excellent uniformity

---

### Plot 8: DPPP Achievement Heatmap

**목적**: Window별 DPPP 달성도 시각화

**데이터**: Phase 2 diagnosis + Phase 3D windows

**알고리즘**:
```r
plot_dppp_achievement_heatmap <- function(diagnosis, windows) {
  # Calculate DPPP achievement for each window
  # (requires recalculating DPPP for optimized windows)

  dppp_data <- diagnosis$current_state$dppp_distribution
  window_data <- windows$windows

  # Assign each precursor to a window
  dppp_data <- dppp_data %>%
    rowwise() %>%
    mutate(
      window_id = {
        matching_windows <- which(
          window_data$mz_start <= mz &
          window_data$mz_end >= mz &
          window_data$rt_start <= rt &
          window_data$rt_end >= rt
        )
        if (length(matching_windows) > 0) matching_windows[1] else NA
      }
    ) %>%
    filter(!is.na(window_id))

  # Calculate mean DPPP per window
  window_dppp <- dppp_data %>%
    group_by(window_id) %>%
    summarise(
      mean_dppp = mean(dppp_value),
      meets_target = mean(meets_target),
      .groups = "drop"
    ) %>%
    left_join(window_data, by = "window_id")

  # Plot heatmap
  p <- ggplot(window_dppp, aes(x = rt_midpoint, y = mz_center,
                                fill = meets_target)) +
    geom_tile() +
    scale_fill_gradient2(
      low = "red",
      mid = "yellow",
      high = "green",
      midpoint = 0.5,
      limits = c(0, 1),
      name = "Target\nAchievement"
    ) +
    labs(
      title = "DPPP Achievement Heatmap (by Window)",
      subtitle = sprintf("Overall satisfaction: %.1f%%",
                        diagnosis$current_state$satisfaction_ratio * 100),
      x = "Retention Time (min)",
      y = "Window Center m/z (Da)",
      caption = "Green = meeting target | Red = not meeting target"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      legend.position = "right"
    )

  return(p)
}
```

**해석**:
- 초록색: Window가 target DPPP 달성
- 빨간색: Window가 target DPPP 미달성

---

## 구현 가이드

### 파일 구조

```r
# R/stage4_visualization.R

# =====================================================
# Phase 4: Visualization & Reporting
# =====================================================

library(ggplot2)
library(gridExtra)
library(viridis)
library(scales)

#' Generate All Visualizations (Main Function)
#'
#' @param all_results List with all previous phase outputs
#' @param output_dir Character, output directory path
#' @param create_pdf Logical, create comprehensive PDF report
#' @param create_individual_plots Logical, export individual plots
#' @param plot_format Character, "png" or "pdf"
#' @param plot_dpi Numeric, plot resolution (default: 300)
#'
#' @return VisualizationResult object
#' @export
generate_visualizations <- function(
  all_results,
  output_dir = "output/",
  create_pdf = TRUE,
  create_individual_plots = TRUE,
  plot_format = "png",
  plot_dpi = 300
) {
  cat("=== Phase 4: Visualization & Reporting ===\n\n")

  # TODO: Implement comprehensive visualization generation
  # 1. Generate 8 required plots
  # 2. Export individual plots (optional)
  # 3. Create PDF report (optional)
  # 4. Export method file (CSV)
  # 5. Calculate summary statistics
  # 6. Package results

  stop("Not implemented yet")
}

#' Plot 1: DPPP Density
#' @export
plot_dppp_density <- function(diagnosis) {
  # TODO: Implement DPPP density heatmap
  stop("Not implemented yet")
}

#' Plot 2: RT Window Size
#' @export
plot_rt_window_size <- function(windows) {
  # TODO: Implement RT window size bar plot
  stop("Not implemented yet")
}

#' Plot 3: RT × m/z Density Heatmap
#' @export
plot_rt_mz_density_heatmap <- function(validated_data, bins = 50) {
  # TODO: Implement precursor density heatmap
  stop("Not implemented yet")
}

#' Plot 4: m/z Normalized Density
#' @export
plot_mz_normalized_density <- function(rt_binning, mz_range) {
  # TODO: Implement normalized density profiles
  stop("Not implemented yet")
}

#' Plot 5: m/z Window Width
#' @export
plot_mz_window_width <- function(windows) {
  # TODO: Implement window width scatter plot
  stop("Not implemented yet")
}

#' Plot 6: Precursor Coverage Map
#' @export
plot_precursor_coverage_map <- function(windows, validated_data) {
  # TODO: Implement coverage map
  stop("Not implemented yet")
}

#' Plot 7: Window Efficiency
#' @export
plot_window_efficiency <- function(windows) {
  # TODO: Implement window efficiency bar plot
  stop("Not implemented yet")
}

#' Plot 8: DPPP Achievement Heatmap
#' @export
plot_dppp_achievement_heatmap <- function(diagnosis, windows) {
  # TODO: Implement DPPP achievement heatmap
  stop("Not implemented yet")
}

#' Create PDF Report
#'
#' @param plots List of ggplot objects
#' @param summary_stats List of summary statistics
#' @param output_file Character, output PDF path
#'
#' @export
create_pdf_report <- function(plots, summary_stats, output_file) {
  # TODO: Implement multi-panel PDF report
  # 1. Arrange plots in grid
  # 2. Add summary statistics
  # 3. Add parameters table
  # 4. Export to PDF

  stop("Not implemented yet")
}

#' Export Method File
#'
#' @param windows WindowGenerationResult
#' @param output_file Character, output CSV path
#'
#' @export
export_method_file <- function(windows, output_file) {
  # TODO: Implement method file export
  # CSV format: RT_start, RT_end, Center_mz, Window_width

  stop("Not implemented yet")
}

#' Export Individual Plots
#'
#' @param plots List of ggplot objects
#' @param output_dir Character, output directory
#' @param format Character, "png" or "pdf"
#' @param dpi Numeric, resolution
#'
#' @export
export_individual_plots <- function(
  plots,
  output_dir,
  format = "png",
  dpi = 300
) {
  # TODO: Implement individual plot export
  stop("Not implemented yet")
}
```

---

## 테스트 전략

### Mock Data 생성

**파일**: `tests/mocks/mock_stage4_output.R`

```r
#' Create Mock Stage 4 Output
#'
#' @return VisualizationResult object
#' @export
create_mock_stage4_output <- function() {
  # Load all previous mocks
  source("tests/mocks/mock_stage1_output.R")
  source("tests/mocks/mock_stage2_output.R")
  source("tests/mocks/mock_stage3a_output.R")
  source("tests/mocks/mock_stage3b_output.R")
  source("tests/mocks/mock_stage3c_output.R")
  source("tests/mocks/mock_stage3d_output.R")

  # Create mock plots (empty ggplot objects)
  mock_plots <- list(
    dppp_density = ggplot() + labs(title = "Mock DPPP Density"),
    rt_window_size = ggplot() + labs(title = "Mock RT Window Size"),
    rt_mz_heatmap = ggplot() + labs(title = "Mock RT × m/z Heatmap"),
    mz_normalized_density = ggplot() + labs(title = "Mock m/z Normalized Density"),
    mz_window_width = ggplot() + labs(title = "Mock m/z Window Width"),
    precursor_coverage_map = ggplot() + labs(title = "Mock Coverage Map"),
    window_efficiency = ggplot() + labs(title = "Mock Window Efficiency"),
    dppp_achievement_heatmap = ggplot() + labs(title = "Mock DPPP Achievement")
  )

  # Create result
  result <- structure(
    list(
      plots = mock_plots,

      report_files = list(
        pdf_report = "output/mock_report.pdf",
        method_file = "output/mock_method.csv",
        individual_plots = c(
          "output/plot1_dppp_density.png",
          "output/plot2_rt_window_size.png",
          "output/plot3_rt_mz_heatmap.png",
          "output/plot4_mz_normalized_density.png",
          "output/plot5_mz_window_width.png",
          "output/plot6_precursor_coverage_map.png",
          "output/plot7_window_efficiency.png",
          "output/plot8_dppp_achievement_heatmap.png"
        )
      ),

      summary_statistics = list(
        optimization_metrics = list(
          target_dppp = 7.0,
          satisfaction_ratio = 0.85,
          coverage_ratio = 0.95
        ),
        performance_metrics = list(
          total_windows = 100,
          mean_precursors_per_window = 100,
          cv_precursors = 0.15
        ),
        quality_metrics = list(
          mean_window_width = 10.0,
          cv_window_width = 0.20
        )
      ),

      metadata = list(
        generation_timestamp = Sys.time(),
        plot_generation_time = 15.0,
        report_generation_time = 5.0
      )
    ),
    class = c("VisualizationResult", "list")
  )

  return(result)
}
```

---

### Unit Tests

**파일**: `tests/test_stage4.R`

```r
library(testthat)
library(ggplot2)
source("tests/mocks/mock_stage1_output.R")
source("tests/mocks/mock_stage2_output.R")
source("tests/mocks/mock_stage3d_output.R")
source("R/stage4_visualization.R")

# =====================================================
# Test: Individual Plot Generation
# =====================================================

test_that("plot_dppp_density generates valid ggplot", {
  # Setup
  diagnosis <- create_mock_stage2_output()

  # Execute
  plot <- plot_dppp_density(diagnosis)

  # Verify
  expect_s3_class(plot, "ggplot")
  expect_silent(print(plot))
})

test_that("plot_rt_window_size generates valid ggplot", {
  windows <- create_mock_stage3d_output()
  plot <- plot_rt_window_size(windows)

  expect_s3_class(plot, "ggplot")
  expect_silent(print(plot))
})

# ... (Similar tests for all 8 plots)

# =====================================================
# Test: PDF Report Generation
# =====================================================

test_that("create_pdf_report generates PDF file", {
  # Setup
  output_file <- tempfile(fileext = ".pdf")

  plots <- list(
    plot1 = ggplot() + labs(title = "Plot 1"),
    plot2 = ggplot() + labs(title = "Plot 2")
  )

  summary_stats <- list(
    metric1 = 100,
    metric2 = 0.95
  )

  # Execute
  create_pdf_report(plots, summary_stats, output_file)

  # Verify
  expect_true(file.exists(output_file))
  expect_true(file.size(output_file) > 0)

  # Cleanup
  unlink(output_file)
})

# =====================================================
# Test: Method File Export
# =====================================================

test_that("export_method_file creates CSV file", {
  # Setup
  windows <- create_mock_stage3d_output()
  output_file <- tempfile(fileext = ".csv")

  # Execute
  export_method_file(windows, output_file)

  # Verify file exists
  expect_true(file.exists(output_file))

  # Read and verify CSV structure
  method_data <- read.csv(output_file)
  expect_true(all(c("RT_start", "RT_end", "Center_mz", "Window_width") %in%
                  colnames(method_data)))
  expect_equal(nrow(method_data), nrow(windows$windows))

  # Cleanup
  unlink(output_file)
})

# =====================================================
# Test: Individual Plot Export
# =====================================================

test_that("export_individual_plots saves plot files", {
  # Setup
  output_dir <- tempdir()
  plots <- list(
    plot1 = ggplot() + labs(title = "Plot 1"),
    plot2 = ggplot() + labs(title = "Plot 2")
  )

  # Execute
  export_individual_plots(plots, output_dir, format = "png", dpi = 150)

  # Verify files exist
  expected_files <- file.path(output_dir, c("plot1.png", "plot2.png"))
  for (f in expected_files) {
    expect_true(file.exists(f))
    expect_true(file.size(f) > 0)
  }

  # Cleanup
  unlink(expected_files)
})

# =====================================================
# Test: Integrated Visualization
# =====================================================

test_that("generate_visualizations creates all outputs", {
  # Setup
  all_results <- list(
    validated_data = create_mock_stage1_output(),
    diagnosis = create_mock_stage2_output(),
    windows = create_mock_stage3d_output()
  )

  output_dir <- tempdir()

  # Execute
  result <- generate_visualizations(
    all_results = all_results,
    output_dir = output_dir,
    create_pdf = TRUE,
    create_individual_plots = TRUE
  )

  # Verify class
  expect_s3_class(result, "VisualizationResult")

  # Verify plots generated
  expect_equal(length(result$plots), 8)
  for (plot_name in names(result$plots)) {
    expect_s3_class(result$plots[[plot_name]], "ggplot")
  }

  # Verify report files
  expect_true(!is.null(result$report_files$pdf_report))
  expect_true(!is.null(result$report_files$method_file))

  # Verify summary statistics
  expect_true(!is.null(result$summary_statistics$optimization_metrics))
})
```

---

## Definition of Done

Phase 4 개발 완료 기준:

### 기능 완성도
- [ ] 8가지 필수 plot 함수 구현 완료
- [ ] `create_pdf_report()` 구현 완료
- [ ] `export_method_file()` 구현 완료
- [ ] `export_individual_plots()` 구현 완료
- [ ] `generate_visualizations()` 통합 함수 완료

### Plot 품질
- [ ] 모든 plot 생성 및 렌더링 확인
- [ ] High-resolution export (300 DPI)
- [ ] Publication-ready quality
- [ ] Consistent theme and style

### 테스트 커버리지
- [ ] 각 plot 함수 unit test 통과
- [ ] PDF report generation test 통과
- [ ] Method file export test 통과
- [ ] Individual plot export test 통과
- [ ] Integrated visualization test 통과

### 코드 품질
- [ ] 모든 함수 roxygen2 문서화
- [ ] 에러 처리 구현
- [ ] 진행 상황 출력
- [ ] 코드 리뷰 완료

### 출력 파일
- [ ] PDF report 생성 확인
- [ ] Method CSV file 생성 확인
- [ ] Individual PNG/PDF plots 생성 확인
- [ ] 파일 형식 및 내용 검증

### 문서화
- [ ] Plot별 해석 가이드 작성
- [ ] API 문서 업데이트
- [ ] Phase 4 개발 가이드 완료
- [ ] DEVELOPMENT.md 업데이트

### 검증
- [ ] 8가지 plot 모두 정상 렌더링
- [ ] PDF report < 10 MB
- [ ] Method file Thermo compatible
- [ ] Plot generation < 30초
- [ ] Report generation < 1분

---

## 참고 자료

### 관련 문서
- [API Specification](../API_SPECIFICATION.md)
- [Phase 3D: Window Generation](PHASE3D_WINDOW_GENERATION.md)

### 관련 코드
- `R/visualizer.R` - 기존 visualization 함수 (참조)

### ggplot2 Theme 설정

```r
# Custom theme for consistent styling
theme_dia_optimizer <- function() {
  theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 11, color = "gray30"),
      axis.title = element_text(size = 11),
      axis.text = element_text(size = 10),
      legend.title = element_text(face = "bold", size = 10),
      legend.text = element_text(size = 9),
      panel.grid.minor = element_blank()
    )
}
```

### Method File Format (Thermo Orbitrap)

```csv
RT_start,RT_end,Center_mz,Window_width,Collision_energy
10.0,15.0,450.5,20.0,27
10.0,15.0,470.5,20.0,27
15.0,20.0,460.5,25.0,27
...
```

---

## 개발 시작하기

```bash
# 1. 모든 이전 Phase 완료 확인
R
source("tests/mocks/mock_stage1_output.R")
source("tests/mocks/mock_stage2_output.R")
source("tests/mocks/mock_stage3d_output.R")

# 2. Phase 4 파일 생성
# R/stage4_visualization.R

# 3. 첫 plot 함수 구현 (plot_dppp_density)
# 가장 단순한 heatmap부터 시작

# 4. Unit test 작성 및 실행
source("tests/test_stage4.R")
test_file("tests/test_stage4.R")

# 5. Plot 저장 테스트
ggsave("test_plot.png", plot_dppp_density(mock_diagnosis), dpi = 300)
```

**개발 순서 권장**:
1. `plot_dppp_density()` - 2D heatmap
2. `plot_rt_window_size()` - Bar plot
3. `plot_rt_mz_density_heatmap()` - Density heatmap
4. `plot_mz_normalized_density()` - Line plot
5. `plot_mz_window_width()` - Scatter plot
6. `plot_precursor_coverage_map()` - Coverage map
7. `plot_window_efficiency()` - Bar plot
8. `plot_dppp_achievement_heatmap()` - Achievement heatmap
9. `export_method_file()` - CSV export
10. `create_pdf_report()` - PDF report
11. `generate_visualizations()` - 통합 함수

---

**End of Phase 4 Development Guide**
