# =============================================================================
# AIDIA - Adaptive Isolation for DIA (Shiny Web Application)
# =============================================================================
# Version: 2.1.0
# Purpose: Web-based interface for DIA isolation window optimization
# UI: 3-Step Wizard (Data -> Setup -> Results) with progressive disclosure
# "Your Adaptive Aid for DIA Optimization"
#
# Structure:
#   app.R              - Orchestrator (this file)
#   ui_step1_data.R    - Step 1: Data upload & confirmation UI
#   ui_step2_setup.R   - Step 2: Instrument, strategy, parameters UI
#   ui_step3_results.R - Step 3: Results & downloads UI
#   server_instrument.R - Cycle time calculation & instrument displays
#   server_data.R       - File upload, DPPP preview, data summary
#   server_optimization.R - Run optimization, results display
#   server_downloads.R  - CSV & PDF download handlers
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

# --- Load AIDIA package ---
if (requireNamespace("aidia", quietly = TRUE)) {
  library(aidia)
} else {
  # Development mode: load from package source
  if (file.exists(file.path("..", "..", "DESCRIPTION"))) {
    devtools::load_all(file.path("..", ".."))
  } else if (file.exists(file.path("..", "DESCRIPTION"))) {
    devtools::load_all("..")
  } else {
    stop("AIDIA package not found. Install with: remotes::install_github('KBSI/aidia')")
  }
}

# --- Source Module Files ---
source("ui_step1_data.R", local = TRUE)
source("ui_step2_setup.R", local = TRUE)
source("ui_step3_results.R", local = TRUE)
source("server_instrument.R", local = TRUE)
source("server_data.R", local = TRUE)
source("server_optimization.R", local = TRUE)
source("server_downloads.R", local = TRUE)

# =============================================================================
# UI Definition
# =============================================================================

ui <- dashboardPage(

  # --- Header ---
  header = dashboardHeader(
    title = "AIDIA"
  ),

  # --- Sidebar (Wizard Navigation + Cycle Time) ---
  sidebar = dashboardSidebar(
    width = 250,

    # Wizard step navigation
    sidebarMenu(
      id = "tabs",
      menuItem("1. Data", tabName = "data", icon = icon("database")),
      menuItem("2. Setup", tabName = "setup", icon = icon("sliders-h")),
      menuItem("3. Results", tabName = "results", icon = icon("chart-bar"))
    ),

    hr(),

    # Calculated Cycle Time Display (reactive feedback - always visible)
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
    )
  ),

  # --- Main Body (3-Step Wizard) ---
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

        /* Body form controls - improved visibility */
        .content-wrapper .form-control:focus {
          border-color: #1abc9c !important;
          box-shadow: 0 0 0 2px rgba(26, 188, 156, 0.25) !important;
        }
        .content-wrapper input[type='number'] {
          text-align: center;
          font-size: 14px !important;
          padding: 4px 8px;
        }
      "))
    ),

    # Progress Indicator with accent color
    shinybusy::add_busy_spinner(
      spin = "fading-circle",
      color = "#1abc9c",
      position = "full-page"
    ),

    # =====================================================================
    # WIZARD STEPS (sourced from ui_step*.R modules)
    # =====================================================================
    tabItems(
      step1_data_ui(),
      step2_setup_ui(),
      step3_results_ui()
    )
  ),

  # --- Footer ---
  footer = dashboardFooter(
    left = "AIDIA v2.1.0",
    right = "Adaptive Isolation for DIA"
  ),

  dark = FALSE,
  title = "AIDIA - Adaptive Isolation for DIA"
)

# =============================================================================
# Server Logic
# =============================================================================

server <- function(input, output, session) {

  # --- Reactive Values (shared across all modules) ---
  rv <- reactiveValues(
    validated_data = NULL,
    optimization_plan = NULL,
    optimized_windows = NULL,
    dppp_preview = NULL,
    data_loaded = FALSE,
    optimization_complete = FALSE,
    cycle_time_calc = NULL  # Calculated cycle time result
  )

  # =========================================================================
  # NAVIGATION HANDLERS (Wizard Step Control)
  # =========================================================================

  # Step 1 -> Step 2
  observeEvent(input$btn_to_setup, {
    updateTabItems(session, "tabs", "setup")
  })

  # Step 2 -> Step 1
  observeEvent(input$btn_to_data, {
    updateTabItems(session, "tabs", "data")
  })

  # Step 3 -> Step 2
  observeEvent(input$btn_to_setup_back, {
    updateTabItems(session, "tabs", "setup")
  })

  # New Analysis -> Step 1 (reset)
  observeEvent(input$btn_new_analysis, {
    rv$data_loaded <- FALSE
    rv$optimization_complete <- FALSE
    rv$validated_data <- NULL
    rv$optimized_windows <- NULL
    rv$optimization_plan <- NULL
    rv$dppp_preview <- NULL
    updateTabItems(session, "tabs", "data")
  })

  # Auto-navigate to Results after optimization completes
  observeEvent(rv$optimization_complete, {
    if (rv$optimization_complete) {
      updateTabItems(session, "tabs", "results")
    }
  })

  # =========================================================================
  # MODULE SERVERS
  # =========================================================================

  # Instrument module returns cycle_time_result reactive
  cycle_time_result <- server_instrument(input, output, session, rv)

  # Data module (depends on cycle_time_result for DPPP preview)
  server_data(input, output, session, rv, cycle_time_result)

  # Optimization module (depends on cycle_time_result for run handler)
  server_optimization(input, output, session, rv, cycle_time_result)

  # Downloads module
  server_downloads(input, output, session, rv)
}

# =============================================================================
# Run Application
# =============================================================================

shinyApp(ui = ui, server = server)
