# Compare delivered geometry while keeping optimization inputs immutable.
.shiny_delivered_windows <- function(windows, options = list()) {
  end <- options$acquisition_end_min
  if (is.null(end) || is.na(end)) end <- max(windows$rt_end)
  aidia:::.prepare_thermo_windows(windows, fill_void = isTRUE(options$fill_void),
    acquisition_end_min = end)
}

.shiny_result_comparison <- function(run, validated_data, export_options = list()) {
  # Acquisition boundaries supersede the earlier optimization-bin labels.
  data <- validated_data$data
  data$rt_group <- NULL
  designed <- .shiny_delivered_windows(run$windows$windows, export_options)
  delivered <- run$windows
  delivered$windows <- designed
  original <- aidia:::.fixed_baseline_windows(run$plan, delivered)
  if (is.null(original)) stop("Original method settings were not saved with this result.")
  methods <- list(Original = original, Designed = designed)
  accounting <- lapply(methods, aidia:::.account_window_precursors, precursor_data = data)
  reference <- aidia:::.original_method_settings(run$plan, run$windows)
  cycles <- c(Original = reference$cycle_time_sec %||% run$plan$diagnosis$current_cycle_time_sec %||% NA_real_,
    Designed = run$windows$dppp_verification$actual_cycle_time_sec %||%
      run$plan$actual_cycle_time_sec %||% NA_real_)
  cycles[!is.finite(cycles) | cycles <= 0] <- NA_real_
  fwhm <- if ("FWHM" %in% names(data)) {
    aidia::ensure_fwhm_seconds(data$FWHM, unit = validated_data$metadata$fwhm_unit)
  } else numeric()
  fwhm <- fwhm[is.finite(fwhm) & fwhm > 0]
  median_fwhm <- if (length(fwhm)) median(fwhm) else NA_real_
  ms1 <- c(reference$timing$ms1$scans_per_cycle %||% NA_real_,
    run$plan$instrument$ms1_scans_per_cycle %||% NA_real_)
  parallel <- c(identical(reference$timing$instrument$cycle_calculation, "parallel") || isTRUE(ms1[1] == 0),
    identical(run$plan$instrument$cycle_mode, "parallel") || isTRUE(ms1[2] == 0))
  ms1[parallel] <- NA_real_ # Zero is a parallel-mode flag, not zero acquired MS1 scans.
  cycle_groups <- if ("cycle" %in% names(designed)) interaction(designed$rt_segment_id, designed$cycle) else designed$rt_segment_id
  per_cycle <- c(reference$n_windows, run$windows$dppp_verification$actual_windows_per_bin %||%
    mean(as.numeric(table(cycle_groups))))
  rt_span <- range(data$RT.Apex, finite = TRUE)
  duration_sec <- diff(rt_span) * 60
  summary <- data.frame(method = names(methods),
    coverage = vapply(accounting, function(x) x$statistics$coverage_percentage, numeric(1)),
    dppp = 1.7 * median_fwhm / as.numeric(cycles), cycle = as.numeric(cycles),
    cycle_count = duration_sec / as.numeric(cycles),
    ms1_scans = duration_sec * ms1 / as.numeric(cycles),
    ms2_scans = duration_sec * per_cycle / as.numeric(cycles),
    windows_per_cycle = per_cycle,
    mean_width = vapply(methods, function(w) mean(w$window_width), numeric(1)),
    parallel = parallel)
  list(data = data, methods = methods, accounting = accounting, summary = summary,
    reference = reference, delivered = delivered, plan = run$plan, rt_span = rt_span)
}

.shiny_tradeoff_table <- function(comparison) {
  x <- comparison$summary
  fields <- c("dppp", "cycle", "cycle_count", "ms1_scans", "ms2_scans", "windows_per_cycle", "mean_width")
  labels <- c("Est. median DPPP", "Est. cycle time (s)", "Est. acquisition cycles", "Est. MS1 scans in analysis",
    "Est. MS2 scans in analysis", "MS2 windows / cycle (mean)", "Isolation width (m/z, mean)")
  fmt <- function(value, digits) if (is.finite(value)) formatC(value, format = "f", digits = digits, big.mark = ",") else "Unavailable"
  rows <- lapply(seq_along(fields), function(i) {
    values <- x[[fields[i]]]
    digits <- if (fields[i] == "cycle") 3 else if (fields[i] %in% c("cycle_count", "ms1_scans", "ms2_scans")) 0 else 1
    displayed <- vapply(values, fmt, character(1), digits = digits)
    if (fields[i] == "ms1_scans") displayed[x$parallel] <- "Parallel"
    change <- if (all(is.finite(values))) formatC(diff(values), format = "f", digits = digits, big.mark = ",", flag = "+") else "--"
    if (all(is.finite(values)) && abs(diff(values)) < 0.5 * 10^-digits) change <- "Unchanged"
    data.frame(Metric = labels[i], Original = displayed[1], Designed = displayed[2], Change = change)
  })
  do.call(rbind, rows)
}

.shiny_comparison_theme <- function() {
  ggplot2::theme_minimal(base_size = 12) + ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    strip.text = ggplot2::element_text(face = "bold", hjust = 0),
    plot.title = ggplot2::element_text(face = "bold", size = 12),
    plot.subtitle = ggplot2::element_text(color = "#536878", size = 10),
    legend.position = "bottom", legend.title = ggplot2::element_text(size = 10),
    plot.margin = ggplot2::margin(8, 12, 8, 8))
}

.shiny_selection_outlines <- function(windows) {
  # Preserve actual gaps and overlap when outlining each RT segment's union.
  segments <- split(windows, paste(windows$rt_start, windows$rt_end))
  do.call(rbind, lapply(segments, function(w) {
    w <- w[order(w$mz_start, w$mz_end), ]
    ends <- cummax(w$mz_end)
    # The overview joins seams within the center/width CSV rounding precision.
    # Individual-window mode still draws the exact delivered boundaries.
    group <- cumsum(c(TRUE, w$mz_start[-1] > head(ends, -1) + 0.0001500001))
    do.call(rbind, lapply(split(w, group), function(part) {
      data.frame(rt_start = part$rt_start[1], rt_end = part$rt_end[1],
        mz_start = min(part$mz_start), mz_end = max(part$mz_end))
    }))
  }))
}

.shiny_plot_selection_comparison <- function(comparison, show_windows = FALSE) {
  # Bin once, then reuse the exact same background and scale for both panels.
  # Aggregate before plotting to bound browser render cost for large reports.
  data <- comparison$data
  windows <- do.call(rbind, lapply(names(comparison$methods), function(method) {
    w <- comparison$methods[[method]]
    if (!show_windows) w <- .shiny_selection_outlines(w)
    data.frame(rt_start = w$rt_start, rt_end = w$rt_end,
      mz_start = w$mz_start, mz_end = w$mz_end,
      method = factor(method, levels = names(comparison$methods)))
  }))
  rt_lim <- range(c(data$RT.Apex, windows$rt_start, windows$rt_end), finite = TRUE)
  mz_lim <- range(c(data$Precursor.Mz, windows$mz_start, windows$mz_end), finite = TRUE)
  breaks_for <- function(limits) {
    if (diff(limits) == 0) limits <- limits + c(-0.5, 0.5)
    seq(limits[1], limits[2], length.out = 101)
  }
  rt_breaks <- breaks_for(rt_lim)
  mz_breaks <- breaks_for(mz_lim)
  rt_bin <- cut(data$RT.Apex, rt_breaks, include.lowest = TRUE, labels = FALSE)
  mz_bin <- cut(data$Precursor.Mz, mz_breaks, include.lowest = TRUE, labels = FALSE)
  valid <- !is.na(rt_bin) & !is.na(mz_bin)
  cells <- as.data.frame(table(rt_bin = factor(rt_bin[valid], levels = 1:100),
    mz_bin = factor(mz_bin[valid], levels = 1:100)))
  cells <- cells[cells$Freq > 0, ]
  cells$rt <- (head(rt_breaks, -1) + diff(rt_breaks) / 2)[as.integer(cells$rt_bin)]
  cells$mz <- (head(mz_breaks, -1) + diff(mz_breaks) / 2)[as.integer(cells$mz_bin)]
  ggplot2::ggplot() +
    ggplot2::geom_tile(data = cells, ggplot2::aes(rt, mz, fill = Freq),
      width = diff(rt_breaks)[1], height = diff(mz_breaks)[1]) +
    ggplot2::geom_rect(data = windows,
      ggplot2::aes(xmin = rt_start, xmax = rt_end, ymin = mz_start, ymax = mz_end),
      fill = NA, color = "#188575", linewidth = if (show_windows) 0.2 else 0.8,
      alpha = if (show_windows) 0.55 else 1) +
    ggplot2::facet_wrap(~method, nrow = 1, drop = FALSE) +
    ggplot2::scale_fill_gradient(low = "#e6edf3", high = "#314f69", trans = "sqrt",
      name = "Input precursors / cell") +
    ggplot2::coord_cartesian(xlim = rt_lim, ylim = mz_lim, expand = FALSE) +
    ggplot2::labs(x = "Retention time (min)", y = "m/z") +
    .shiny_comparison_theme() + ggplot2::theme(panel.grid = ggplot2::element_blank())
}

# Reuse the report's load-counting and IQR comparison on delivered geometry.
.shiny_plot_load_comparison <- function(comparison, view = "rt") {
  result <- comparison$delivered
  data <- comparison$data
  if (view == "whole") {
    p <- aidia:::plot_precursor_load_balance(result, list(data = data), comparison$plan,
      aggregate_rt = TRUE)
  } else {
    if (view != "rt") result$windows <- result$windows[result$windows$rt_segment_id == as.integer(view), , drop = FALSE]
    p <- aidia:::plot_precursor_load_balance(result, list(data = data), comparison$plan)
  }
  p + ggplot2::labs(title = NULL,
    caption = "Points = windows (including empty windows); band = middle 50%; line = median.") +
    .shiny_comparison_theme()
}

server_results_comparison <- function(input, output, session, rv) {
  comparison <- shiny::reactive({
    shiny::req(rv$confirmed_run, rv$validated_data)
    tryCatch(.shiny_result_comparison(rv$confirmed_run, rv$validated_data,
      .shiny_export_options(input)), error = function(e) {
        shiny::validate(shiny::need(FALSE, paste("Check the export schedule:", conditionMessage(e))))
      })
  })
  shiny::observeEvent(rv$confirmed_run, {
    shiny::req(rv$confirmed_run)
    w <- rv$confirmed_run$windows$windows
    ids <- sort(unique(w$rt_segment_id))
    choices <- c("All RT groups" = "rt", "Whole method" = "whole",
      stats::setNames(as.character(ids), paste("RT group", ids)))
    shiny::updateSelectInput(session, "comparison_load_view", choices = choices, selected = "rt")
  })
  output$comparison_coverage <- shiny::renderText({
    x <- comparison()$summary$coverage
    sprintf("Input coverage: Original %.1f%% / Designed %.1f%% (%+.1f pp)", x[1], x[2], diff(x))
  })
  output$comparison_schedule_note <- shiny::renderText({
    x <- comparison()$methods$Designed
    generic <- !is.null(input$export_format) && input$export_format != "thermo"
    sprintf("Thermo export schedule: %.2f-%.2f min. %s", min(x$rt_start), max(x$rt_end),
      if (generic) "Selected format has no RT columns; this schedule is included in the ZIP's Thermo file." else
        "RT boundaries and m/z windows match the method CSV, including run start/end options.")
  })
  output$comparison_acquisition <- shiny::renderText({
    x <- comparison()$summary$dppp
    sprintf("Est. median DPPP: Original %.1f / Designed %.1f", x[1], x[2])
  })
  output$comparison_duration <- shiny::renderText({
    rt <- comparison()$rt_span
    sprintf("Analysis duration: %.2f min (report RT %.2f-%.2f min)", diff(rt), rt[1], rt[2])
  })
  output$comparison_acquisition_table <- shiny::renderTable({
    .shiny_tradeoff_table(comparison())
  }, striped = FALSE, bordered = FALSE, spacing = "s", rownames = FALSE, width = "100%")
  output$comparison_selection_plot <- shiny::renderPlot({
    .shiny_plot_selection_comparison(comparison(), isTRUE(input$comparison_show_windows))
  }, res = 96)
  output$comparison_load_plot <- shiny::renderPlot({
    .shiny_plot_load_comparison(comparison(), input$comparison_load_view %||% "rt")
  }, res = 96)
  output$comparison_load_note <- shiny::renderText({
    x <- comparison()$accounting
    empty <- vapply(x, function(a) mean(a$windows$n_precursors == 0) * 100, numeric(1))
    sprintf("Empty windows: Original %.1f%% / Designed %.1f%%", empty[1], empty[2])
  })
  output$comparison_tradeoff <- shiny::renderText({
    x <- comparison()$summary$coverage
    sprintf("Input coverage: %.1f%% original / %.1f%% designed. Load counts input precursors across each RT interval, not simultaneous elution.", x[1], x[2])
  })
}
