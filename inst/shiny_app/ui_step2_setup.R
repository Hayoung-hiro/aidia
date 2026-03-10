# ui_step2_setup.R - Step 2: STRATEGY (DPPP Target, Strategy, Parameters)

step2_setup_ui <- function() {
  smoothing_label <- "Apply Boundary Smoothing (Whittaker-Henderson)"
  tabItem(
    tabName = "setup",

    # --- Section A: DPPP Target ---
    fluidRow(
    box(
      title = "A. DPPP Target",
      status = "primary",
      solidHeader = TRUE,
      width = 12,

      fluidRow(
        column(4, class = "label-prominent",
          numericInput(
            inputId = "target_dppp",
            label = "Target DPPP",
            value = 7.0,
            min = 1.0,
            max = 15.0,
            step = 0.5
          ),

          # Quick DPPP Presets (outline by default, filled on click)
          div(
            style = "display: flex; gap: 4px; margin-top: -5px;",
            actionButton("preset_id", "ID (1.5)", class = "btn-sm dppp-preset-btn dppp-btn-id",
                         style = "flex: 1; padding: 6px 0; font-size: 11px;"),
            actionButton("preset_balanced", "Bal (4.0)", class = "btn-sm dppp-preset-btn dppp-btn-bal",
                         style = "flex: 1; padding: 6px 0; font-size: 11px;"),
            actionButton("preset_quant", "Quant (7.0)", class = "btn-sm dppp-preset-btn dppp-btn-quant",
                         style = "flex: 1; padding: 6px 0; font-size: 11px;")
          )
        ),
        column(4, class = "label-prominent",
          # Satisfaction Target
          sliderInput(
            inputId = "target_satisfaction",
            label = "Target Satisfaction (%)",
            min = 50,
            max = 95,
            value = 70,
            step = 5,
            post = "%"
          )
        ),
        column(4,
          div(
            style = "padding-top: 15px;",
            # DPPP Formula card (prominent, readable)
            tags$div(
              class = "panel-accent", style = "font-size: 14px; line-height: 1.8;",
              tags$strong("DPPP"), " = 1.7 \u00d7 FWHM / cycle_time",
              tags$br(),
              tags$span(class = "text-muted", "ID: 1.5 | Balanced: 4.0 | Quant: 7.0")
            ),
            # Window count preview (reactive, shown when data + instrument configured)
            uiOutput("dppp_window_count_preview")
          )
        )
      )
    )),

    # --- Section B: Strategy & Parameters ---
    fluidRow(
    box(
      title = "B. Strategy & Parameters",
      status = "info",
      solidHeader = TRUE,
      width = 12,

      fluidRow(
        # m/z Optimization Strategy
        column(6, class = "label-prominent",
          selectInput(
            inputId = "mz_strategy",
            label = "m/z Range Strategy",
            choices = c(
              "Greedy (MacCoss, Recommended)" = "greedy",
              "KDE (Density Peak)" = "kde",
              "Quantile (P5-P95)" = "quantile",
              "Coverage (Conservative)" = "coverage",
              "Outlier (Mean +/- 3 SD)" = "outlier"
            ),
            selected = "greedy"
          )
        ),

        # Window Mode Selection
        column(6, class = "label-prominent",
          selectInput(
            inputId = "window_mode",
            label = "Window Width Mode",
            choices = c(
              "Density (Dense=Narrow)" = "density",
              "Fixed (Equal Width)" = "fixed",
              "Staggered (Offset Bins)" = "staggered"
            ),
            selected = "density"
          )
        )
      ),

      # --- Strategy & Window Mode Preview Images ---
      fluidRow(
        column(6,
          uiOutput("strategy_preview_img")
        ),
        column(6,
          uiOutput("window_mode_preview_img")
        )
      ),

      # --- Window Mode descriptions (conditionalPanel per mode) ---
      conditionalPanel(
        condition = "input.window_mode == 'density'",
        div(class = "mode-description",
          tags$small(
            icon("chart-area"), " ",
            tags$strong("Density mode:"),
            " Adaptive window widths based on precursor density. ",
            "Windows are narrower in dense m/z regions, wider in sparse regions. ",
            "Best for maximizing precursor coverage per window."
          )
        )
      ),
      conditionalPanel(
        condition = "input.window_mode == 'fixed'",
        div(class = "mode-description",
          tags$small(
            icon("th"), " ",
            tags$strong("Fixed mode:"),
            " Equal-width windows across the entire m/z range. ",
            "Simple and predictable. Best when precursor density is relatively uniform."
          )
        )
      ),
      conditionalPanel(
        condition = "input.window_mode == 'staggered'",
        div(class = "mode-description",
          tags$small(
            icon("exchange-alt"), " ",
            tags$strong("Staggered mode (2-Cycle Interleaved):"),
            " Two acquisition cycles with 50% m/z offset. ",
            "Cycle 2 windows are shifted by half-width from Cycle 1. ",
            "After demultiplexing (Skyline, DIA-NN), effective isolation = half nominal width. ",
            "Window boundaries placed at mass defect forbidden zones for optimal quadrupole transmission."
          ),
          tags$div(
            class = "panel-accent", style = "margin-top: 8px;",
            icon("sync-alt"),
            tags$strong(" Thermo Loop Control N"),
            " = windows per RT bin per cycle. ",
            tags$strong("Set this value in Xcalibur method editor."),
            " Calculated automatically after optimization."
          )
        )
      ),

      # --- Strategy-specific parameters (inline conditionalPanels) ---

      # Greedy Strategy Parameters
      conditionalPanel(
        condition = "input.mz_strategy == 'greedy'",
        div(class = "strategy-section",
          tags$h4("Greedy Parameters (MacCoss Lab)", class = "section-title strategy-heading"),

          # Info box explaining the algorithm
          div(class = "algo-info",
            tags$small(
              tags$strong("How Greedy works:"), tags$br(),
              "1. Fixed m/z range = Windows x Min Width", tags$br(),
              "2. Slides along m/z axis to find optimal position", tags$br(),
              "3. Maximizes precursor count within fixed range"
            )
          ),

          checkboxInput(
            inputId = "greedy_auto_windows",
            label = "Auto Window Count (from DPPP)",
            value = TRUE
          ),
          # Show recommended windows when Auto is checked
          conditionalPanel(
            condition = "input.greedy_auto_windows",
            uiOutput("greedy_auto_windows_info")
          ),
          conditionalPanel(
            condition = "!input.greedy_auto_windows",
            sliderInput(
              inputId = "greedy_n_windows",
              label = "Windows per RT Bin",
              min = 10, max = 100, value = 40, step = 5
            )
          ),

          # m/z Range Preview (most important info)
          uiOutput("greedy_mz_range_display"),

          hr(style = "margin: 10px 0; border-color: var(--border-subtle);"),

          # Sliding Step - clarify it's for search precision
          tags$label("Search Precision", class = "control-label",
                     style = "font-size: 12px;"),
          sliderInput(
            inputId = "greedy_mz_step",
            label = NULL,
            min = 0.5, max = 10.0, value = 2.0, step = 0.5,
            post = " Da step"
          ),
          helpText("Smaller step = more precise search but slower. Does NOT affect m/z range width.",
                   style = "font-size: 10px; font-style: italic;"),

          hr(style = "margin: 10px 0; border-color: var(--border-subtle);"),

          # Post-Smoothing
          checkboxInput(
            inputId = "greedy_apply_smoothing",
            label = smoothing_label,
            value = TRUE
          ),
          helpText("Smooths m/z boundaries across RT bins to prevent abrupt jumps. Uses weighted Whittaker-Henderson smoother.",
                   style = "font-size: 10px;")
        )
      ),

      # Quantile Strategy Parameters
      conditionalPanel(
        condition = "input.mz_strategy == 'quantile'",
        div(class = "strategy-section",
          tags$h4("Quantile Parameters", class = "section-title strategy-heading"),
          sliderInput(
            inputId = "quantile_lower",
            label = "Lower Percentile",
            min = 0.01, max = 0.20, value = 0.05, step = 0.01
          ),
          sliderInput(
            inputId = "quantile_upper",
            label = "Upper Percentile",
            min = 0.80, max = 0.99, value = 0.95, step = 0.01
          ),
          checkboxInput(
            inputId = "quantile_apply_smoothing",
            label = smoothing_label,
            value = FALSE
          ),
          helpText("P5-P95 covers 90% of precursors. WH smoothing prevents abrupt m/z jumps.",
                   style = "font-size: 10px;")
        )
      ),

      # Coverage Strategy Parameters
      conditionalPanel(
        condition = "input.mz_strategy == 'coverage'",
        div(class = "strategy-section",
          tags$h4("Coverage Parameters", class = "section-title strategy-heading"),
          sliderInput(
            inputId = "target_coverage",
            label = "Target Coverage (%)",
            min = 70, max = 99, value = 90, step = 1, post = "%"
          ),
          helpText("Find minimum m/z range achieving this coverage",
                   style = "font-size: 10px;")
        )
      ),

      # Outlier Strategy Parameters
      conditionalPanel(
        condition = "input.mz_strategy == 'outlier'",
        div(class = "strategy-section",
          tags$h4("Outlier Parameters", class = "section-title strategy-heading"),
          sliderInput(
            inputId = "outlier_threshold",
            label = "Threshold (x SD)",
            min = 2.0, max = 4.0, value = 3.0, step = 0.5
          ),
          checkboxInput(
            inputId = "outlier_apply_smoothing",
            label = smoothing_label,
            value = FALSE
          ),
          helpText("Mean +/- NxSD range. WH smoothing prevents abrupt m/z jumps.",
                   style = "font-size: 10px;")
        )
      ),

      # KDE Strategy Parameters
      conditionalPanel(
        condition = "input.mz_strategy == 'kde'",
        div(class = "strategy-section",
          tags$h4("KDE Parameters (Density Peak)", class = "section-title strategy-heading"),
          sliderInput(
            inputId = "kde_density_threshold",
            label = "Density Threshold (%)",
            min = 5, max = 30, value = 10, step = 5
          ),
          helpText("Boundary at N% of peak density. Lower = wider range.",
                   style = "font-size: 10px;"),
          sliderInput(
            inputId = "kde_min_coverage",
            label = "Minimum Coverage (%)",
            min = 60, max = 95, value = 80, step = 5
          ),
          helpText("Expand range to ensure at least N% precursor coverage.",
                   style = "font-size: 10px;")
        )
      ),

      # Common parameter (all strategies)
      hr(),
      fluidRow(
        column(4,
          numericInput(
            inputId = "min_isolation_width",
            label = "Min Isolation Width (Da)",
            value = 2,
            min = 1,
            max = 10,
            step = 0.5
          ),
          helpText("Minimum window width (2 Da typical for narrow-DIA)",
                   style = "font-size: 11px;")
        ),
        column(4,
          numericInput(
            inputId = "max_isolation_width",
            label = "Max Isolation Width (Da)",
            value = 80,
            min = 10,
            max = 500,
            step = 5
          ),
          helpText("Maximum window width (80 Da default; limits wide windows in sparse m/z regions)",
                   style = "font-size: 11px;")
        ),
        column(4,
          # Duty cycle sync info (parallel instruments only)
          uiOutput("duty_cycle_sync_info")
        )
      ),

      # --- Window Placement Optimization (all modes, at end of strategy section) ---
      hr(),
      div(class = "panel-raised", style = "margin-bottom: 12px; border-left: 3px solid var(--text-primary);",
        fluidRow(
          column(6,
            selectInput(
              inputId = "fz_offset_preset",
              label = "Forbidden Zone Placement (Recommended)",
              choices = c(
                "Standard Proteomics (0.25) - Recommended" = "0.25",
                "Phosphoproteomics (0.18)" = "0.18",
                "Custom" = "custom",
                "None (Disabled)" = "0"
              ),
              selected = "0.25"
            )
          ),
          column(6,
            div(style = "padding-top: 25px;",
              helpText(
                "Snaps window boundaries to mass defect forbidden zones where ",
                "peptide precursors cannot exist. Prevents quadrupole edge ",
                "transmission loss and isotope envelope splitting. ",
                "Enabled by default for optimal transmission efficiency.",
                style = "font-size: 10px; line-height: 1.4;"
              )
            )
          )
        ),
        conditionalPanel(
          condition = "input.fz_offset_preset == 'custom'",
          fluidRow(
            column(4,
              numericInput(
                inputId = "custom_fz_offset",
                label = "Custom Forbidden Zone Offset",
                value = 0.2500,
                min = 0.0001,
                max = 0.9999,
                step = 0.0001
              )
            )
          )
        )
      )
    )),

    # --- Section C: RT Binning (collapsed) ---
    fluidRow(
    box(
      title = "C. RT Binning",
      status = "warning",
      solidHeader = FALSE,
      width = 12,
      collapsible = TRUE,
      collapsed = FALSE,

      selectInput(
        inputId = "rt_binning_mode",
        label = "RT Binning Mode",
        choices = c(
          "Fixed (auto width)" = "fixed",
          "Adaptive (KS change-point)" = "adaptive",
          "Custom (manual width)" = "custom"
        ),
        selected = "fixed"
      ),
      helpText("Fixed: auto-calculated bin width. Adaptive: KS-test detects m/z distribution shifts.",
               style = "font-size: 11px;"),

      # Manual bin width slider (Custom mode only)
      conditionalPanel(
        condition = "input.rt_binning_mode == 'custom'",
        sliderInput(
          inputId = "rt_bin_width",
          label = "RT Bin Width (min)",
          min = 1,
          max = 15,
          value = 5,
          step = 0.5,
          post = " min"
        ),
        helpText("Controls RT segment grouping. Smaller = more segments.",
                 style = "font-size: 11px;")
      ),

      # Adaptive KS parameters (Adaptive mode only)
      conditionalPanel(
        condition = "input.rt_binning_mode == 'adaptive'",
        div(class = "strategy-section",
          tags$h4("Adaptive Parameters", class = "section-title strategy-heading"),
          sliderInput(
            inputId = "cpd_significance",
            label = "Change Point Significance",
            min = 0.001, max = 0.10, value = 0.05, step = 0.005
          ),
          sliderInput(
            inputId = "cpd_min_bin_width",
            label = "Min Bin Width (min)",
            min = 0.5, max = 5.0, value = 1.0, step = 0.5
          ),
          helpText("Lower significance = fewer, more confident change points.",
                   style = "font-size: 10px;")
        )
      ),

      # Default mode note
      conditionalPanel(
        condition = "input.rt_binning_mode == 'fixed'",
        helpText("Fixed mode uses auto-calculated bin width. No additional parameters needed.",
                 style = "font-size: 11px;")
      )
    )),

    # --- Section D: Expert Settings (collapsed + warning) ---
    fluidRow(
    box(
      title = "D. Expert Settings",
      status = "secondary",
      solidHeader = FALSE,
      width = 12,
      collapsible = TRUE,
      collapsed = TRUE,

      # Expert warning banner
      div(class = "tab-banner-warning",
        tags$small(
          icon("exclamation-triangle"), " ",
          "Expert settings. Modify only if you understand instrument scan timing."
        )
      ),

      fluidRow(
        # Column 1: Acquisition
        column(4,
          tags$h4("Acquisition", class = "section-title"),

          # MS1 Scans per Cycle
          numericInput(
            inputId = "ms1_scans_per_cycle",
            label = "MS1 Scans/Cycle",
            value = 1,
            min = 0,
            max = 10,
            step = 1
          ),
          helpText("1 for standard DIA, 0 for parallel (Astral), 3-4 for Boxcar",
                   style = "font-size: 11px;")
        ),

        # Column 2: Edge Handling
        column(4,
          tags$h4("Edge Handling", class = "section-title"),

          numericInput(
            inputId = "edge_void_buffer",
            label = "Void Volume Buffer (min)",
            value = 0.5, min = 0, max = 2, step = 0.1
          ),
          numericInput(
            inputId = "edge_wash_threshold",
            label = "Wash Merge Threshold (precursors)",
            value = 30, min = 0, max = 200, step = 10
          ),
          helpText("Void buffer extends first bin start (typical: 0.3-1.0 min depending on column length/ID). Wash merge combines sparse last bin.",
                   style = "font-size: 10px;")
        )
      )
    )),

    # Navigation
    div(
      class = "wizard-nav wizard-nav-between",
      actionButton("btn_to_data", "Back to Data & Instrument",
                   class = "btn-default btn-lg",
                   icon = icon("arrow-left")),
      actionButton("run_optimization", "Run Optimization",
                   class = "btn-success btn-lg",
                   icon = icon("play"),
                   style = "font-weight: 600;")
    )
  )
}
