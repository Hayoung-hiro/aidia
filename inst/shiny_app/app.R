# =============================================================================
# AIDIA - Adaptive Isolation for DIA (Shiny Web Application)
# =============================================================================
# Version: see DESCRIPTION (single source of truth)
# Purpose: Web-based interface for DIA isolation window optimization
# UI: 3-Step Wizard (Data -> Setup -> Results) with progressive disclosure
# "Your Adaptive Aid for DIA Optimization"
#
# Structure:
#   app.R              - Orchestrator (this file)
#   ui_step1_data.R    - Step 1: Data upload, instrument, DPPP preview UI
#   ui_step2_setup.R   - Step 2: DPPP target, strategy, parameters UI
#   ui_step3_results.R - Step 3: Results, naming & downloads UI
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

# --- Ensure %||% is available ---
# In dev mode (shiny::runApp without library(aidia)), the package-internal
# %||% is not loaded. Base R only provides it in R >= 4.4.0.
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

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
source("ui_workflow.R", local = TRUE)
source("server_navigation.R", local = TRUE)
source("ui_step1_data.R", local = TRUE)
source("ui_step2_setup.R", local = TRUE)
source("ui_step3_results.R", local = TRUE)
source("server_instrument.R", local = TRUE)
source("server_data.R", local = TRUE)
source("server_optimization.R", local = TRUE)
source("server_downloads.R", local = TRUE)
source("optimization_workflow.R", local = TRUE)
source("server_live_preview.R", local = TRUE)
source("preview_display.R", local = TRUE)
source("results_comparison.R", local = TRUE)

# One bounded worker pool per app process, shared across sessions.
# I(1) also uses a background process when configured with a single worker.
.aidia_previous_future_plan <- future::plan()
future::plan(future::multisession,
             workers = I(getOption("aidia.shiny.workers", 2L)))
shiny::onStop(function() future::plan(.aidia_previous_future_plan))
.aidia_app_path <- normalizePath(".", winslash = "/")
.aidia_package_path <- getNamespaceInfo("aidia", "path")

# =============================================================================
# UI Definition
# =============================================================================

ui <- dashboardPage(

  # --- Header ---
  header = dashboardHeader(
    title = tags$span(
      tags$img(src = "logo_header.png", height = "28px", alt = "AIDIA",
               style = "margin-right: 8px; vertical-align: middle;"),
      style = "display: inline-flex; align-items: center;"
    )
  ),

  # --- Sidebar (Navigation + Data Summary + Cycle Time + Pipeline Status) ---
  sidebar = dashboardSidebar(
    width = 250,

    # Compact product introduction leaves room for navigation and context.
    div(
      class = "workflow-brand",
      tags$strong("DIA window design"),
      tags$p("From your data to an acquisition method.")
    ),

    # Wizard step navigation
    sidebarMenu(
      id = "tabs",
      menuItem("1. Prepare data", tabName = "data", icon = icon("database")),
      menuItem("2. Configure windows", tabName = "setup", icon = icon("sliders-h")),
      menuItem("3. Review & export", tabName = "results", icon = icon("chart-bar"))
    ),

    hr(),

    # Data Summary (compact, shown after data load)
    conditionalPanel(
      condition = "output.data_loaded",
      div(
        style = "padding: 4px 15px 8px 15px;",
        h5("Data Summary", class = "sidebar-heading"),
        uiOutput("sidebar_data_summary")
      ),
      hr()
    ),

    # Persistent reference to the confirmed method used by downloads.
    div(class = "sidebar-metric-card sidebar-method-card",
      h5("Method for download", class = "sidebar-heading"),
      uiOutput("sidebar_confirmed_method")
    ),

    hr(),

    # Pipeline Status (compact, replaces Step 1 info boxes)
    div(
      style = "padding: 4px 15px;",
      h5("Analysis progress", class = "sidebar-heading"),
      uiOutput("sidebar_pipeline_status")
    )
  ),

  # --- Main Body (3-Step Wizard) ---
  body = dashboardBody(

    # shinyjs for progressive disclosure (toggle/hide)
    useShinyjs(),

    # Custom CSS - External stylesheet for professional styling
    tags$head(
      tags$script(src = "workflow-navigation.js"),
      tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),
      # Google Fonts for better typography
      tags$link(
        rel = "stylesheet",
        href = "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap"
      ),
      # Client-side DPPP button sync; sidebar uses AdminLTE responsive navigation.
      tags$script(HTML("
        $(document).ready(function() {
          // --- DPPP Preset Button sync (pure client-side, no server round-trip) ---
          function syncDpppButtons(val) {
            val = parseFloat(val);
            $('.dppp-preset-btn').removeClass('dppp-active');
            if (val === 1.5) $('#preset_id').addClass('dppp-active');
            else if (val === 4.0) $('#preset_balanced').addClass('dppp-active');
            else if (val === 7.0) $('#preset_quant').addClass('dppp-active');
          }

          // Immediate toggle on button click (zero round-trip)
          $(document).on('click', '#preset_id', function() { syncDpppButtons(1.5); });
          $(document).on('click', '#preset_balanced', function() { syncDpppButtons(4.0); });
          $(document).on('click', '#preset_quant', function() { syncDpppButtons(7.0); });

          // Sync when user manually types/changes target DPPP value
          $(document).on('change', '#target_dppp', function() {
            syncDpppButtons($(this).val());
          });

          // Initial sync on page load (default = 7.0 -> Quant active)
          setTimeout(function() {
            var initVal = $('#target_dppp').val();
            if (initVal) syncDpppButtons(initVal);
          }, 300);
        });
      ")),
      # All styles moved to custom.css (equal-height-row, DPPP preview, form controls)
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
    left = paste0("AIDIA v", utils::packageVersion("aidia")),
    right = "Adaptive Isolation for DIA"
  ),

  dark = NULL,
  help = NULL,
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
    confirmed_run = NULL,
    cycle_time_calc = NULL  # Calculated cycle time result
  )

  # =========================================================================
  # NAVIGATION HANDLERS (Wizard Step Control)
  # =========================================================================

  # Client-side scroll-to-top on sidebar tab change only (scoped to sidebar menu, not all tabs)
  shinyjs::runjs("$('.sidebar-menu').on('shown.bs.tab', function() { window.scrollTo(0, 0); });")

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
    rv$confirmed_run <- NULL
    rv$data_error <- NULL
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
  server_navigation(input, output, session, rv, cycle_time_result)

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
