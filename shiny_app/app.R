# =============================================================================
# AIDIA - Adaptive Isolation for DIA (Shiny Web Application)
# =============================================================================
# Version: 1.0.0
# Purpose: Web-based interface for DIA isolation window optimization
# "Your Adaptive Aid for DIA Optimization"
# =============================================================================

# --- Dependencies ---
library(shiny)
library(bs4Dash)
library(shinybusy)      # Progress indicators
library(shinyjs)        # Progressive disclosure (toggle/hide)
library(DT)             # Interactive tables

# --- Configuration ---
# Increase file upload limit to 500MB (default is 5MB)
# DIA-NN parquet files can be 50-500MB depending on experiment size
options(shiny.maxRequestSize = 500 * 1024^2)

# --- Load aidia package ---
# Option 1: Use installed package (production)
# library(aidia)

# Option 2: Use devtools::load_all() for development
# This loads the package from source without installing
if (!requireNamespace("aidia", quietly = TRUE)) {
  # Package not installed, use load_all for development
  devtools::load_all("..")
} else {
  library(aidia)
}

# --- Ensure all required modules are loaded ---
# When running from shiny_app/, the relative paths in package files don't work
# Source all required modules explicitly to ensure availability

# Helper to source from parent directory
source_from_parent <- function(rel_path) {
  full_path <- file.path("..", rel_path)
  if (file.exists(full_path)) {
    source(full_path)
    return(TRUE)
  }
  return(FALSE)
}

# Load instrument_utils for cycle time calculation
source_from_parent("R/instrument_utils.R")

# Source utils_common.R first (contains count_precursors_in_windows)
if (source_from_parent("R/utils_common.R")) {
  cat("[Shiny] Loaded utils_common.R\n")
}

# Source all Stage 3 modules
stage3_modules <- c(
  "R/stage3/stage3_rt_binning.R",
  "R/stage3/stage3_mz_optimization.R",
  "R/stage3/stage3_window_generation.R",
  "R/stage3/stage3_statistics.R",
  "R/stage3/stage3_export.R"
)

for (module in stage3_modules) {
  if (source_from_parent(module)) {
    cat("[Shiny] Loaded", basename(module), "\n")
  }
}

# Source Stage 4 modules (for structured PDF report generation)
if (source_from_parent("R/stage4_visualization.R")) {
  cat("[Shiny] Loaded stage4_visualization.R\n")
}
if (source_from_parent("R/stage4_export.R")) {
  cat("[Shiny] Loaded stage4_export.R\n")
}

## Instrument type detection: is_orbitrap_instrument(), is_astral_instrument()
## are provided by R/instrument_utils.R (sourced above)

# =============================================================================
# UI Definition
# =============================================================================

ui <- dashboardPage(

  # --- Header ---
  header = dashboardHeader(
    title = "AIDIA"
  ),

  # --- Sidebar (MINIMAL) ---
  sidebar = dashboardSidebar(
    width = 250,

    # File Upload Section
    h4("Data Input", style = "padding-left: 15px; color: #ecf0f1;"),
    fileInput(
      inputId = "parquet_file",
      label = "Upload Parquet File",
      accept = c(".parquet"),
      placeholder = "DIA-NN report..."
    ),

    hr(),

    # Run Button — primary CTA immediately after file upload
    actionButton(
      inputId = "run_optimization",
      label = "Run Optimization",
      class = "btn-primary btn-lg",
      style = "width: 90%; margin-left: 5%;"
    ),

    hr(),

    # Calculated Cycle Time Display (reactive feedback)
    div(
      id = "cycle_time_display",
      style = "background: linear-gradient(135deg, #1a252f 0%, #2c3e50 100%); border-radius: 8px; padding: 12px; margin: 10px 15px; border-left: 4px solid #1abc9c;",
      h5("Calculated Cycle Time", style = "margin: 0 0 8px 0; color: #ecf0f1; font-size: 13px;"),
      div(
        style = "display: flex; justify-content: space-between; align-items: baseline;",
        span(textOutput("calculated_cycle_time", inline = TRUE),
             style = "font-size: 24px; font-weight: 700; color: #1abc9c;"),
        span("sec", style = "font-size: 14px; color: #95a5a6; margin-left: 4px;")
      ),
      div(
        style = "margin-top: 8px; font-size: 11px; color: #7f8c8d;",
        textOutput("cycle_time_breakdown", inline = TRUE)
      ),
      div(
        style = "margin-top: 4px;",
        uiOutput("efficiency_badge")
      )
    ),

    hr(),

    # Optional naming fields — collapsed by default
    tags$details(
      tags$summary("Sample Naming (optional)", style = "color: #bdc3c7; font-size: 12px; cursor: pointer;"),
      textInput(
        inputId = "sample_name",
        label = "Sample/Project Name",
        value = "",
        placeholder = "e.g., HeLa_digest"
      ),
      textInput(
        inputId = "condition",
        label = "Condition/Note",
        value = "",
        placeholder = "e.g., 60min_gradient"
      ),
      helpText("Used in output file names. Leave blank to use defaults.",
               style = "font-size: 10px; color: #7f8c8d; padding: 0 15px;")
    )
  ),

  # --- Main Body ---
  body = dashboardBody(

    # shinyjs for progressive disclosure (toggle/hide)
    useShinyjs(),

    # Custom CSS - External stylesheet for professional styling
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),
      # Google Fonts for better typography
      tags$link(
        rel = "stylesheet",
        href = "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap"
      ),
      tags$style(HTML("
        body { font-family: 'Inter', 'Segoe UI', sans-serif; }

        /* Equal height row for boxes */
        .equal-height-row {
          display: flex;
          flex-wrap: wrap;
        }
        .equal-height-row > [class*='col-'] {
          display: flex;
          margin-bottom: 15px;
        }
        .equal-height-row > [class*='col-'] > .box {
          width: 100%;
          display: flex;
          flex-direction: column;
        }
        .equal-height-row > [class*='col-'] > .box > .box-body {
          flex: 1;
        }

        /* DPPP Preview section styling */
        .dppp-preview-section h5 {
          margin-bottom: 10px;
          color: #2c3e50;
          font-weight: 600;
        }

        /* Info box consistency */
        .info-box {
          min-height: 90px;
        }

        /* Sidebar numeric input styling - improved visibility */
        .main-sidebar .form-control {
          background-color: #1a252f !important;
          color: #ecf0f1 !important;
          border: 1px solid #3d566e !important;
          font-weight: 500;
        }
        .main-sidebar .form-control:focus {
          border-color: #1abc9c !important;
          box-shadow: 0 0 0 2px rgba(26, 188, 156, 0.25) !important;
        }
        .main-sidebar input[type='number'] {
          text-align: center;
          font-size: 14px !important;
          padding: 4px 8px;
        }

        /* Checkbox styling in sidebar */
        .main-sidebar .checkbox label {
          color: #ecf0f1;
          font-weight: 500;
        }
      "))
    ),

    # Progress Indicator with accent color
    shinybusy::add_busy_spinner(
      spin = "fading-circle",
      color = "#1abc9c",
      position = "full-page"
    ),

    # Row 1: Status Cards
    fluidRow(
      # Data Status
      bs4InfoBoxOutput("data_status", width = 4),
      # Optimization Status
      bs4InfoBoxOutput("optimization_status", width = 4),
      # Download Status
      bs4InfoBoxOutput("download_status", width = 4)
    ),

    # Row 2: Settings (3-tab pattern)
    fluidRow(
      box(
        title = "Settings",
        status = "primary",
        solidHeader = TRUE,
        width = 12,
        collapsible = TRUE,

        tabsetPanel(
          # ============================================================
          # Tab 1: Setup (Essential parameters)
          # ============================================================
          tabPanel(
            title = tagList(icon("sliders-h"), "Setup"),

            br(),
            fluidRow(
              # Column 1: Instrument
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
                ),

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
                  )
                ),

                # MS2 Resolution (Orbitrap only)
                conditionalPanel(
                  condition = "input.instrument == 'qexactive' || input.instrument == 'qexactive_hfx' || input.instrument == 'exploris' || input.instrument == 'eclipse' || input.instrument == 'fusion_lumos'",
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
                ),

                # MS2 Window Count
                numericInput(
                  inputId = "current_window_count",
                  label = "MS2 Window Count",
                  value = 40,
                  min = 10,
                  max = 500,
                  step = 5
                ),
                helpText("Number of MS2/DIA isolation windows per cycle",
                         style = "font-size: 11px; color: #bdc3c7;")
              ),

              # Column 2: DPPP Target
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
                ),

                br(),

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

              # Column 3: Strategy & Mode
              column(4,
                # m/z Optimization Strategy
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
                ),
                helpText("Greedy: MacCoss method (recommended). KDE: Density-informed.",
                         style = "font-size: 11px; color: #bdc3c7;"),

                # Window Mode Selection
                selectInput(
                  inputId = "window_mode",
                  label = "Window Width Mode",
                  choices = c(
                    "Density (Dense=Narrow)" = "density",
                    "Fixed (Equal Width)" = "fixed",
                    "Staggered (Offset Bins)" = "staggered"
                  ),
                  selected = "density"
                ),
                helpText("Density: narrow where dense. Fixed: equal width. Staggered: offset bins.",
                         style = "font-size: 11px; color: #bdc3c7;"),

                # Toggle link for rarely-changed options
                actionLink("toggle_setup_more", "More Options...",
                           style = "font-size: 12px; color: #1abc9c; margin-top: 8px; display: block;"),

                # Hidden by default — min isolation width + RT binning mode
                shinyjs::hidden(
                  div(id = "setup_more_options",
                    hr(style = "margin: 8px 0; border-color: rgba(26,188,156,0.3);"),
                    # Minimum Isolation Width
                    numericInput(
                      inputId = "min_isolation_width",
                      label = "Min Isolation Width (Da)",
                      value = 2,
                      min = 1,
                      max = 10,
                      step = 0.5
                    ),
                    helpText("Minimum window width (2 Da typical for narrow-DIA)",
                             style = "font-size: 11px; color: #bdc3c7;"),

                    # RT Binning Mode
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
                             style = "font-size: 11px; color: #bdc3c7;")
                  )
                )
              )
            )
          ),

          # ============================================================
          # Tab 2: Tuning (Strategy fine-tuning)
          # ============================================================
          tabPanel(
            title = tagList(icon("cog"), "Tuning"),

            br(),
            # Info banner — defaults work for most experiments
            div(class = "tab-banner-info",
              tags$small(
                icon("info-circle"), " ",
                "Fine-tune strategy parameters. Defaults work well for most experiments.",
                style = "color: #2c3e50;"
              )
            ),
            fluidRow(
              # Column 1: Strategy Parameters
              column(6,
                h5("Strategy Parameters", style = "color: #2c3e50; font-weight: 600;"),

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
                )
              ),

              # Column 2: RT Binning Parameters — collapsed by default
              column(6,
                box(
                  title = "RT Binning Parameters",
                  status = "info",
                  solidHeader = FALSE,
                  collapsible = TRUE,
                  collapsed = TRUE,
                  width = 12,

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
                             style = "font-size: 11px; color: #bdc3c7;")
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
                )
              )
            )
          ),

          # ============================================================
          # Tab 3: Expert (Instrument scan timing)
          # ============================================================
          tabPanel(
            title = tagList(icon("flask"), "Expert"),

            br(),
            # Expert warning banner
            div(class = "tab-banner-warning",
              tags$small(
                icon("exclamation-triangle"), " ",
                "Expert settings. Modify only if you understand instrument scan timing.",
                style = "color: #856404;"
              )
            ),
            fluidRow(
              # Column 1: Injection Time — collapsed
              column(4,
                box(
                  title = "Injection Time",
                  status = "warning",
                  solidHeader = FALSE,
                  collapsible = TRUE,
                  collapsed = TRUE,
                  width = 12,

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
                    helpText("Astral MS2 IT is configured in the Setup tab.",
                             style = "font-size: 11px; color: #7f8c8d;")
                  )
                )
              ),

              # Column 2: Acquisition — collapsed
              column(4,
                box(
                  title = "Acquisition",
                  status = "warning",
                  solidHeader = FALSE,
                  collapsible = TRUE,
                  collapsed = TRUE,
                  width = 12,

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
                           style = "font-size: 11px; color: #bdc3c7;")
                )
              ),

              # Column 3: Edge Handling — collapsed
              column(4,
                box(
                  title = "Edge Handling",
                  status = "warning",
                  solidHeader = FALSE,
                  collapsible = TRUE,
                  collapsed = TRUE,
                  width = 12,

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
            )
          )
        )
      )
    ),

    # Row 3: Data Summary + Cycle Time Detail
    fluidRow(
      class = "equal-height-row",
      # Left: Data Summary
      box(
        title = "Data Summary",
        status = "primary",
        solidHeader = TRUE,
        width = 6,
        height = "100%",

        # Conditional display
        conditionalPanel(
          condition = "output.data_loaded",
          tableOutput("data_summary"),
          br(),
          # Add some padding for alignment
          div(style = "min-height: 120px;")
        ),
        conditionalPanel(
          condition = "!output.data_loaded",
          p("Upload a parquet file to begin.", style = "color: #999;"),
          div(style = "min-height: 200px;")
        )
      ),

      # Right: Cycle Time Calculation Details
      box(
        title = "Cycle Time Calculation",
        status = "info",
        solidHeader = TRUE,
        width = 6,
        height = "100%",

        # Cycle Time Breakdown
        h5("Based on Your Experiment Settings", style = "margin-top: 0; color: #2c3e50;"),
        tableOutput("cycle_time_detail_table"),
        hr(style = "margin: 10px 0;"),

        # Visual Comparison
        h5("Cycle Time Breakdown"),
        uiOutput("cycle_time_visual"),
        hr(style = "margin: 10px 0;"),

        # Efficiency Info
        uiOutput("efficiency_detail")
      )
    ),

    # Row 4: DPPP Quick Preview
    fluidRow(
      box(
        title = "DPPP Quick Preview",
        status = "warning",
        solidHeader = TRUE,
        width = 12,
        collapsible = TRUE,

        conditionalPanel(
          condition = "output.data_loaded",
          fluidRow(
            class = "equal-height-row dppp-preview-section",
            column(4,
              # FWHM Summary
              h5("Peak Width (FWHM)", style = "margin-top: 0;"),
              tableOutput("fwhm_summary"),
              div(style = "min-height: 30px;")
            ),
            column(4,
              # DPPP at Different Cycle Times (Reactive to Target DPPP & Satisfaction)
              h5("DPPP at Different Cycle Times"),
              helpText(
                sprintf("Target: DPPP >= "),
                textOutput("current_target_dppp", inline = TRUE),
                style = "font-size: 11px; color: #7f8c8d; margin-bottom: 8px;"
              ),
              tableOutput("dppp_preview_table")
            ),
            column(4,
              # Recommendation
              h5("Recommendation"),
              uiOutput("dppp_recommendation")
            )
          )
        ),
        conditionalPanel(
          condition = "!output.data_loaded",
          p("Upload data to see DPPP preview.", style = "color: #999;")
        )
      )
    ),

    # Row 5: Optimization Results
    fluidRow(
      box(
        title = "Optimization Results",
        status = "success",
        solidHeader = TRUE,
        width = 12,

        conditionalPanel(
          condition = "output.optimization_complete",
          fluidRow(
            column(4, tableOutput("optimization_summary")),
            column(4,
              h5("m/z Range Summary", style = "margin-top: 0; color: #2c3e50; font-weight: 600;"),
              uiOutput("mz_range_summary")
            ),
            column(4,
              h5("Downloads", style = "margin-top: 0; color: #2c3e50; font-weight: 600;"),
              fluidRow(
                column(6, downloadButton("download_csv", "CSV Method",
                                         class = "btn-success btn-block")),
                column(6, downloadButton("download_pdf", "PDF Report",
                                         class = "btn-info btn-block"))
              )
            )
          )
        ),
        conditionalPanel(
          condition = "!output.optimization_complete",
          p("Run optimization to see results.", style = "color: #999;")
        )
      )
    ),

    # Row 6: Window Preview
    fluidRow(
      box(
        title = "Window Preview (First 20 rows)",
        status = "info",
        solidHeader = TRUE,
        width = 12,
        collapsible = TRUE,
        collapsed = TRUE,

        DT::dataTableOutput("window_preview")
      )
    )
  ),

  # --- Footer ---
  footer = dashboardFooter(
    left = "AIDIA v1.0.0",
    right = "Adaptive Isolation for DIA"
  ),

  dark = FALSE,
  title = "AIDIA - Adaptive Isolation for DIA"
)

# =============================================================================
# Server Logic
# =============================================================================

server <- function(input, output, session) {

  # --- Reactive Values ---
  rv <- reactiveValues(
    validated_data = NULL,
    optimization_plan = NULL,
    optimized_windows = NULL,
    dppp_preview = NULL,
    data_loaded = FALSE,
    optimization_complete = FALSE,
    cycle_time_calc = NULL  # Calculated cycle time result
  )

  # --- Reactive: Calculate Cycle Time from Experiment Parameters ---
  cycle_time_result <- reactive({
    # Explicitly depend on all inputs that affect cycle time calculation
    # This ensures reactivity when any of these inputs change
    instrument <- input$instrument
    ms1_scans_input <- input$ms1_scans_per_cycle  # Explicit dependency for reactivity
    window_count_input <- input$current_window_count  # Explicit dependency

    # Determine analyzer type
    is_orbitrap <- is_orbitrap_instrument(instrument)
    is_astral <- is_astral_instrument(instrument)

    # Build experiment config based on instrument type
    if (is_orbitrap) {
      # Get MS1 IT (auto or custom)
      ms1_it <- if (isTRUE(input$ms1_it_auto)) {
        "auto"
      } else {
        input$ms1_it_custom %||% 50
      }

      # Get MS2 IT (auto or custom)
      ms2_it <- if (isTRUE(input$ms2_it_auto)) {
        "auto"
      } else {
        input$ms2_it_custom %||% 50
      }

      # Get MS1 scans per cycle (for Boxcar support) - use the explicit dependency
      ms1_scans <- ms1_scans_input %||% 1

      config <- list(
        instrument = list(preset = instrument),
        ms1 = list(
          resolution = as.numeric(input$ms1_resolution %||% 60000),
          max_injection_time_ms = ms1_it,
          scans_per_cycle = ms1_scans
        ),
        ms2 = list(
          resolution = as.numeric(input$ms2_resolution %||% 15000),
          max_injection_time_ms = ms2_it
        ),
        dia_windows = list(
          window_count = window_count_input %||% 40
        )
      )
    } else if (is_astral) {
      # Astral: use the Astral IT slider (MS1 on Orbitrap, MS2 on Astral - parallel)
      # TODO: Future enhancement - separate MS1 IT input for dual analyzer instruments
      ms2_it <- input$astral_ms2_it %||% 3.0

      config <- list(
        instrument = list(preset = instrument),
        ms1 = list(
          resolution = 120000,  # Orbitrap MS1
          max_injection_time_ms = 50,  # TODO: Add separate MS1 IT for Astral
          scans_per_cycle = 0  # Parallel: MS1 during MS2
        ),
        ms2 = list(
          resolution = 80000,  # Astral fixed
          max_injection_time_ms = ms2_it
        ),
        dia_windows = list(
          window_count = window_count_input %||% 100
        )
      )
    } else {
      # TOF instruments - use explicit dependency
      ms1_scans <- ms1_scans_input %||% 0  # Usually parallel

      config <- list(
        instrument = list(preset = instrument),
        ms1 = list(
          resolution = NULL,
          max_injection_time_ms = 10,
          scans_per_cycle = ms1_scans
        ),
        ms2 = list(
          resolution = NULL,
          max_injection_time_ms = 2
        ),
        dia_windows = list(
          window_count = window_count_input %||% 50
        )
      )
    }

    # Calculate cycle time
    tryCatch({
      result <- calculate_cycle_time_from_experiment(config, verbose = FALSE)
      result
    }, error = function(e) {
      cat("[Shiny] Error calculating cycle time:", e$message, "\n")
      NULL
    })
  })

  # --- Output: Auto IT value displays ---
  output$ms1_it_auto_value <- renderText({
    ms1_res <- as.numeric(input$ms1_resolution %||% 60000)
    transient <- get_transient_time(ms1_res, "orbitrap")
    sprintf("%.0f ms (T_transient)", transient)
  })

  output$ms2_it_auto_value <- renderText({
    ms2_res <- as.numeric(input$ms2_resolution %||% 15000)
    transient <- get_transient_time(ms2_res, "orbitrap")
    sprintf("%.0f ms (T_transient)", transient)
  })

  # --- Output: Calculated Cycle Time Display ---
  output$calculated_cycle_time <- renderText({
    result <- cycle_time_result()
    if (is.null(result)) {
      return("--")
    }
    sprintf("%.3f", result$cycle_time_sec)
  })

  output$cycle_time_breakdown <- renderText({
    result <- cycle_time_result()
    if (is.null(result)) {
      return("")
    }

    ms1_scans <- result$ms1$scans_per_cycle %||% 1
    if (ms1_scans == 0) {
      # Parallel mode
      sprintf("MS1: %.0fms (parallel) | MS2: %d x %.1fms",
              result$ms1$scan_time_ms,
              result$window_count,
              result$ms2$scan_time_ms)
    } else if (ms1_scans > 1) {
      # Boxcar mode
      sprintf("MS1: %dx%.0fms | MS2: %d x %.1fms",
              ms1_scans,
              result$ms1$scan_time_ms,
              result$window_count,
              result$ms2$scan_time_ms)
    } else {
      # Standard sequential
      sprintf("MS1: %.0fms + MS2: %d x %.1fms",
              result$ms1$scan_time_ms,
              result$window_count,
              result$ms2$scan_time_ms)
    }
  })

  # --- Output: Greedy Auto Windows Info ---
  # Shows the recommended window count when Auto mode is selected
  output$greedy_auto_windows_info <- renderUI({
    # Calculate recommended windows from DPPP target and cycle time
    calc_result <- cycle_time_result()

    # Try to get windows from optimization plan first
    plan_windows <- rv$optimization_plan$n_windows_per_bin

    # Calculate based on target DPPP if we have FWHM data
    dppp_windows <- NULL
    if (!is.null(rv$validated_data)) {
      fwhm_values <- ensure_fwhm_seconds(rv$validated_data$data$FWHM)
      fwhm_median <- median(fwhm_values, na.rm = TRUE)

      if (!is.null(calc_result) && !is.na(fwhm_median)) {
        # DPPP = 1.7 x FWHM / cycle_time
        # cycle_time ~ n_windows x ms2_time (simplified for Astral parallel)
        # target_dppp = 1.7 x fwhm / (n_windows x ms2_time)
        # n_windows = 1.7 x fwhm / (target_dppp x ms2_time)
        target_dppp <- input$target_dppp %||% 7.0
        ms2_time_sec <- calc_result$ms2$scan_time_ms / 1000
        dppp_windows <- estimate_window_count_preview(fwhm_median, target_dppp, ms2_time_sec)
      }
    }

    # Determine which value to show
    if (!is.null(plan_windows)) {
      # Optimization plan available
      tags$div(
        style = "background: rgba(39, 174, 96, 0.15); padding: 6px 8px; border-radius: 4px; margin: 4px 0;",
        tags$span(
          style = "color: #27ae60; font-weight: 600;",
          sprintf("Auto: %d windows", plan_windows)
        ),
        tags$br(),
        tags$small("(from optimization plan)", style = "color: #7f8c8d;")
      )
    } else if (!is.null(dppp_windows)) {
      # Estimated from DPPP calculation
      tags$div(
        style = "background: rgba(52, 152, 219, 0.15); padding: 6px 8px; border-radius: 4px; margin: 4px 0;",
        tags$span(
          style = "color: #3498db; font-weight: 600;",
          sprintf("Estimated: %d windows", dppp_windows)
        ),
        tags$br(),
        tags$small(sprintf("(for DPPP %.1f with current settings)", input$target_dppp),
                   style = "color: #7f8c8d;")
      )
    } else {
      # No data available yet
      tags$div(
        style = "background: rgba(149, 165, 166, 0.15); padding: 6px 8px; border-radius: 4px; margin: 4px 0;",
        tags$span(
          style = "color: #7f8c8d;",
          "Upload data to see recommended windows"
        )
      )
    }
  })

  # --- Output: Greedy m/z Range Display ---
  output$greedy_mz_range_display <- renderUI({
    # Get window count (from auto or manual)
    if (isTRUE(input$greedy_auto_windows)) {
      # Priority: optimization plan > estimated > default
      n_windows <- rv$optimization_plan$n_windows_per_bin

      # Estimate if no plan yet
      if (is.null(n_windows) && !is.null(rv$validated_data)) {
        calc_result <- cycle_time_result()
        fwhm_values <- ensure_fwhm_seconds(rv$validated_data$data$FWHM)
        fwhm_median <- median(fwhm_values, na.rm = TRUE)
        if (!is.null(calc_result) && !is.na(fwhm_median)) {
          target_dppp <- input$target_dppp %||% 7.0
          ms2_time_sec <- calc_result$ms2$scan_time_ms / 1000
          n_windows <- estimate_window_count_preview(fwhm_median, target_dppp, ms2_time_sec)
        }
      }

      n_windows <- n_windows %||% 40
    } else {
      n_windows <- input$greedy_n_windows %||% 40
    }

    min_width <- input$min_isolation_width %||% 2
    mz_range <- n_windows * min_width

    # Determine if this is a reasonable range (typical precursor spread is 400-1200 m/z)
    range_status <- if (mz_range < 100) {
      list(color = "#e74c3c", icon = "!", msg = "Very narrow - may miss many precursors")
    } else if (mz_range < 200) {
      list(color = "#f39c12", icon = "~", msg = "Narrow range - check coverage")
    } else if (mz_range > 600) {
      list(color = "#3498db", icon = "o", msg = "Wide range - good coverage expected")
    } else {
      list(color = "#27ae60", icon = "v", msg = "Typical range for DIA")
    }

    tags$div(
      style = "background: rgba(241, 196, 15, 0.25); padding: 10px; border-radius: 6px; margin: 8px 0; border: 1px solid rgba(241, 196, 15, 0.4);",

      # Main value
      tags$div(
        style = "display: flex; justify-content: space-between; align-items: baseline;",
        tags$span(
          style = "font-size: 18px; font-weight: 700; color: #d35400;",
          sprintf("%.0f Da", mz_range)
        ),
        tags$span(
          style = "font-size: 12px; color: #7f8c8d;",
          "Fixed m/z Range"
        )
      ),

      # Formula breakdown
      tags$div(
        style = "margin-top: 6px; padding-top: 6px; border-top: 1px dashed rgba(211, 84, 0, 0.3);",
        tags$span(
          style = "font-size: 12px; color: #8e44ad;",
          sprintf("%d windows", n_windows)
        ),
        tags$span(style = "color: #7f8c8d; margin: 0 4px;", "x"),
        tags$span(
          style = "font-size: 12px; color: #16a085;",
          sprintf("%.1f Da (min width)", min_width)
        )
      ),

      # Status indicator
      tags$div(
        style = sprintf("margin-top: 6px; font-size: 11px; color: %s;", range_status$color),
        sprintf("%s %s", range_status$icon, range_status$msg)
      )
    )
  })

  output$efficiency_badge <- renderUI({
    result <- cycle_time_result()
    if (is.null(result)) {
      return(NULL)
    }

    efficiency_pct <- result$ms2$efficiency_pct
    efficiency_mode <- result$ms2$efficiency_mode

    if (efficiency_mode == "auto" || efficiency_pct >= 95) {
      # Optimal
      tags$span(
        style = "background: #27ae60; color: white; padding: 2px 8px; border-radius: 4px; font-size: 10px; font-weight: 600;",
        sprintf("%.0f%% Efficiency", efficiency_pct)
      )
    } else if (efficiency_pct >= 70) {
      # Acceptable
      tags$span(
        style = "background: #f39c12; color: white; padding: 2px 8px; border-radius: 4px; font-size: 10px; font-weight: 600;",
        sprintf("%.0f%% Efficiency", efficiency_pct)
      )
    } else {
      # Low efficiency
      tags$span(
        style = "background: #e74c3c; color: white; padding: 2px 8px; border-radius: 4px; font-size: 10px; font-weight: 600;",
        sprintf("%.0f%% Efficiency", efficiency_pct)
      )
    }
  })

  # --- Output: Cycle Time Detail Table (Main Body) ---
  output$cycle_time_detail_table <- renderTable({
    result <- cycle_time_result()
    if (is.null(result)) {
      return(data.frame(
        Parameter = c("Waiting for instrument selection..."),
        Value = c("")
      ))
    }

    # Determine instrument type for display
    is_orbitrap <- result$instrument$analyzer_type == "orbitrap"
    ms1_scans <- result$ms1$scans_per_cycle %||% 1
    is_boxcar <- ms1_scans > 1
    is_parallel <- ms1_scans == 0

    # Build parameter list dynamically
    params <- c("Instrument")
    values <- c(result$instrument$name)

    if (is_orbitrap) {
      params <- c(params, "MS1 Resolution", "MS2 Resolution")
      values <- c(values,
                  format(result$ms1$resolution, big.mark = ","),
                  format(result$ms2$resolution, big.mark = ","))
    }

    params <- c(params, "MS1 Scans/Cycle")
    values <- c(values, sprintf("%d %s", ms1_scans,
                                ifelse(is_boxcar, "(Boxcar)",
                                       ifelse(is_parallel, "(Parallel)", ""))))

    params <- c(params, "MS1 Scan Time", "MS2 Scan Time", "MS2 Window Count")
    values <- c(values,
                sprintf("%.1f ms", result$ms1$scan_time_ms),
                sprintf("%.1f ms (%.1f Hz)", result$ms2$scan_time_ms, result$theoretical_ms2_rate_hz),
                as.character(result$window_count))

    if (is_boxcar || !is_parallel) {
      params <- c(params, "MS1 Total Time")
      values <- c(values, sprintf("%.0f ms (= %d x %.0f ms)",
                                  result$ms1$total_time_ms %||% result$ms1$scan_time_ms,
                                  ms1_scans, result$ms1$scan_time_ms))
    }

    params <- c(params, "MS2 Total Time", "Cycle Time")
    values <- c(values,
                sprintf("%.0f ms", result$ms2_total_time_ms),
                sprintf("%.3f sec (%.0f ms)", result$cycle_time_sec, result$cycle_time_ms))

    data.frame(Parameter = params, Value = values)
  }, striped = TRUE, hover = TRUE, spacing = "s", width = "100%")

  # --- Output: Cycle Time Visual Breakdown ---
  output$cycle_time_visual <- renderUI({
    result <- cycle_time_result()
    if (is.null(result)) {
      return(tags$p("Configure instrument settings to see breakdown.", style = "color: #999;"))
    }

    total_ms <- result$cycle_time_ms
    ms1_total_ms <- result$ms1$total_time_ms  # Use total time (includes all MS1 scans in Boxcar mode)
    ms1_pct <- (ms1_total_ms / total_ms) * 100
    ms2_pct <- (result$ms2_total_time_ms / total_ms) * 100

    # For parallel instruments, adjust display
    is_parallel <- result$instrument$cycle_calculation == "parallel"

    if (is_parallel) {
      tags$div(
        tags$p(
          style = "font-size: 12px; color: #7f8c8d; margin-bottom: 8px;",
          "Parallel Mode: MS1 acquired during MS2 scans"
        ),
        tags$div(
          style = "background: #3498db; height: 24px; border-radius: 4px; position: relative; overflow: hidden;",
          tags$div(
            style = sprintf("position: absolute; left: 0; top: 0; height: 100%%; width: 100%%; background: #1abc9c;"),
            tags$span(
              style = "position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); color: white; font-size: 11px; font-weight: 600;",
              sprintf("MS2: %.0f ms (100%%)", result$ms2_total_time_ms)
            )
          )
        )
      )
    } else {
      tags$div(
        tags$p(
          style = "font-size: 12px; color: #7f8c8d; margin-bottom: 8px;",
          "Sequential Mode: MS1 -> MS2"
        ),
        tags$div(
          style = "display: flex; height: 24px; border-radius: 4px; overflow: hidden;",
          tags$div(
            style = sprintf("width: %.1f%%; background: #3498db; display: flex; align-items: center; justify-content: center;", ms1_pct),
            tags$span(style = "color: white; font-size: 10px; font-weight: 600;",
                      sprintf("MS1 %.0fms", ms1_total_ms))
          ),
          tags$div(
            style = sprintf("width: %.1f%%; background: #1abc9c; display: flex; align-items: center; justify-content: center;", ms2_pct),
            tags$span(style = "color: white; font-size: 10px; font-weight: 600;",
                      sprintf("MS2 %.0fms", result$ms2_total_time_ms))
          )
        )
      )
    }
  })

  # --- Output: Efficiency Detail ---
  output$efficiency_detail <- renderUI({
    result <- cycle_time_result()
    if (is.null(result)) {
      return(NULL)
    }

    efficiency_pct <- result$ms2$efficiency_pct
    efficiency_mode <- result$ms2$efficiency_mode
    limiting_factor <- result$ms2$limiting_factor
    sweet_spot_it <- result$ms2$sweet_spot_it_ms
    current_it <- result$ms2$injection_time_ms
    transient <- result$ms2$transient_ms

    # Build message based on limiting factor
    if (efficiency_mode == "auto" || efficiency_pct >= 95) {
      color <- "#27ae60"
      icon_class <- "check-circle"
      message <- sprintf("Optimal! IT (%.0f ms) ~ T_transient (%.0f ms)", current_it, transient)
      suggestion <- NULL
    } else {
      color <- if (efficiency_pct >= 70) "#f39c12" else "#e74c3c"
      icon_class <- "exclamation-triangle"
      message <- sprintf(
        "IT (%.0f ms) > T_transient (%.0f ms) -> Injection Limited",
        current_it, transient
      )
      suggestion <- sprintf(
        "Tip: Use Auto IT (%.0f ms) for %.1f%% faster scans",
        sweet_spot_it, (1 - efficiency_pct/100) * 100
      )
    }

    tags$div(
      style = sprintf("padding: 10px; border-radius: 6px; background: %s15; border-left: 3px solid %s;", color, color),
      tags$div(
        style = "display: flex; align-items: center; gap: 8px;",
        icon(icon_class, style = sprintf("color: %s;", color)),
        tags$strong(sprintf("Efficiency: %.0f%%", efficiency_pct), style = sprintf("color: %s;", color))
      ),
      tags$p(style = "margin: 6px 0 0 0; font-size: 12px; color: #34495e;", message),
      if (!is.null(suggestion)) {
        tags$p(style = "margin: 4px 0 0 0; font-size: 11px; color: #7f8c8d;", suggestion)
      }
    )
  })

  # --- Toggle: "More Options" in Setup tab ---
  observeEvent(input$toggle_setup_more, {
    shinyjs::toggle("setup_more_options")
  })

  # --- DPPP Preset Buttons ---
  observeEvent(input$preset_id, {
    updateNumericInput(session, "target_dppp", value = 1.5)
  })

  observeEvent(input$preset_balanced, {
    updateNumericInput(session, "target_dppp", value = 4.0)
  })

  observeEvent(input$preset_quant, {
    updateNumericInput(session, "target_dppp", value = 7.0)
  })

  # --- File Upload Handler ---
  observeEvent(input$parquet_file, {
    req(input$parquet_file)

    # Show processing notification
    showNotification("Processing file...", id = "upload_progress", duration = NULL, type = "message")

    tryCatch({
      # Read parquet file
      file_path <- input$parquet_file$datapath
      cat("\n[Shiny] File uploaded:", input$parquet_file$name, "\n")
      cat("[Shiny] Temp path:", file_path, "\n")
      cat("[Shiny] File size:", file.info(file_path)$size / 1024^2, "MB\n")

      # Run Stage 1: Data Validation
      cat("[Shiny] Starting create_validated_dataset()...\n")
      rv$validated_data <- create_validated_dataset(
        proteome_file = file_path,
        enable_replicate_consensus = TRUE,
        max_intensity_cv_percent = 30
      )
      cat("[Shiny] create_validated_dataset() completed!\n")

      rv$data_loaded <- TRUE
      rv$optimization_complete <- FALSE
      rv$optimized_windows <- NULL

      # Calculate DPPP Quick Preview
      cat("[Shiny] Calculating DPPP Quick Preview...\n")
      rv$dppp_preview <- quick_dppp_preview(
        rv$validated_data,
        cycle_times = c(1.5, 2.5, 3.5),
        target_dppp = input$target_dppp
      )
      cat("[Shiny] DPPP Preview calculated!\n")

      removeNotification("upload_progress")
      showNotification(
        paste("Data loaded:", format(nrow(rv$validated_data$data), big.mark = ","), "precursors"),
        type = "message"
      )

    }, error = function(e) {
      cat("[Shiny] ERROR in file upload:", e$message, "\n")
      removeNotification("upload_progress")
      showNotification(paste("Error:", e$message), type = "error", duration = 10)
      rv$data_loaded <- FALSE
    })
  })

  # --- Run Optimization ---
  observeEvent(input$run_optimization, {
    # Check if data is loaded
    if (is.null(rv$validated_data) || !rv$data_loaded) {
      showNotification("Please upload a parquet file first!", type = "warning")
      return()
    }

    # Show processing notification
    showNotification("Running optimization...", id = "opt_progress", duration = NULL, type = "message")

    tryCatch({
      cat("\n[Shiny] Starting optimization...\n")
      cat("[Shiny] Instrument:", input$instrument, "\n")
      cat("[Shiny] Target DPPP:", input$target_dppp, "\n")
      cat("[Shiny] Target Satisfaction:", input$target_satisfaction, "%\n")
      cat("[Shiny] m/z Strategy:", input$mz_strategy, "\n")

      # Log IT mode for Orbitrap instruments
      is_orbitrap <- is_orbitrap_instrument(input$instrument)
      is_astral <- is_astral_instrument(input$instrument)

      if (is_orbitrap) {
        ms1_it_mode <- if (isTRUE(input$ms1_it_auto)) "AUTO" else sprintf("CUSTOM (%d ms)", input$ms1_it_custom)
        ms2_it_mode <- if (isTRUE(input$ms2_it_auto)) "AUTO" else sprintf("CUSTOM (%d ms)", input$ms2_it_custom)
        cat("[Shiny] MS1 IT Mode:", ms1_it_mode, "\n")
        cat("[Shiny] MS2 IT Mode:", ms2_it_mode, "\n")
      } else if (is_astral) {
        cat("[Shiny] Astral MS2 IT:", input$astral_ms2_it, "ms\n")
      }

      # Stage 2: Optimization Planning
      cat("[Shiny] Running plan_optimization()...\n")

      # Determine Custom IT override (Orbitrap only)
      ms2_time_override_sec <- NULL
      if (is_orbitrap && !isTRUE(input$ms2_it_auto)) {
        ms2_time_override_sec <- (input$ms2_it_custom %||% 50) / 1000  # ms to sec
        cat("[Shiny] Custom MS2 IT Override:", input$ms2_it_custom, "ms\n")
      } else if (is_astral) {
        ms2_time_override_sec <- (input$astral_ms2_it %||% 3) / 1000
        cat("[Shiny] Astral MS2 IT:", input$astral_ms2_it, "ms\n")
      } else {
        cat("[Shiny] Using Auto IT (Sweet Spot mode)\n")
      }

      # Get calculated current cycle time from experiment parameters
      calc_result <- cycle_time_result()
      current_cycle_time_sec <- if (!is.null(calc_result)) {
        cat("[Shiny] Using calculated current cycle time:", calc_result$cycle_time_sec, "sec\n")
        cat("[Shiny]   - MS1 scan time:", calc_result$ms1$scan_time_ms, "ms\n")
        cat("[Shiny]   - MS2 scan time:", calc_result$ms2$scan_time_ms, "ms\n")
        cat("[Shiny]   - Window count:", calc_result$window_count, "\n")
        cat("[Shiny]   - Efficiency:", calc_result$ms2$efficiency_pct, "%\n")
        calc_result$cycle_time_sec
      } else {
        cat("[Shiny] No calculated cycle time, using auto-estimate\n")
        NULL
      }

      rv$optimization_plan <- plan_optimization(
        validated_data = rv$validated_data,
        instrument_preset = input$instrument,
        target_dppp = input$target_dppp,
        target_satisfaction = input$target_satisfaction / 100,
        ms2_time_override = ms2_time_override_sec,
        current_cycle_time = current_cycle_time_sec,
        ms2_resolution = if (!is.null(input$ms2_resolution)) as.numeric(input$ms2_resolution) else NULL
      )
      cat("[Shiny] plan_optimization() completed!\n")

      # Debug: Show key optimization parameters
      cat("[Shiny] === OPTIMIZATION PLAN DEBUG ===\n")
      cat("[Shiny] Target DPPP:", input$target_dppp, "\n")
      cat("[Shiny] Required Cycle Time:", rv$optimization_plan$required_cycle_time_sec, "sec\n")
      cat("[Shiny] Current Cycle Time:", rv$optimization_plan$current_cycle_time_sec, "sec\n")
      cat("[Shiny] Windows per bin:", rv$optimization_plan$window_count_per_bin, "\n")
      cat("[Shiny] t_scan:", rv$optimization_plan$timing$t_scan_ms, "ms\n")
      cat("[Shiny] ================================\n")

      # Determine RT bin width and binning mode
      rt_binning_mode_input <- input$rt_binning_mode %||% "fixed"

      if (rt_binning_mode_input == "custom") {
        # Custom: user-specified bin width, fixed binning
        rt_bin_width_final <- input$rt_bin_width
        rt_binning_mode_final <- "fixed"
        cat("[Shiny] Custom RT Bin Width:", rt_bin_width_final, "min (fixed binning)\n")
      } else {
        # Fixed and Adaptive: auto-calculate bin width
        rt_range <- range(rv$validated_data$data$RT.Apex, na.rm = TRUE)
        auto_result <- calculate_auto_rt_bin_width(
          rt_range = rt_range,
          mz_strategy = input$mz_strategy,
          target_min_bins = 5
        )
        rt_bin_width_final <- auto_result$bin_width

        if (rt_binning_mode_input == "adaptive") {
          rt_binning_mode_final <- "adaptive"
          cat("[Shiny] Adaptive RT Binning: auto width =", rt_bin_width_final, "min (used as min constraint)")
          cat(" (", auto_result$n_bins, " target bins for ", input$mz_strategy, " strategy)\n", sep = "")
        } else {
          rt_binning_mode_final <- "fixed"
          cat("[Shiny] Fixed RT Binning: auto width =", rt_bin_width_final, "min")
          cat(" (", auto_result$n_bins, " bins for ", input$mz_strategy, " strategy)\n", sep = "")
        }

        showNotification(
          sprintf("RT bin: %.1f min (%s, %d bins)", rt_bin_width_final, rt_binning_mode_final, auto_result$n_bins),
          type = "message", duration = 3
        )
      }

      # Stage 3: Window Optimization with selected m/z strategy
      cat("[Shiny] Running optimize_windows()...\n")
      cat("[Shiny] m/z Range Strategy:", input$mz_strategy, "\n")
      cat("[Shiny] Window Width Mode:", input$window_mode, "\n")
      cat("[Shiny] RT Binning Mode:", input$rt_binning_mode %||% "fixed", "\n")
      cat("[Shiny] Min Isolation Width:", input$min_isolation_width, "Da\n")

      # Get strategy-specific parameters with defaults
      strategy_params <- list(
        # Quantile parameters
        quantile_lower = input$quantile_lower %||% 0.05,
        quantile_upper = input$quantile_upper %||% 0.95,
        quantile_apply_smoothing = isTRUE(input$quantile_apply_smoothing %||% FALSE),
        # Coverage parameters
        target_coverage = (input$target_coverage %||% 90) / 100,  # Convert % to ratio
        # Greedy parameters
        mz_step = input$greedy_mz_step %||% 2.0,
        greedy_n_windows = NULL,  # Will be set below if manual
        greedy_apply_smoothing = isTRUE(input$greedy_apply_smoothing %||% TRUE),
        # Outlier parameters
        outlier_threshold = input$outlier_threshold %||% 3.0,
        outlier_apply_smoothing = isTRUE(input$outlier_apply_smoothing %||% FALSE),
        # SG Smoothing parameters (shared)
        smoothing_window = 7,
        polynomial_order = 3,
        # KDE parameters
        kde_density_threshold = (input$kde_density_threshold %||% 10) / 100,  # Convert % to ratio
        kde_min_coverage = (input$kde_min_coverage %||% 80) / 100  # Convert % to ratio
      )

      # Handle Greedy window count (auto vs manual)
      if (input$mz_strategy == "greedy" && !isTRUE(input$greedy_auto_windows)) {
        strategy_params$greedy_n_windows <- input$greedy_n_windows %||% 40
        cat(sprintf("[Shiny] Greedy: Manual window count = %d\n", strategy_params$greedy_n_windows))
      }

      cat("[Shiny] Strategy parameters:\n")
      cat(sprintf("  - Quantile: P%.0f-P%.0f, SG=%s\n",
                  strategy_params$quantile_lower * 100,
                  strategy_params$quantile_upper * 100,
                  ifelse(strategy_params$quantile_apply_smoothing, "YES", "NO")))
      cat(sprintf("  - Coverage target: %.0f%%\n", strategy_params$target_coverage * 100))
      cat(sprintf("  - Greedy mz_step: %.1f Da, SG=%s\n",
                  strategy_params$mz_step,
                  ifelse(strategy_params$greedy_apply_smoothing, "YES", "NO")))
      if (!is.null(strategy_params$greedy_n_windows)) {
        cat(sprintf("  - Greedy n_windows: %d (manual)\n", strategy_params$greedy_n_windows))
      }
      cat(sprintf("  - Outlier threshold: %.1f SD, SG=%s\n",
                  strategy_params$outlier_threshold,
                  ifelse(strategy_params$outlier_apply_smoothing, "YES", "NO")))
      cat(sprintf("  - KDE: threshold=%.0f%%, min_coverage=%.0f%%\n",
                  strategy_params$kde_density_threshold * 100,
                  strategy_params$kde_min_coverage * 100))

      rv$optimized_windows <- optimize_windows(
        validated_data = rv$validated_data,
        optimization_plan = rv$optimization_plan,
        mz_strategy = input$mz_strategy,
        window_mode = input$window_mode %||% "density",
        rt_bin_width_min = rt_bin_width_final,
        rt_binning_mode = rt_binning_mode_final,
        cpd_significance_level = input$cpd_significance %||% 0.05,
        cpd_min_bin_width = input$cpd_min_bin_width %||% 1.0,
        edge_void_buffer_min = input$edge_void_buffer %||% 0.5,
        edge_wash_min_precursors = input$edge_wash_threshold %||% 30,
        min_width_da = input$min_isolation_width %||% 2,
        # Pass strategy-specific parameters
        quantile_lower = strategy_params$quantile_lower,
        quantile_upper = strategy_params$quantile_upper,
        quantile_apply_smoothing = strategy_params$quantile_apply_smoothing,
        target_coverage = strategy_params$target_coverage,
        mz_step = strategy_params$mz_step,
        n_windows_override = strategy_params$greedy_n_windows,  # For Greedy manual override
        greedy_apply_smoothing = strategy_params$greedy_apply_smoothing,
        outlier_threshold = strategy_params$outlier_threshold,
        outlier_apply_smoothing = strategy_params$outlier_apply_smoothing,
        smoothing_window = strategy_params$smoothing_window,
        polynomial_order = strategy_params$polynomial_order,
        # KDE parameters
        kde_density_threshold = strategy_params$kde_density_threshold,
        kde_min_coverage = strategy_params$kde_min_coverage
      )
      cat("[Shiny] optimize_windows() completed!\n")

      rv$optimization_complete <- TRUE

      removeNotification("opt_progress")
      showNotification(
        paste("Optimization complete:", nrow(rv$optimized_windows$windows), "windows generated"),
        type = "message"
      )

    }, error = function(e) {
      cat("[Shiny] ERROR in optimization:", e$message, "\n")
      removeNotification("opt_progress")
      showNotification(paste("Error:", e$message), type = "error", duration = 10)
      rv$optimization_complete <- FALSE
    })
  })

  # --- Output: Data Status Info Box ---
  output$data_status <- renderbs4InfoBox({
    # Guard clause: return "waiting" state early if no data loaded
    if (!rv$data_loaded || is.null(rv$validated_data)) {
      return(bs4InfoBox(
        title = "Data Status",
        value = "Waiting",
        subtitle = "Upload parquet file",
        icon = icon("cloud-upload-alt"),
        color = "warning",
        fill = TRUE
      ))
    }

    n_precursors <- nrow(rv$validated_data$data)
    has_dppp_preview <- !is.null(rv$dppp_preview)
    gradient_len <- if (has_dppp_preview) {
      sprintf("%.0f min gradient", rv$dppp_preview$gradient_length)
    } else {
      "Ready"
    }

    bs4InfoBox(
      title = "Precursors Loaded",
      value = format(n_precursors, big.mark = ","),
      subtitle = gradient_len,
      icon = icon("check-circle"),
      color = "success",
      fill = TRUE
    )
  })

  # --- Output: Optimization Status Info Box ---
  output$optimization_status <- renderbs4InfoBox({
    # Guard clause: return "pending" state early if not optimized
    if (!rv$optimization_complete || is.null(rv$optimized_windows)) {
      return(bs4InfoBox(
        title = "Optimization",
        value = "Pending",
        subtitle = "Configure and run",
        icon = icon("cogs"),
        color = "warning",
        fill = TRUE
      ))
    }

    n_windows <- nrow(rv$optimized_windows$windows)
    has_coverage <- !is.null(rv$optimized_windows$statistics$coverage_percentage)
    coverage <- if (has_coverage) {
      sprintf("%.1f%% coverage", rv$optimized_windows$statistics$coverage_percentage)
    } else {
      "Optimized"
    }

    bs4InfoBox(
      title = "Windows Generated",
      value = n_windows,
      subtitle = coverage,
      icon = icon("layer-group"),
      color = "info",
      fill = TRUE
    )
  })

  # --- Output: Download Status Info Box ---
  output$download_status <- renderbs4InfoBox({
    # Guard clause: return "waiting" state early if not ready
    if (!rv$optimization_complete) {
      return(bs4InfoBox(
        title = "Export",
        value = "Waiting",
        subtitle = "Run optimization first",
        icon = icon("hourglass-half"),
        color = "warning",
        fill = TRUE
      ))
    }

    bs4InfoBox(
      title = "Export Ready",
      value = "Download",
      subtitle = "CSV & PDF available",
      icon = icon("file-download"),
      color = "success",
      fill = TRUE
    )
  })

  # --- Output: Conditional flags for UI ---
  output$data_loaded <- reactive({ rv$data_loaded })
  outputOptions(output, "data_loaded", suspendWhenHidden = FALSE)

  output$optimization_complete <- reactive({ rv$optimization_complete })
  outputOptions(output, "optimization_complete", suspendWhenHidden = FALSE)

  # --- Reactive: DPPP Quick Preview (responds to target_dppp and satisfaction changes) ---
  dppp_preview_reactive <- reactive({
    req(rv$validated_data)

    # Get current parameters (these trigger reactivity)
    target_dppp <- input$target_dppp
    target_satisfaction <- input$target_satisfaction / 100

    # Also consider calculated cycle time
    calc_ct <- cycle_time_result()
    current_ct <- if (!is.null(calc_ct)) calc_ct$cycle_time_sec else NULL

    # Calculate DPPP preview with current target
    tryCatch({
      quick_dppp_preview(
        rv$validated_data,
        cycle_times = c(1.0, 1.5, 2.0, 2.5, 3.0, 3.5),
        target_dppp = target_dppp,
        target_satisfaction = target_satisfaction
      )
    }, error = function(e) {
      cat("[Shiny] Error in DPPP preview:", e$message, "\n")
      NULL
    })
  })

  # --- Output: DPPP Quick Preview ---
  # Output: Current target DPPP for reactive display
  output$current_target_dppp <- renderText({
    sprintf("%.1f @ %d%% satisfaction", input$target_dppp, input$target_satisfaction)
  })

  output$fwhm_summary <- renderTable({
    preview <- dppp_preview_reactive()
    req(preview)
    fwhm <- preview$fwhm_stats
    data.frame(
      Metric = c("Median", "IQR (Q25-Q75)", "Range (Min-Max)"),
      Value = c(
        sprintf("%.2f sec", fwhm$median),
        sprintf("%.2f - %.2f sec", fwhm$q25, fwhm$q75),
        sprintf("%.2f - %.2f sec", fwhm$min, fwhm$max)
      )
    )
  }, striped = TRUE, hover = TRUE, spacing = "s")

  output$dppp_preview_table <- renderTable({
    preview <- dppp_preview_reactive()
    req(preview)

    # Explicitly depend on target_dppp to ensure reactivity
    target_dppp <- input$target_dppp
    target_satisfaction <- input$target_satisfaction

    # Get current cycle time for highlighting
    calc_ct <- cycle_time_result()
    current_ct <- if (!is.null(calc_ct)) calc_ct$cycle_time_sec else NA

    # Get DPPP data from preview (recalculated with current target_dppp)
    dppp_data <- preview$dppp_preview

    # Build display data with Status based on current target
    # Status shows "v Meet" if DPPP >= target, "x Below" if not
    display_df <- data.frame(
      `Cycle Time` = sprintf("%.1f sec", dppp_data$cycle_time_sec),
      `DPPP` = sprintf("%.1f", dppp_data$dppp_median),
      `Satisfaction` = sprintf("%.0f%%", dppp_data$satisfaction_pct),
      `Status` = ifelse(
        dppp_data$satisfaction_pct >= target_satisfaction,
        sprintf("v >=%d%%", target_satisfaction),
        sprintf("x <%d%%", target_satisfaction)
      ),
      check.names = FALSE
    )

    display_df
  }, striped = TRUE, hover = TRUE, spacing = "s")

  output$dppp_recommendation <- renderUI({
    preview <- dppp_preview_reactive()
    req(preview)

    target <- input$target_dppp
    satisfaction <- input$target_satisfaction
    rec_ct <- preview$recommended_cycle_time

    # Get calculated cycle time
    calc_ct <- cycle_time_result()
    current_ct <- if (!is.null(calc_ct)) calc_ct$cycle_time_sec else NULL

    # Handle NA values
    if (is.null(rec_ct) || is.na(rec_ct)) {
      return(tags$div(
        class = "recommendation-box",
        tags$p("Recommendation not available - FWHM data may be missing.",
               style = "color: #e74c3c;")
      ))
    }

    # Check if current cycle time meets requirements
    meets_target <- !is.null(current_ct) && current_ct <= rec_ct

    tags$div(
      style = "padding: 10px; border-radius: 6px; background: #f8f9fa;",

      # Main recommendation
      tags$div(
        style = "display: flex; align-items: center; gap: 8px; margin-bottom: 8px;",
        icon("lightbulb", style = "color: #f39c12; font-size: 18px;"),
        tags$strong("Target Requirements", style = "color: #2c3e50;")
      ),
      tags$p(
        style = "margin: 0 0 8px 0; font-size: 13px; color: #34495e;",
        sprintf("For DPPP >= %.1f with %d%% satisfaction:", target, satisfaction)
      ),
      tags$p(
        style = "margin: 0 0 12px 0; font-size: 14px;",
        "Required cycle time <= ",
        tags$strong(sprintf("%.2f sec", rec_ct), style = "color: #16a085; font-size: 16px;")
      ),

      # Current status
      if (!is.null(current_ct)) {
        if (meets_target) {
          tags$div(
            style = "padding: 8px; background: #d4edda; border-radius: 4px; border-left: 3px solid #28a745;",
            tags$span(
              style = "color: #155724; font-weight: 600;",
              sprintf("Your current cycle time (%.2f sec) MEETS the requirement!", current_ct)
            )
          )
        } else {
          # Calculate how much reduction is needed
          reduction_needed <- current_ct - rec_ct
          reduction_pct <- (reduction_needed / current_ct) * 100

          tags$div(
            style = "padding: 8px; background: #f8d7da; border-radius: 4px; border-left: 3px solid #dc3545;",
            tags$span(
              style = "color: #721c24; font-weight: 600;",
              sprintf("Current: %.2f sec -> Need: <=%.2f sec", current_ct, rec_ct)
            ),
            tags$br(),
            tags$span(
              style = "color: #721c24; font-size: 12px;",
              sprintf("Reduce cycle time by %.1f sec (%.0f%% reduction needed)", reduction_needed, reduction_pct)
            ),
            tags$br(),
            tags$span(
              style = "color: #856404; font-size: 11px; font-style: italic;",
              "Tip: Use fewer windows, faster scan rate, or lower target DPPP"
            )
          )
        }
      }
    )
  })

  # --- Output: Data Summary Table ---
  output$data_summary <- renderTable({
    req(rv$validated_data)

    data <- rv$validated_data$data

    # Convert FWHM to seconds if in minutes (same logic as quick_dppp_preview)
    fwhm_values <- data$FWHM
    median_fwhm <- median(fwhm_values, na.rm = TRUE)
    if (!is.na(median_fwhm) && median_fwhm < 1) {
      median_fwhm_sec <- median_fwhm * 60  # Convert min to sec
    } else {
      median_fwhm_sec <- median_fwhm
    }

    data.frame(
      Metric = c(
        "Total Precursors",
        "RT Range (min)",
        "m/z Range",
        "Median FWHM (sec)"
      ),
      Value = c(
        format(nrow(data), big.mark = ","),
        sprintf("%.1f - %.1f", min(data$RT.Apex), max(data$RT.Apex)),
        sprintf("%.1f - %.1f", min(data$Precursor.Mz), max(data$Precursor.Mz)),
        sprintf("%.2f", median_fwhm_sec)
      )
    )
  })

  # --- Output: Optimization Summary Table ---
  output$optimization_summary <- renderTable({
    req(rv$optimized_windows)

    windows <- rv$optimized_windows$windows
    plan <- rv$optimization_plan
    params <- rv$optimized_windows$parameters

    # Determine IT mode display
    is_orbitrap <- is_orbitrap_instrument(input$instrument)
    is_astral <- is_astral_instrument(input$instrument)

    it_mode_display <- if (is_orbitrap) {
      if (isTRUE(input$ms2_it_auto)) {
        "Auto (Sweet Spot)"
      } else {
        sprintf("Custom (%d ms)", input$ms2_it_custom %||% 50)
      }
    } else if (is_astral) {
      sprintf("%.1f ms", input$astral_ms2_it %||% 3)
    } else {
      "N/A (TOF)"
    }

    # Build metrics dynamically (include DPPP verification if available)
    metrics <- c(
      "Total Windows",
      "RT Bins",
      "RT Bin Width (min)",
      "IT Mode",
      "Mean Width (Da)",
      "Coverage (%)",
      "Planned Cycle Time (sec)"
    )
    values <- c(
      nrow(windows),
      length(unique(windows$rt_segment_id)),
      sprintf("%.1f", params$rt_bin_width_min),
      it_mode_display,
      sprintf("%.1f", mean(windows$window_width)),
      sprintf("%.1f%%", rv$optimized_windows$statistics$coverage_percentage),
      sprintf("%.2f", plan$required_cycle_time_sec)
    )

    # Add DPPP re-verification results if available
    dppp_v <- rv$optimized_windows$dppp_verification
    if (!is.null(dppp_v)) {
      metrics <- c(metrics,
        "Actual Cycle Time (sec)",
        "Actual DPPP (median)",
        "DPPP Deviation (%)"
      )
      deviation_str <- sprintf("%.1f%%", dppp_v$deviation_pct)
      if (abs(dppp_v$deviation_pct) > 5) {
        deviation_str <- paste(deviation_str, "(WARNING)")
      } else {
        deviation_str <- paste(deviation_str, "(PASS)")
      }
      values <- c(values,
        sprintf("%.3f", dppp_v$actual_cycle_time_sec),
        sprintf("%.2f", dppp_v$actual_dppp_median),
        deviation_str
      )
    }

    data.frame(Metric = metrics, Value = values)
  })

  # --- Output: m/z Range Summary (post-optimization) ---
  output$mz_range_summary <- renderUI({
    req(rv$optimized_windows)

    windows <- rv$optimized_windows$windows
    params <- rv$optimized_windows$parameters

    # Overall m/z range from optimized windows
    mz_min <- min(windows$mz_start, na.rm = TRUE)
    mz_max <- max(windows$mz_end, na.rm = TRUE)
    mz_span <- mz_max - mz_min

    # Per-RT-bin statistics
    n_rt_bins <- length(unique(windows$rt_segment_id))
    windows_per_bin <- nrow(windows) / n_rt_bins

    # Width statistics
    min_width <- min(windows$window_width, na.rm = TRUE)
    max_width <- max(windows$window_width, na.rm = TRUE)
    mean_width <- mean(windows$window_width, na.rm = TRUE)

    # Strategy label
    strategy_label <- if (exists("format_strategy_label")) {
      format_strategy_label(params$mz_strategy)
    } else {
      toupper(params$mz_strategy)
    }

    tags$div(
      style = "font-size: 13px;",

      # Strategy badge
      tags$div(
        style = "margin-bottom: 10px;",
        tags$span(
          style = "background: #2c3e50; color: white; padding: 4px 10px; border-radius: 4px; font-weight: 600; font-size: 12px;",
          strategy_label
        ),
        tags$span(
          style = "background: #16a085; color: white; padding: 4px 10px; border-radius: 4px; font-weight: 600; font-size: 12px; margin-left: 4px;",
          params$window_mode %||% "density"
        )
      ),

      # m/z range
      tags$div(
        style = "padding: 8px; background: #f8f9fa; border-radius: 6px; margin-bottom: 8px; border-left: 3px solid #3498db;",
        tags$div(
          style = "font-weight: 600; color: #2c3e50;",
          sprintf("m/z Range: %.1f - %.1f Da (%.0f Da span)", mz_min, mz_max, mz_span)
        ),
        tags$div(
          style = "color: #7f8c8d; font-size: 12px; margin-top: 4px;",
          sprintf("%.0f windows/bin | %d RT bins", windows_per_bin, n_rt_bins)
        )
      ),

      # Width distribution
      tags$div(
        style = "padding: 8px; background: #f8f9fa; border-radius: 6px; border-left: 3px solid #1abc9c;",
        tags$div(
          style = "font-weight: 600; color: #2c3e50;",
          "Window Width Distribution"
        ),
        tags$div(
          style = "margin-top: 4px; color: #34495e;",
          sprintf("Min: %.1f Da | Mean: %.1f Da | Max: %.1f Da", min_width, mean_width, max_width)
        ),
        if (params$window_mode == "density") {
          tags$div(
            style = "color: #7f8c8d; font-size: 11px; margin-top: 4px; font-style: italic;",
            sprintf("Variable width ratio: %.1fx (max/min)", max_width / max(min_width, 0.1))
          )
        }
      )
    )
  })

  # --- Output: Window Preview Table ---
  output$window_preview <- DT::renderDataTable({
    req(rv$optimized_windows)

    windows <- rv$optimized_windows$windows

    # Select key columns for preview
    preview_cols <- c("rt_segment_id", "mz_start", "mz_end",
                      "window_width", "n_precursors")

    preview_data <- windows[, intersect(preview_cols, names(windows))]

    DT::datatable(
      head(preview_data, 20),
      options = list(
        pageLength = 10,
        scrollX = TRUE,
        dom = 'tip'
      ),
      rownames = FALSE
    ) %>%
      DT::formatRound(columns = c("mz_start", "mz_end", "window_width"), digits = 2)
  })

  # --- Helper: Generate descriptive filename using pipeline convention ---
  # Uses format_output_filename() from utils_common.R:
  # {type}_{instrument}_{strategy}_{window}_{rt}_{date}.{ext}
  shiny_output_filename <- function(type, ext) {
    params <- rv$optimized_windows$parameters
    format_output_filename(
      type = type,
      instrument_preset = input$instrument,
      strategy = input$mz_strategy,
      window_mode = input$window_mode %||% "density",
      rt_binning_mode = input$rt_binning_mode %||% "fixed",
      rt_bin_width_min = params$rt_bin_width_min %||% 5,
      ext = ext
    )
  }

  # --- Download Handler: CSV Method File ---
  output$download_csv <- downloadHandler(
    filename = function() {
      shiny_output_filename("method", "csv")
    },
    content = function(file) {
      req(rv$optimized_windows, rv$validated_data)

      # Build project name from inputs
      project_name <- paste(
        c(
          trimws(input$sample_name %||% ""),
          trimws(input$condition %||% "")
        )[nchar(c(trimws(input$sample_name %||% ""),
                  trimws(input$condition %||% ""))) > 0],
        collapse = "_"
      )
      if (nchar(project_name) == 0) project_name <- "shiny_export"

      # Use existing export function from Stage 3
      export_windows_to_csv(
        optimized_windows = rv$optimized_windows,
        output_file = file,
        validated_data = rv$validated_data,
        optimization_plan = rv$optimization_plan,
        instrument_type = input$instrument,
        project_name = project_name
      )
    }
  )

  # --- Download Handler: PDF Report ---
  output$download_pdf <- downloadHandler(
    filename = function() {
      shiny_output_filename("report", "pdf")
    },
    content = function(file) {
      req(rv$optimized_windows, rv$validated_data, rv$optimization_plan)

      showNotification("Generating PDF report...", id = "pdf_progress",
                       duration = NULL, type = "message")

      tryCatch({
        cat("[Shiny] Generating structured PDF report via generate_visualizations()...\n")

        # Use the pipeline's Stage 4 to generate plots + structured PDF
        # generate_visualizations() calls create_pdf_report() internally
        temp_dir <- tempdir()
        viz_output_dir <- file.path(temp_dir, "shiny_report")
        if (!dir.exists(viz_output_dir)) dir.create(viz_output_dir, recursive = TRUE)

        # Generate all visualizations (single-strategy mode for Shiny)
        viz_result <- generate_visualizations(
          validated_data = rv$validated_data,
          optimization_plan = rv$optimization_plan,
          optimized_windows = rv$optimized_windows,
          output_dir = viz_output_dir,
          create_pdf = FALSE,               # We'll create PDF separately with our filename
          create_individual_plots = FALSE,   # Skip individual PNGs in Shiny
          windows_list = setNames(
            list(rv$optimized_windows),
            input$mz_strategy
          )
        )

        # Create structured PDF using the pipeline's create_pdf_report()
        cat("[Shiny] Creating structured PDF with create_pdf_report()...\n")
        create_pdf_report(
          plots = viz_result$plots,
          validated_data = rv$validated_data,
          optimization_plan = rv$optimization_plan,
          optimized_windows = rv$optimized_windows,
          output_file = file
        )

        removeNotification("pdf_progress")
        cat("[Shiny] PDF report generated successfully!\n")

      }, error = function(e) {
        cat("[Shiny] ERROR generating PDF:", e$message, "\n")
        removeNotification("pdf_progress")
        showNotification(paste("PDF Error:", e$message), type = "error", duration = 10)
      })
    }
  )
}

# =============================================================================
# Run Application
# =============================================================================

shinyApp(ui = ui, server = server)
