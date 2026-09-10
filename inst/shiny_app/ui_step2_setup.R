# ui_step2_setup.R - Three decisions, with related parameters on compact rows.

step2_setup_ui <- function() {
  help <- .workflow_help
  row <- .workflow_row
  section <- function(number, title, ...) {
    .workflow_section("config", number, title, ...,
      action = actionButton(paste0("reset_", c("sampling", "windows", "rt")[[as.integer(number)]]),
          "Reset", class = "config-reset btn-sm", icon = icon("undo"),
          title = "Restore this section to the last confirmed settings for this instrument, or its defaults before confirmation.")
    )
  }
  smoothing_help <- p("Whittaker-Henderson smoothing reduces abrupt m/z boundary changes between RT groups.")

  tabItem(tabName = "setup",
    tags$script(src = "configure-help.js"),
    div(class = "configure-compact",
      div(class = "workflow-heading",
        tags$p(class = "workflow-eyebrow", "STEP 2 OF 3"),
        h2("Configure your windows"),
        uiOutput("draft_status")
      ),

      section("1", "Peak sampling target",
        conditionalPanel(condition = "output.is_parallel_instrument == false", class = "config-sampling-sequential",
          row("Sampling target",
            numericInput("target_dppp", "Points / peak", value = 7, min = 1, max = 15, step = 0.5),
            sliderInput("target_satisfaction", "Peaks meeting target", min = 50, max = 95,
                        value = 70, step = 5, post = "%", ticks = FALSE),
            div(class = "config-presets",
              actionButton("preset_id", "ID", class = "btn-sm dppp-preset-btn dppp-btn-id"),
              actionButton("preset_balanced", "Balanced", class = "btn-sm dppp-preset-btn dppp-btn-bal"),
              actionButton("preset_quant", "Quant", class = "btn-sm dppp-preset-btn dppp-btn-quant")
            ),
            info = help("Peak sampling target",
              p("DPPP is the number of data points across a peak: 1.7 \u00d7 FWHM / cycle time."),
              p("Choose the target and the percentage of peaks that should meet it. Automatic window count uses these settings for sequential instruments."),
              p("Presets: Identification 1.5 - Balanced 4.0 - Quantification 7.0."),
              uiOutput("dppp_window_count_preview"))
          )
        ),
        conditionalPanel(condition = "output.is_parallel_instrument == true", class = "config-sampling-parallel",
          row("Parallel acquisition",
            div(class = "config-stat", tags$span("Sync-optimal"), uiOutput("sync_hero_window_count")),
            div(class = "config-stat", tags$span("Peak sampling check"), uiOutput("sync_dppp_confirmation")),
            info = help("Parallel acquisition",
              p("Window count follows MS1/MS2 synchronization. DPPP checks peak sampling against the selected target."),
              p("Cycle time = max(MS1, N \u00d7 MS2)."), uiOutput("sync_detail_panel"))
          )
        ),
        tags$details(class = "config-more",
          tags$summary("Scan settings"),
          row("MS1 scans",
            numericInput("ms1_scans_per_cycle", "Per cycle", value = 1, min = 0, max = 10, step = 1),
            info = help("MS1 scans per cycle", p("Controls MS1 scans in the acquisition cycle. Standard DIA commonly uses 1; Boxcar can use 3\u20134. Parallel acquisition uses its instrument timing model.")))
        )
      ),

      section("2", "Window design",
        div(class = "config-methods",
          div(class = "config-method",
            div(class = "config-method-label", tags$label(id = "mz_strategy-label", `for` = "mz_strategy", "m/z range strategy"),
              help("m/z range strategy", p("Selects the m/z range to cover in each RT group. KDE locates the main density peak."),
                   p("These illustrations describe the methods; they are not plots of your uploaded data."), uiOutput("strategy_preview_img"))),
            selectInput("mz_strategy", NULL,
              choices = c("KDE" = "kde", "Greedy" = "greedy", "Quantile" = "quantile",
                          "Coverage" = "coverage", "Outlier" = "outlier"), selected = "kde")
          ),
          div(class = "config-method",
            div(class = "config-method-label", tags$label(id = "window_mode-label", `for` = "window_mode", "Window width mode"),
              help("Window width mode",
                p("Density: narrower windows in dense m/z regions, wider windows in sparse regions. Fixed: equal widths. Staggered: two cycles with a half-window offset."),
                p("For staggered acquisition, set Thermo Loop Control N in the method editor to the windows per RT bin per cycle, reported after optimization."),
                uiOutput("window_mode_preview_img"))),
            selectInput("window_mode", NULL,
              choices = c("Density" = "density", "Fixed" = "fixed", "Staggered" = "staggered"), selected = "density")
          )
        ),
        div(class = "config-design-grid",
          div(class = "config-design-controls",
        row("Window count",
          checkboxInput("auto_windows", "Auto", value = TRUE),
          conditionalPanel(condition = "input.auto_windows", class = "config-count-output", uiOutput("auto_windows_info")),
          conditionalPanel(condition = "!input.auto_windows",
            sliderInput("manual_n_windows", "Per RT bin", min = 10, max = 200, value = 40, step = 5, ticks = FALSE)),
          info = help("Window count", p("Auto uses acquisition timing and peak sampling settings. Turn Auto off to set the count manually. In staggered mode this is the count per RT bin per cycle."))
        ),

        conditionalPanel(condition = "input.mz_strategy == 'kde'",
          row("KDE range",
            sliderInput("kde_density_threshold", "Density cutoff", min = 5, max = 30, value = 10, step = 5, post = "%", ticks = FALSE),
            sliderInput("kde_min_coverage", "Min. precursor inclusion", min = 60, max = 95, value = 80, step = 5, post = "%", ticks = FALSE),
            info = help("KDE range selection",
              p("Density cutoff is a percentage of the KDE peak height. Lower values generally select a wider range around the density peak."),
              p("Minimum precursor inclusion sets the coverage target for range selection. Final window coverage is reported in Results.")))
        ),
        conditionalPanel(condition = "input.mz_strategy == 'greedy'",
          row("Greedy range",
            numericInput("greedy_range_width", "Total m/z span", value = 200, min = 1, step = 10),
            uiOutput("greedy_mz_range_display"),
            info = help("Greedy range selection",
              p("Finds the most precursors within your chosen m/z span in each RT group. For example, 100 m/z with 50 windows maps to an internal minimum width of 2 m/z."),
              p("Auto uses the calculated window count. Density mode varies individual window widths; the derived width is a design setting, not a promise of equal-width windows. Smoothing and boundary rounding can change the final selected span."))),
          tags$details(class = "config-more",
            tags$summary("Greedy search details"),
            row("Search details",
              sliderInput("greedy_mz_step", "Search step (m/z)", min = 0.5, max = 10, value = 2, step = 0.5, ticks = FALSE),
              checkboxInput("greedy_apply_smoothing", "Smooth boundaries", value = TRUE),
              info = help("Greedy search details",
                p("A smaller search step searches more starting positions and takes longer. It does not change the chosen span."), smoothing_help)))
        ),
        conditionalPanel(condition = "input.mz_strategy == 'quantile'",
          row("Quantile range",
            sliderInput("quantile_exclude_low", "Exclude low m/z", min = 1, max = 20, value = 5, step = 1, post = "%", ticks = FALSE),
            sliderInput("quantile_exclude_high", "Exclude high m/z", min = 1, max = 20, value = 5, step = 1, post = "%", ticks = FALSE),
            checkboxInput("quantile_apply_smoothing", "Smooth boundaries", value = TRUE),
            info = help("Quantile range selection", p("Exclude the selected percentage of precursors from each end of the m/z distribution. Excluding 5% from each end keeps the central 90% before smoothing and window generation."), smoothing_help)),
          div(class = "config-derived-value", textOutput("quantile_retained"))
        ),
        conditionalPanel(condition = "input.mz_strategy == 'coverage'",
          row("Coverage range",
            sliderInput("target_coverage", "Precursor inclusion target", min = 70, max = 99, value = 90, step = 1, post = "%", ticks = FALSE),
            info = help("Coverage range selection", p("Finds the minimum m/z range achieving the selected precursor inclusion. Final window coverage is reported separately in Results.")))
        ),
        conditionalPanel(condition = "input.mz_strategy == 'outlier'",
          row("Outlier range",
            sliderInput("outlier_threshold", "Threshold (\u00d7 SD)", min = 2, max = 4, value = 3, step = 0.5, ticks = FALSE),
            checkboxInput("outlier_apply_smoothing", "Smooth boundaries", value = TRUE),
            info = help("Outlier range selection", p("Selects a range around the mean m/z, plus or minus the chosen number of standard deviations."), smoothing_help))
        ),

        row("Isolation widths",
          conditionalPanel(condition = "input.mz_strategy != 'greedy'",
            numericInput("min_isolation_width", "Min. target (m/z)", value = 2, min = aidia:::ABSOLUTE_MIN_WIDTH_DA, step = 0.5)),
          numericInput("max_isolation_width", "Max width (m/z)", value = 80, min = 10, max = 500, step = 5),
          info = help("Isolation window width",
            p("These settings apply to individual isolation windows. The initial values follow the selected instrument preset. The minimum is a design target and may be relaxed during window generation."),
            p("Min. target must be at least 1 m/z and below Max width."),
            p("Greedy derives its minimum setting from Total m/z span divided by window count. Max width limits broad individual windows in sparse m/z regions; it does not set the total search span."))
        ),
        row("Isotope boundary",
          selectInput("fz_offset_preset", "Offset preset", choices = c(
            "Standard proteomics - 0.25" = "0.25", "Phosphoproteomics - 0.18" = "0.18",
            "Custom" = "custom", "Disabled" = "0"), selected = "0.25"),
          conditionalPanel(condition = "input.fz_offset_preset == 'custom'",
            numericInput("custom_fz_offset", "Offset", value = 0.2500, min = 0.0001, max = 0.9999, step = 0.0001)),
          info = help("Isotope boundary effect",
            p("Offsets window boundaries away from integer m/z positions where isotope envelopes cluster, reducing the chance of splitting isotope peaks between windows."),
            p("The plot below uses the uploaded data and updates when the offset changes. Window-design previews update automatically. Downloads use the last confirmed result."))
        ),
        conditionalPanel(condition = "input.fz_offset_preset != '0'",
          div(class = "config-boundary-plot",
            conditionalPanel(condition = "!output.data_loaded", tags$p(class = "text-muted", "Upload data to view the isotope boundary effect.")),
            conditionalPanel(condition = "output.data_loaded", plotOutput("fz_validation_plot", height = "200px"))
          )
        )
          ),
          div(class = "config-preview",
            div(class = "config-preview-heading",
              tags$strong("m/z preview"),
              help("Live m/z preview",
                p("All RT groups shows your complete validated precursor distribution on an RT-m/z plane, using the report density heatmap. Brighter regions have higher density. Green outlines mark the selected m/z range in each RT group, so data outside the selection remains visible. The heatmap is a distribution view, not the KDE range-selection threshold."),
                p("For an individual RT group, the grey distribution uses all precursors in that group. Green shading marks the selected m/z range; the strip below shows the actual generated windows."),
                p("For KDE, the curve and dashed threshold use the same density estimator as range selection. Minimum inclusion and window constraints may limit the effect of threshold changes."),
                p("Changing the viewed RT group does not change the method. Confirm & view results preserves the current calculation for download."))
            ),
            conditionalPanel(condition = "!output.preview_ready",
              div(class = "preview-placeholder", textOutput("preview_waiting"), uiOutput("preview_error"))),
            conditionalPanel(condition = "output.preview_ready",
              selectInput("preview_rt_bin", "View", choices = c("All RT groups" = "all"), selected = "all"),
              div(class = "preview-plot-scroll", plotOutput("live_mz_plot", height = "270px")),
              div(class = "preview-legend",
                conditionalPanel(condition = "input.preview_rt_bin != 'all'",
                  tags$span(class = "legend-original", "Data")),
                tags$span(class = "legend-range", "Selected range"),
                conditionalPanel(condition = "input.mz_strategy == 'kde' && input.preview_rt_bin != 'all'",
                  tags$span(class = "legend-threshold", "KDE threshold")),
                conditionalPanel(condition = "input.preview_rt_bin != 'all'",
                  tags$span(class = "legend-windows", "Windows"))),
              uiOutput("live_mz_summary"))
          )
        )
      ),

      section("3", "Retention-time grouping",
        row("RT groups",
          selectInput("rt_binning_mode", "Grouping mode", choices = c(
            "Automatic duration" = "fixed", "Detect distribution changes" = "adaptive", "Choose duration" = "custom"), selected = "fixed"),
          conditionalPanel(condition = "input.rt_binning_mode == 'custom'",
            sliderInput("rt_bin_width", "Group duration (min)", min = 1, max = 15, value = 5, step = 0.5, ticks = FALSE)),
          info = help("Retention-time grouping",
            p("Each RT group gets its own set of m/z windows. Automatic duration calculates a regular group duration. Detect distribution changes uses a KS test to place boundaries. Choose duration uses your selected duration."),
            p("Shorter durations create more RT groups."))
        ),
        conditionalPanel(condition = "input.rt_binning_mode == 'adaptive'",
          row("Change detection",
            sliderInput("cpd_significance", "Significance", min = 0.001, max = 0.10, value = 0.05, step = 0.005, ticks = FALSE),
            sliderInput("cpd_min_bin_width", "Min. group width (min)", min = 0.5, max = 5, value = 1, step = 0.5, ticks = FALSE),
            info = help("Adaptive group parameters", p("Lower significance requires stronger evidence for a change point. Minimum group width prevents very short RT groups.")))
        ),
        tags$details(class = "config-more",
          tags$summary("Run start / end settings"),
          row("RT edges",
            numericInput("edge_void_buffer", "Start buffer (min)", value = 0.5, min = 0, max = 2, step = 0.1),
            numericInput("edge_wash_threshold", "End merge (precursors)", value = 30, min = 0, max = 200, step = 10),
            info = help("RT edge handling",
              p("Start buffer extends the first group's start to account for void volume. End merge combines a sparse last group when its precursor count is below the threshold.")))
        )
      ),
      uiOutput("setup_navigation_feedback"),
      div(class = "wizard-nav wizard-nav-between",
        actionButton("btn_to_data", "Back to data", class = "btn-default", icon = icon("arrow-left")),
        actionButton("run_optimization", "Confirm & view results", class = "btn-success", icon = icon("play"))
      )
    )
  )
}
