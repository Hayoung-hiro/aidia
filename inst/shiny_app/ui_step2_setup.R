# ui_step2_setup.R - Step 2: SETUP (Instrument, Strategy, Parameters)

step2_setup_ui <- function() {
  tabItem(
    tabName = "setup",

    # --- Section A: Instrument & Timing ---
    box(
      title = "A. Instrument & Timing",
      status = "primary",
      solidHeader = TRUE,
      width = 12,

      fluidRow(
        # Column 1: Instrument Selection
        column(4,
          selectInput(
            inputId = "instrument",
            label = "Instrument Preset",
            choices = c(
              # Thermo Orbitrap (verified)
              "Thermo Astral Zoom (270 Hz)" = "astral_zoom",
              "Thermo Astral (200 Hz)" = "astral",
              "Thermo Q Exactive (12 Hz)" = "qexactive",
              "Thermo Q Exactive HF-X (40 Hz)" = "qexactive_hfx",
              "Thermo Exploris 480 (40 Hz)" = "exploris",
              "Thermo Eclipse Tribrid (40 Hz)" = "eclipse",
              "Thermo Fusion Lumos (20 Hz)" = "fusion_lumos"
              # TODO: Add Bruker TimsTOF, SCIEX, Waters when verified
            ),
            selected = "astral_zoom"
          )
        ),

        # Column 2: Window Count
        column(4,
          numericInput(
            inputId = "current_window_count",
            label = "MS2 Window Count",
            value = 40,
            min = 10,
            max = 500,
            step = 5
          ),
          helpText("Number of MS2/DIA isolation windows per cycle",
                   style = "font-size: 11px; color: #7f8c8d;")
        ),

        # Column 3: Instrument-specific settings
        column(4,
          # MS1 Resolution (Orbitrap only)
          conditionalPanel(
            condition = "input.instrument == 'qexactive' || input.instrument == 'qexactive_hfx' || input.instrument == 'exploris' || input.instrument == 'eclipse' || input.instrument == 'fusion_lumos'",
            selectInput(
              inputId = "ms1_resolution",
              label = "MS1 Resolution",
              choices = c(
                "15,000" = 15000,
                "30,000" = 30000,
                "60,000" = 60000,
                "120,000" = 120000,
                "240,000" = 240000,
                "480,000" = 480000
              ),
              selected = 60000
            ),

            # MS2 Resolution (Orbitrap only)
            selectInput(
              inputId = "ms2_resolution",
              label = "MS2 Resolution",
              choices = c(
                "7,500" = 7500,
                "15,000" = 15000,
                "30,000" = 30000,
                "45,000" = 45000,
                "60,000" = 60000,
                "120,000" = 120000,
                "240,000" = 240000
              ),
              selected = 15000
            )
          ),

          # Astral MS2 IT slider (for Astral instruments)
          conditionalPanel(
            condition = "input.instrument == 'astral' || input.instrument == 'astral_zoom' || input.instrument == 'astral_sensitive'",
            sliderInput(
              inputId = "astral_ms2_it",
              label = "Astral MS2 IT (ms)",
              min = 2,
              max = 40,
              value = 3,
              step = 0.5,
              post = " ms"
            ),
            helpText("3ms: 200 Hz max speed | >3ms: Sensitivity mode",
                     style = "font-size: 10px; color: #7f8c8d;")
          )
        )
      )
    ),

    # --- Section B: DPPP Target ---
    box(
      title = "B. DPPP Target",
      status = "warning",
      solidHeader = TRUE,
      width = 12,

      fluidRow(
        column(4,
          numericInput(
            inputId = "target_dppp",
            label = "Target DPPP",
            value = 7.0,
            min = 1.0,
            max = 15.0,
            step = 0.5
          ),

          # Quick DPPP Presets
          div(
            style = "display: flex; gap: 4px; margin-top: -5px;",
            actionButton("preset_id", "ID", class = "btn-sm btn-info",
                         style = "flex: 1; padding: 6px 0; font-size: 11px; font-weight: 600;"),
            actionButton("preset_balanced", "Bal", class = "btn-sm btn-warning",
                         style = "flex: 1; padding: 6px 0; font-size: 11px; font-weight: 600;"),
            actionButton("preset_quant", "Quant", class = "btn-sm btn-success",
                         style = "flex: 1; padding: 6px 0; font-size: 11px; font-weight: 600;")
          )
        ),
        column(4,
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
            style = "padding-top: 25px;",
            helpText(
              tags$strong("DPPP"), " = 1.7 x FWHM / cycle_time",
              tags$br(),
              "ID: 1.5 | Balanced: 4.0 | Quant: 7.0",
              style = "font-size: 12px; color: #7f8c8d; line-height: 1.6;"
            )
          )
        )
      )
    ),

    # --- Section C: Strategy & Parameters ---
    box(
      title = "C. Strategy & Parameters",
      status = "info",
      solidHeader = TRUE,
      width = 12,

      fluidRow(
        # m/z Optimization Strategy
        column(6,
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
        column(6,
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

      # --- Window Mode descriptions (conditionalPanel per mode) ---
      conditionalPanel(
        condition = "input.window_mode == 'density'",
        div(style = "background: rgba(26, 188, 156, 0.08); padding: 10px 14px; border-radius: 6px; margin-bottom: 12px; border-left: 3px solid #1abc9c;",
          tags$small(
            icon("chart-area"), " ",
            tags$strong("Density mode:"),
            " Adaptive window widths based on precursor density. ",
            "Windows are narrower in dense m/z regions, wider in sparse regions. ",
            "Best for maximizing precursor coverage per window.",
            style = "color: #2c3e50; line-height: 1.5;"
          )
        )
      ),
      conditionalPanel(
        condition = "input.window_mode == 'fixed'",
        div(style = "background: rgba(52, 152, 219, 0.08); padding: 10px 14px; border-radius: 6px; margin-bottom: 12px; border-left: 3px solid #3498db;",
          tags$small(
            icon("th"), " ",
            tags$strong("Fixed mode:"),
            " Equal-width windows across the entire m/z range. ",
            "Simple and predictable. Best when precursor density is relatively uniform.",
            style = "color: #2c3e50; line-height: 1.5;"
          )
        )
      ),
      conditionalPanel(
        condition = "input.window_mode == 'staggered'",
        div(style = "background: rgba(155, 89, 182, 0.08); padding: 10px 14px; border-radius: 6px; margin-bottom: 12px; border-left: 3px solid #9b59b6;",
          tags$small(
            icon("exchange-alt"), " ",
            tags$strong("Staggered mode:"),
            " Fixed-width windows with alternating offset between odd/even RT bins. ",
            "Even bins are shifted by a fraction of the window width, reducing boundary effects ",
            "where precursors near window edges in one bin are fully covered in adjacent bins.",
            style = "color: #2c3e50; line-height: 1.5;"
          ),
          div(style = "margin-top: 8px;",
            sliderInput(
              inputId = "stagger_offset_pct",
              label = "Stagger Offset (%)",
              min = 10, max = 90, value = 50, step = 10,
              post = "%"
            ),
            helpText("50% = half-window shift (recommended). Lower = less overlap between bins.",
                     style = "font-size: 10px; color: #7f8c8d;")
          )
        )
      ),

      # --- Strategy-specific parameters (inline conditionalPanels) ---

      # Greedy Strategy Parameters
      conditionalPanel(
        condition = "input.mz_strategy == 'greedy'",
        div(style = "background: rgba(241, 196, 15, 0.1); padding: 10px; margin: 5px 0; border-radius: 5px;",
          h5("Greedy Parameters (MacCoss Lab)", style = "margin: 0 0 8px 0; color: #f39c12;"),

          # Info box explaining the algorithm
          div(style = "background: rgba(255,255,255,0.5); padding: 8px; border-radius: 4px; margin-bottom: 10px; border-left: 3px solid #f39c12;",
            tags$small(
              tags$strong("How Greedy works:"), tags$br(),
              "1. Fixed m/z range = Windows x Min Width", tags$br(),
              "2. Slides along m/z axis to find optimal position", tags$br(),
              "3. Maximizes precursor count within fixed range",
              style = "color: #7f8c8d; line-height: 1.4;"
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

          hr(style = "margin: 10px 0; border-color: rgba(243, 156, 18, 0.3);"),

          # Sliding Step - clarify it's for search precision
          tags$label("Search Precision", class = "control-label",
                     style = "font-size: 12px; color: #7f8c8d;"),
          sliderInput(
            inputId = "greedy_mz_step",
            label = NULL,
            min = 0.5, max = 10.0, value = 2.0, step = 0.5,
            post = " Da step"
          ),
          helpText("Smaller step = more precise search but slower. Does NOT affect m/z range width.",
                   style = "font-size: 10px; color: #95a5a6; font-style: italic;"),

          hr(style = "margin: 10px 0; border-color: rgba(243, 156, 18, 0.3);"),

          # Post-Smoothing (following dynamicDIA.py)
          checkboxInput(
            inputId = "greedy_apply_smoothing",
            label = "Apply Savitzky-Golay Smoothing",
            value = TRUE
          ),
          helpText("Smooths m/z boundaries across RT bins to prevent abrupt jumps (dynamicDIA method).",
                   style = "font-size: 10px; color: #7f8c8d;")
        )
      ),

      # Quantile Strategy Parameters
      conditionalPanel(
        condition = "input.mz_strategy == 'quantile'",
        div(style = "background: rgba(52, 152, 219, 0.1); padding: 10px; margin: 5px 0; border-radius: 5px;",
          h5("Quantile Parameters", style = "margin: 0 0 8px 0; color: #3498db;"),
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
            label = "Apply SG Smoothing (smooth m/z boundaries across RT)",
            value = FALSE
          ),
          helpText("P5-P95 covers 90% of precursors. SG smoothing prevents abrupt m/z jumps.",
                   style = "font-size: 10px; color: #7f8c8d;")
        )
      ),

      # Coverage Strategy Parameters
      conditionalPanel(
        condition = "input.mz_strategy == 'coverage'",
        div(style = "background: rgba(46, 204, 113, 0.1); padding: 10px; margin: 5px 0; border-radius: 5px;",
          h5("Coverage Parameters", style = "margin: 0 0 8px 0; color: #27ae60;"),
          sliderInput(
            inputId = "target_coverage",
            label = "Target Coverage (%)",
            min = 70, max = 99, value = 90, step = 1, post = "%"
          ),
          helpText("Find minimum m/z range achieving this coverage",
                   style = "font-size: 10px; color: #7f8c8d;")
        )
      ),

      # Outlier Strategy Parameters
      conditionalPanel(
        condition = "input.mz_strategy == 'outlier'",
        div(style = "background: rgba(155, 89, 182, 0.1); padding: 10px; margin: 5px 0; border-radius: 5px;",
          h5("Outlier Parameters", style = "margin: 0 0 8px 0; color: #9b59b6;"),
          sliderInput(
            inputId = "outlier_threshold",
            label = "Threshold (x SD)",
            min = 2.0, max = 4.0, value = 3.0, step = 0.5
          ),
          checkboxInput(
            inputId = "outlier_apply_smoothing",
            label = "Apply SG Smoothing (smooth m/z boundaries across RT)",
            value = FALSE
          ),
          helpText("Mean +/- NxSD range. SG smoothing prevents abrupt m/z jumps.",
                   style = "font-size: 10px; color: #7f8c8d;")
        )
      ),

      # KDE Strategy Parameters
      conditionalPanel(
        condition = "input.mz_strategy == 'kde'",
        div(style = "background: rgba(231, 76, 60, 0.1); padding: 10px; margin: 5px 0; border-radius: 5px;",
          h5("KDE Parameters (Density Peak)", style = "margin: 0 0 8px 0; color: #e74c3c;"),
          sliderInput(
            inputId = "kde_density_threshold",
            label = "Density Threshold (%)",
            min = 5, max = 30, value = 10, step = 5
          ),
          helpText("Boundary at N% of peak density. Lower = wider range.",
                   style = "font-size: 10px; color: #7f8c8d;"),
          sliderInput(
            inputId = "kde_min_coverage",
            label = "Minimum Coverage (%)",
            min = 60, max = 95, value = 80, step = 5
          ),
          helpText("Expand range to ensure at least N% precursor coverage.",
                   style = "font-size: 10px; color: #7f8c8d;")
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
                   style = "font-size: 11px; color: #7f8c8d;")
        )
      )
    ),

    # --- Section D: RT Binning (collapsed accordion) ---
    box(
      title = "D. RT Binning",
      status = "info",
      solidHeader = FALSE,
      width = 12,
      collapsible = TRUE,
      collapsed = TRUE,

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
               style = "font-size: 11px; color: #7f8c8d;"),

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
                 style = "font-size: 11px; color: #7f8c8d;")
      ),

      # Adaptive KS parameters (Adaptive mode only)
      conditionalPanel(
        condition = "input.rt_binning_mode == 'adaptive'",
        div(style = "background: rgba(26, 188, 156, 0.1); padding: 10px; margin: 5px 0; border-radius: 5px;",
          h5("Adaptive Parameters", style = "margin: 0 0 8px 0; color: #1abc9c;"),
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
                   style = "font-size: 10px; color: #7f8c8d;")
        )
      ),

      # Default mode note
      conditionalPanel(
        condition = "input.rt_binning_mode == 'fixed'",
        helpText("Fixed mode uses auto-calculated bin width. No additional parameters needed.",
                 style = "font-size: 11px; color: #7f8c8d;")
      )
    ),

    # --- Section E: Expert Settings (collapsed accordion + warning) ---
    box(
      title = "E. Expert Settings",
      status = "warning",
      solidHeader = FALSE,
      width = 12,
      collapsible = TRUE,
      collapsed = TRUE,

      # Expert warning banner
      div(class = "tab-banner-warning",
        tags$small(
          icon("exclamation-triangle"), " ",
          "Expert settings. Modify only if you understand instrument scan timing.",
          style = "color: #856404;"
        )
      ),

      fluidRow(
        # Column 1: Injection Time
        column(4,
          h5("Injection Time", style = "color: #2c3e50; font-weight: 600;"),

          # MS1 Injection Time (Orbitrap only)
          conditionalPanel(
            condition = "input.instrument == 'qexactive' || input.instrument == 'qexactive_hfx' || input.instrument == 'exploris' || input.instrument == 'eclipse' || input.instrument == 'fusion_lumos'",
            div(
              style = "padding: 0;",
              tags$label("MS1 Max IT", class = "control-label"),
              div(
                style = "display: flex; gap: 8px; align-items: center;",
                checkboxInput("ms1_it_auto", "Auto", value = TRUE, width = "55px"),
                conditionalPanel(
                  condition = "!input.ms1_it_auto",
                  div(
                    style = "display: flex; align-items: center; gap: 4px;",
                    numericInput("ms1_it_custom", NULL, value = 50, min = 5, max = 500, step = 5, width = "90px"),
                    span("ms", style = "color: #34495e; font-size: 12px; font-weight: 500;")
                  )
                ),
                conditionalPanel(
                  condition = "input.ms1_it_auto",
                  span(textOutput("ms1_it_auto_value", inline = TRUE),
                       style = "color: #1abc9c; font-weight: 600; font-size: 12px;")
                )
              )
            )
          ),

          # MS2 Injection Time (Orbitrap only)
          conditionalPanel(
            condition = "input.instrument == 'qexactive' || input.instrument == 'qexactive_hfx' || input.instrument == 'exploris' || input.instrument == 'eclipse' || input.instrument == 'fusion_lumos'",
            div(
              style = "padding: 0;",
              tags$label("MS2 Max IT", class = "control-label"),
              div(
                style = "display: flex; gap: 8px; align-items: center;",
                checkboxInput("ms2_it_auto", "Auto", value = TRUE, width = "55px"),
                conditionalPanel(
                  condition = "!input.ms2_it_auto",
                  div(
                    style = "display: flex; align-items: center; gap: 4px;",
                    numericInput("ms2_it_custom", NULL, value = 50, min = 5, max = 500, step = 5, width = "90px"),
                    span("ms", style = "color: #34495e; font-size: 12px; font-weight: 500;")
                  )
                ),
                conditionalPanel(
                  condition = "input.ms2_it_auto",
                  span(textOutput("ms2_it_auto_value", inline = TRUE),
                       style = "color: #1abc9c; font-weight: 600; font-size: 12px;")
                )
              )
            ),
            helpText("Auto = T_transient (Sweet Spot, 100% efficiency)",
                     style = "font-size: 10px; color: #7f8c8d; margin-top: 4px;")
          ),

          # Astral IT note
          conditionalPanel(
            condition = "input.instrument == 'astral' || input.instrument == 'astral_zoom' || input.instrument == 'astral_sensitive'",
            helpText("Astral MS2 IT is configured in Instrument & Timing above.",
                     style = "font-size: 11px; color: #7f8c8d;")
          )
        ),

        # Column 2: Acquisition
        column(4,
          h5("Acquisition", style = "color: #2c3e50; font-weight: 600;"),

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
                   style = "font-size: 11px; color: #7f8c8d;")
        ),

        # Column 3: Edge Handling
        column(4,
          h5("Edge Handling", style = "color: #2c3e50; font-weight: 600;"),

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
          helpText("Void buffer extends first bin start. Wash merge combines sparse last bin.",
                   style = "font-size: 10px; color: #7f8c8d;")
        )
      )
    ),

    # Navigation
    div(
      class = "wizard-nav wizard-nav-between",
      actionButton("btn_to_data", "Back to Data",
                   class = "btn-default btn-lg",
                   icon = icon("arrow-left")),
      actionButton("run_optimization", "Run Optimization",
                   class = "btn-success btn-lg",
                   icon = icon("play"),
                   style = "font-weight: 600;")
    )
  )
}
