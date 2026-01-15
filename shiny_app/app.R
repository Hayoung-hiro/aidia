# =============================================================================
# DIA Window Optimizer - Shiny Web Application (MVP)
# =============================================================================
# Version: 0.3.0 (MVP with PDF Report)
# Purpose: Web-based interface for DIA isolation window optimization
# =============================================================================

# --- Dependencies ---
library(shiny)
library(shinydashboard)
library(shinybusy)      # Progress indicators
library(DT)             # Interactive tables

# --- Configuration ---
# Increase file upload limit to 500MB (default is 5MB)
# DIA-NN parquet files can be 50-500MB depending on experiment size
options(shiny.maxRequestSize = 500 * 1024^2)

# --- Load diaoptimizer package ---
# Option 1: Use installed package (production)
# library(diaoptimizer)

# Option 2: Use devtools::load_all() for development
# This loads the package from source without installing
if (!requireNamespace("diaoptimizer", quietly = TRUE)) {
  # Package not installed, use load_all for development
  devtools::load_all("..")
} else {
  library(diaoptimizer)
}

# =============================================================================
# UI Definition
# =============================================================================

ui <- dashboardPage(

  # --- Header ---
  dashboardHeader(
    title = "DIA Window Optimizer",
    titleWidth = 250
  ),

  # --- Sidebar ---
  dashboardSidebar(
    width = 250,

    # File Upload Section
    h4("📁 Data Input", style = "padding-left: 15px; color: #ecf0f1;"),
    fileInput(
      inputId = "parquet_file",
      label = "Upload Parquet File",
      accept = c(".parquet"),
      placeholder = "DIA-NN report..."
    ),

    hr(),

    # Instrument Selection
    h4("⚙️ Settings", style = "padding-left: 15px; color: #ecf0f1;"),
    selectInput(
      inputId = "instrument",
      label = "Instrument Preset",
      choices = c(
        "Thermo Astral Zoom (270 Hz)" = "astral_zoom",
        "Thermo Astral (200 Hz)" = "astral",
        "Thermo Q Exactive (12 Hz)" = "qexactive",
        "Thermo Q Exactive HF-X (40 Hz)" = "qexactive_hfx",
        "Thermo Exploris 480 (40 Hz)" = "exploris",
        "Thermo Eclipse Tribrid (40 Hz)" = "eclipse",
        "Thermo Fusion Lumos (20 Hz)" = "fusion_lumos",
        "Bruker timsTOF (100 Hz)" = "timstof",
        "Bruker timsTOF Pro 2 (120 Hz)" = "timstof_pro",
        "Bruker timsTOF Ultra (300 Hz)" = "timstof_ultra",
        "SCIEX ZenoTOF 7600 (133 Hz)" = "sciex_7600",
        "Waters SYNAPT XS (20 Hz)" = "waters_synapt"
      ),
      selected = "astral_zoom"
    ),

    # DPPP Target
    sliderInput(
      inputId = "target_dppp",
      label = "Target DPPP",
      min = 1.5,
      max = 10.0,
      value = 7.0,
      step = 0.5
    ),

    # Quick DPPP Presets
    fluidRow(
      column(4, actionButton("preset_id", "ID", class = "btn-sm btn-info")),
      column(4, actionButton("preset_balanced", "Bal", class = "btn-sm btn-warning")),
      column(4, actionButton("preset_quant", "Quant", class = "btn-sm btn-success"))
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
    ),

    br(),

    # RT Bin Width (for smoothing strategy)
    sliderInput(
      inputId = "rt_bin_width",
      label = "RT Bin Width (min)",
      min = 1,
      max = 15,
      value = 5,
      step = 0.5,
      post = " min"
    ),
    helpText("Controls window grouping. Smaller = more RT segments.",
             style = "font-size: 11px; color: #bdc3c7; padding: 0 15px;"),

    hr(),

    # Run Button
    actionButton(
      inputId = "run_optimization",
      label = "▶ Run Optimization",
      class = "btn-primary btn-lg",
      style = "width: 90%; margin-left: 5%;"
    )
  ),

  # --- Main Body ---
  dashboardBody(

    # Custom CSS
    tags$head(
      tags$style(HTML("
        .content-wrapper { background-color: #f4f6f9; }
        .info-box { min-height: 90px; }
        .box-header { background-color: #3c8dbc; color: white; }
        .progress-bar { background-color: #00a65a; }
      "))
    ),

    # Progress Indicator (hidden by default)
    shinybusy::add_busy_spinner(
      spin = "fading-circle",
      color = "#3c8dbc",
      position = "full-page"
    ),

    # Row 1: Status Cards
    fluidRow(
      # Data Status
      infoBoxOutput("data_status", width = 4),
      # Optimization Status
      infoBoxOutput("optimization_status", width = 4),
      # Download Status
      infoBoxOutput("download_status", width = 4)
    ),

    # Row 2: Main Results
    fluidRow(
      # Left: Data Summary
      box(
        title = "📊 Data Summary",
        status = "primary",
        solidHeader = TRUE,
        width = 6,

        # Conditional display
        conditionalPanel(
          condition = "output.data_loaded",
          tableOutput("data_summary")
        ),
        conditionalPanel(
          condition = "!output.data_loaded",
          p("Upload a parquet file to begin.", style = "color: #999;")
        )
      ),

      # Right: Optimization Results
      box(
        title = "🎯 Optimization Results",
        status = "success",
        solidHeader = TRUE,
        width = 6,

        conditionalPanel(
          condition = "output.optimization_complete",
          tableOutput("optimization_summary"),
          hr(),
          fluidRow(
            column(6, downloadButton("download_csv", "⬇️ CSV Method",
                                     class = "btn-success btn-block")),
            column(6, downloadButton("download_pdf", "📄 PDF Report",
                                     class = "btn-info btn-block"))
          )
        ),
        conditionalPanel(
          condition = "!output.optimization_complete",
          p("Run optimization to see results.", style = "color: #999;")
        )
      )
    ),

    # Row 3: Preview Table
    fluidRow(
      box(
        title = "📋 Window Preview (First 20 rows)",
        status = "info",
        solidHeader = TRUE,
        width = 12,
        collapsible = TRUE,
        collapsed = TRUE,

        DT::dataTableOutput("window_preview")
      )
    )
  )
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
    data_loaded = FALSE,
    optimization_complete = FALSE
  )

  # --- DPPP Preset Buttons ---
  observeEvent(input$preset_id, {
    updateSliderInput(session, "target_dppp", value = 1.5)
  })

  observeEvent(input$preset_balanced, {
    updateSliderInput(session, "target_dppp", value = 4.0)
  })

  observeEvent(input$preset_quant, {
    updateSliderInput(session, "target_dppp", value = 7.0)
  })

  # --- File Upload Handler ---
  observeEvent(input$parquet_file, {
    req(input$parquet_file)

    # Show processing notification
    showNotification("📁 Processing file...", id = "upload_progress", duration = NULL, type = "message")

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

      removeNotification("upload_progress")
      showNotification(
        paste("✅ Data loaded:", format(nrow(rv$validated_data$data), big.mark = ","), "precursors"),
        type = "message"
      )

    }, error = function(e) {
      cat("[Shiny] ERROR in file upload:", e$message, "\n")
      removeNotification("upload_progress")
      showNotification(paste("❌ Error:", e$message), type = "error", duration = 10)
      rv$data_loaded <- FALSE
    })
  })

  # --- Run Optimization ---
  observeEvent(input$run_optimization, {
    # Check if data is loaded
    if (is.null(rv$validated_data) || !rv$data_loaded) {
      showNotification("⚠️ Please upload a parquet file first!", type = "warning")
      return()
    }

    # Show processing notification
    showNotification("⚙️ Running optimization...", id = "opt_progress", duration = NULL, type = "message")

    tryCatch({
      cat("\n[Shiny] Starting optimization...\n")
      cat("[Shiny] Instrument:", input$instrument, "\n")
      cat("[Shiny] Target DPPP:", input$target_dppp, "\n")
      cat("[Shiny] Target Satisfaction:", input$target_satisfaction, "%\n")

      # Stage 2: Optimization Planning
      cat("[Shiny] Running plan_optimization()...\n")
      rv$optimization_plan <- plan_optimization(
        validated_data = rv$validated_data,
        instrument_preset = input$instrument,
        target_dppp = input$target_dppp,
        target_satisfaction = input$target_satisfaction / 100
      )
      cat("[Shiny] plan_optimization() completed!\n")

      # Stage 3: Window Optimization (Smoothing strategy - GLOBAL optimization)
      cat("[Shiny] Running optimize_windows()...\n")
      cat("[Shiny] RT Bin Width:", input$rt_bin_width, "min\n")
      rv$optimized_windows <- optimize_windows(
        validated_data = rv$validated_data,
        optimization_plan = rv$optimization_plan,
        mz_strategy = "smoothing",
        window_mode = "variable",
        rt_bin_width_min = input$rt_bin_width
      )
      cat("[Shiny] optimize_windows() completed!\n")

      rv$optimization_complete <- TRUE

      removeNotification("opt_progress")
      showNotification(
        paste("✅ Optimization complete:", nrow(rv$optimized_windows$windows), "windows generated"),
        type = "message"
      )

    }, error = function(e) {
      cat("[Shiny] ERROR in optimization:", e$message, "\n")
      removeNotification("opt_progress")
      showNotification(paste("❌ Error:", e$message), type = "error", duration = 10)
      rv$optimization_complete <- FALSE
    })
  })

  # --- Output: Data Status Info Box ---
  output$data_status <- renderInfoBox({
    if (rv$data_loaded && !is.null(rv$validated_data)) {
      n_precursors <- nrow(rv$validated_data$data)
      infoBox(
        title = "Precursors",
        value = format(n_precursors, big.mark = ","),
        icon = icon("database"),
        color = "green"
      )
    } else {
      infoBox(
        title = "Data Status",
        value = "No data",
        icon = icon("upload"),
        color = "yellow"
      )
    }
  })

  # --- Output: Optimization Status Info Box ---
  output$optimization_status <- renderInfoBox({
    if (rv$optimization_complete && !is.null(rv$optimized_windows)) {
      n_windows <- nrow(rv$optimized_windows$windows)
      infoBox(
        title = "Windows",
        value = n_windows,
        icon = icon("th"),
        color = "blue"
      )
    } else {
      infoBox(
        title = "Optimization",
        value = "Pending",
        icon = icon("cogs"),
        color = "yellow"
      )
    }
  })

  # --- Output: Download Status Info Box ---
  output$download_status <- renderInfoBox({
    if (rv$optimization_complete) {
      infoBox(
        title = "Download",
        value = "Ready",
        icon = icon("download"),
        color = "green"
      )
    } else {
      infoBox(
        title = "Download",
        value = "Waiting",
        icon = icon("clock"),
        color = "yellow"
      )
    }
  })

  # --- Output: Conditional flags for UI ---
  output$data_loaded <- reactive({ rv$data_loaded })
  outputOptions(output, "data_loaded", suspendWhenHidden = FALSE)

  output$optimization_complete <- reactive({ rv$optimization_complete })
  outputOptions(output, "optimization_complete", suspendWhenHidden = FALSE)

  # --- Output: Data Summary Table ---
  output$data_summary <- renderTable({
    req(rv$validated_data)

    data <- rv$validated_data$data

    data.frame(
      Metric = c(
        "Total Precursors",
        "RT Range (min)",
        "m/z Range",
        "Median FWHM (sec)"
      ),
      Value = c(
        format(nrow(data), big.mark = ","),
        sprintf("%.1f - %.1f", min(data$RT.Start), max(data$RT.Start)),
        sprintf("%.1f - %.1f", min(data$Precursor.Mz), max(data$Precursor.Mz)),
        sprintf("%.2f", median(data$FWHM, na.rm = TRUE))
      )
    )
  })

  # --- Output: Optimization Summary Table ---
  output$optimization_summary <- renderTable({
    req(rv$optimized_windows)

    windows <- rv$optimized_windows$windows
    plan <- rv$optimization_plan
    params <- rv$optimized_windows$parameters

    data.frame(
      Metric = c(
        "Total Windows",
        "RT Bins",
        "RT Bin Width (min)",
        "Mean Width (Da)",
        "Coverage (%)",
        "Recommended Cycle Time (sec)"
      ),
      Value = c(
        nrow(windows),
        length(unique(windows$rt_segment_id)),
        sprintf("%.1f", params$rt_bin_width_min),
        sprintf("%.1f", mean(windows$window_width)),
        sprintf("%.1f%%", rv$optimized_windows$statistics$coverage_percentage),
        sprintf("%.2f", plan$required_cycle_time_sec)
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

  # --- Download Handler: CSV Method File ---
  output$download_csv <- downloadHandler(
    filename = function() {
      paste0("dia_method_", input$instrument, "_", Sys.Date(), ".csv")
    },
    content = function(file) {
      req(rv$optimized_windows, rv$validated_data)

      # Use existing export function from Stage 3
      export_windows_to_csv(
        optimized_windows = rv$optimized_windows,
        output_file = file,
        validated_data = rv$validated_data,
        optimization_plan = rv$optimization_plan,
        instrument_type = input$instrument,
        project_name = "shiny_export"
      )
    }
  )

  # --- Download Handler: PDF Report ---
  output$download_pdf <- downloadHandler(
    filename = function() {
      paste0("dia_report_", input$instrument, "_", Sys.Date(), ".pdf")
    },
    content = function(file) {
      req(rv$optimized_windows, rv$validated_data, rv$optimization_plan)

      showNotification("📄 Generating PDF report...", id = "pdf_progress",
                       duration = NULL, type = "message")

      tryCatch({
        cat("[Shiny] Generating PDF report...\n")

        # Generate core plots for PDF report
        plots <- list()

        # Plot 1: DPPP Comparison (그대로 유지)
        cat("[Shiny] Generating DPPP plot...\n")
        plots[[1]] <- plot_dppp_comparison(rv$optimization_plan, rv$validated_data)

        # Plot 2: Coverage Map (RT x m/z with optimization boundaries)
        cat("[Shiny] Generating coverage map...\n")
        plots[[2]] <- plot_density_with_mz_range(rv$optimized_windows, rv$validated_data)

        # Plot 3: m/z Normalized Density
        cat("[Shiny] Generating m/z normalized density plot...\n")
        plots[[3]] <- plot_mz_normalized_density(rv$optimized_windows, rv$validated_data)

        # Plot 4: Window Width Distribution
        cat("[Shiny] Generating window width distribution...\n")
        plots[[4]] <- plot_window_width_distribution(rv$optimized_windows, rv$validated_data)

        # Create PDF directly (no empty pages)
        cat("[Shiny] Creating PDF file...\n")
        pdf(file, width = 12, height = 8)

        # Title page
        grid::grid.newpage()
        grid::grid.text("DIA Window Optimization Report",
                        x = 0.5, y = 0.7,
                        gp = grid::gpar(fontsize = 24, fontface = "bold"))
        grid::grid.text(sprintf("Generated: %s", Sys.time()),
                        x = 0.5, y = 0.5,
                        gp = grid::gpar(fontsize = 14))
        grid::grid.text(sprintf("Instrument: %s | Windows: %d | Coverage: %.1f%%",
                                rv$optimization_plan$instrument$preset,
                                nrow(rv$optimized_windows$windows),
                                rv$optimized_windows$statistics$coverage_percentage),
                        x = 0.5, y = 0.4,
                        gp = grid::gpar(fontsize = 12))

        # Print each plot on its own page (no empty pages)
        for (i in seq_along(plots)) {
          if (!is.null(plots[[i]])) {
            # Check if it's a grob (grid object) or ggplot
            if (inherits(plots[[i]], "grob") || inherits(plots[[i]], "gtable")) {
              grid::grid.newpage()
              grid::grid.draw(plots[[i]])
            } else {
              print(plots[[i]])
            }
          }
        }

        dev.off()

        removeNotification("pdf_progress")
        cat("[Shiny] PDF report generated successfully!\n")

      }, error = function(e) {
        cat("[Shiny] ERROR generating PDF:", e$message, "\n")
        removeNotification("pdf_progress")
        showNotification(paste("❌ PDF Error:", e$message), type = "error", duration = 10)
      })
    }
  )
}

# =============================================================================
# Run Application
# =============================================================================

shinyApp(ui = ui, server = server)
