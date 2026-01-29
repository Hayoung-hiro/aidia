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
    div(
      style = "display: flex; gap: 4px; padding: 0 15px; margin-top: -5px;",
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
    ),

    br(),

    # m/z Optimization Strategy (NEW)
    selectInput(
      inputId = "mz_strategy",
      label = "m/z Strategy",
      choices = c(
        "Quantile (Recommended)" = "quantile",
        "Smoothing (GLOBAL)" = "smoothing",
        "Coverage (Conservative)" = "coverage",
        "Outlier (Robust)" = "outlier"
      ),
      selected = "quantile"
    ),
    helpText("Quantile: Fast & robust. Smoothing: Best for long gradients.",
             style = "font-size: 11px; color: #bdc3c7; padding: 0 15px;"),

    br(),

    # Auto RT Bin Width Checkbox (NEW)
    checkboxInput(
      inputId = "auto_rt_bin",
      label = "Auto RT Bin Width",
      value = TRUE
    ),
    helpText("Auto-adjusts bin width for selected strategy.",
             style = "font-size: 11px; color: #bdc3c7; padding: 0 15px;"),

    # RT Bin Width (conditionally shown)
    conditionalPanel(
      condition = "!input.auto_rt_bin",
      sliderInput(
        inputId = "rt_bin_width",
        label = "Manual RT Bin Width (min)",
        min = 1,
        max = 15,
        value = 5,
        step = 0.5,
        post = " min"
      ),
      helpText("Controls window grouping. Smaller = more RT segments.",
               style = "font-size: 11px; color: #bdc3c7; padding: 0 15px;")
    ),

    br(),

    # Custom IT Override (Orbitrap only) - NEW
    conditionalPanel(
      condition = "input.instrument == 'qexactive' || input.instrument == 'qexactive_hfx' || input.instrument == 'exploris' || input.instrument == 'eclipse' || input.instrument == 'fusion_lumos'",
      checkboxInput(
        inputId = "use_custom_it",
        label = "Custom Injection Time",
        value = FALSE
      ),
      conditionalPanel(
        condition = "input.use_custom_it",
        sliderInput(
          inputId = "custom_it_ms",
          label = "Injection Time (ms)",
          min = 5,
          max = 200,
          value = 50,
          step = 5,
          post = " ms"
        ),
        helpText("Override Auto IT (Sweet Spot). Higher IT = better sensitivity, fewer windows.",
                 style = "font-size: 11px; color: #bdc3c7; padding: 0 15px;")
      ),
      conditionalPanel(
        condition = "!input.use_custom_it",
        helpText("Auto IT: IT = T_transient (100% efficiency, max windows)",
                 style = "font-size: 11px; color: #1abc9c; padding: 0 15px;")
      )
    ),

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
      infoBoxOutput("data_status", width = 4),
      # Optimization Status
      infoBoxOutput("optimization_status", width = 4),
      # Download Status
      infoBoxOutput("download_status", width = 4)
    ),

    # Row 2: Data Summary + DPPP Preview
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

      # Right: DPPP Quick Preview (NEW)
      box(
        title = "⚡ DPPP Quick Preview",
        status = "warning",
        solidHeader = TRUE,
        width = 6,

        conditionalPanel(
          condition = "output.data_loaded",
          # FWHM Summary
          h5("Peak Width (FWHM)", style = "margin-top: 0;"),
          tableOutput("fwhm_summary"),
          hr(style = "margin: 10px 0;"),
          # DPPP at Different Cycle Times
          h5("DPPP at Different Cycle Times"),
          tableOutput("dppp_preview_table"),
          hr(style = "margin: 10px 0;"),
          # Recommendation
          uiOutput("dppp_recommendation")
        ),
        conditionalPanel(
          condition = "!output.data_loaded",
          p("Upload data to see DPPP preview.", style = "color: #999;")
        )
      )
    ),

    # Row 3: Optimization Results
    fluidRow(
      box(
        title = "🎯 Optimization Results",
        status = "success",
        solidHeader = TRUE,
        width = 12,

        conditionalPanel(
          condition = "output.optimization_complete",
          fluidRow(
            column(6, tableOutput("optimization_summary")),
            column(6,
              h5("Downloads", style = "margin-top: 0;"),
              fluidRow(
                column(6, downloadButton("download_csv", "⬇️ CSV Method",
                                         class = "btn-success btn-block")),
                column(6, downloadButton("download_pdf", "📄 PDF Report",
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
    dppp_preview = NULL,
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
      cat("[Shiny] m/z Strategy:", input$mz_strategy, "\n")

      # Log IT mode for Orbitrap instruments
      is_orbitrap <- input$instrument %in% c("qexactive", "qexactive_hfx", "exploris", "eclipse", "fusion_lumos")
      if (is_orbitrap) {
        if (!is.null(input$use_custom_it) && input$use_custom_it) {
          cat("[Shiny] IT Mode: CUSTOM (", input$custom_it_ms, " ms)\n", sep = "")
        } else {
          cat("[Shiny] IT Mode: AUTO (Sweet Spot, IT = T_transient)\n")
        }
      }

      # Stage 2: Optimization Planning
      cat("[Shiny] Running plan_optimization()...\n")

      # Determine Custom IT override (Orbitrap only)
      ms2_time_override_sec <- NULL
      if (!is.null(input$use_custom_it) && input$use_custom_it) {
        ms2_time_override_sec <- input$custom_it_ms / 1000  # ms to sec
        cat("[Shiny] Custom IT Override:", input$custom_it_ms, "ms\n")
      } else {
        cat("[Shiny] Using Auto IT (Sweet Spot mode)\n")
      }

      rv$optimization_plan <- plan_optimization(
        validated_data = rv$validated_data,
        instrument_preset = input$instrument,
        target_dppp = input$target_dppp,
        target_satisfaction = input$target_satisfaction / 100,
        ms2_time_override = ms2_time_override_sec
      )
      cat("[Shiny] plan_optimization() completed!\n")

      # Determine RT bin width (auto or manual)
      if (input$auto_rt_bin) {
        # Calculate adaptive RT bin width based on strategy and gradient length
        rt_range <- range(rv$validated_data$data$RT.Start, na.rm = TRUE)
        adaptive_result <- calculate_adaptive_rt_bin_width(
          rt_range = rt_range,
          mz_strategy = input$mz_strategy,
          target_min_bins = 5
        )
        rt_bin_width_final <- adaptive_result$bin_width
        cat("[Shiny] AUTO RT Bin Width:", rt_bin_width_final, "min")
        cat(" (", adaptive_result$n_bins, " bins for ", input$mz_strategy, " strategy)\n", sep = "")

        # Show notification about auto-adjustment
        showNotification(
          sprintf("Auto RT bin: %.1f min (%d bins)", rt_bin_width_final, adaptive_result$n_bins),
          type = "message", duration = 3
        )
      } else {
        rt_bin_width_final <- input$rt_bin_width
        cat("[Shiny] Manual RT Bin Width:", rt_bin_width_final, "min\n")
      }

      # Stage 3: Window Optimization with selected m/z strategy
      cat("[Shiny] Running optimize_windows()...\n")
      cat("[Shiny] m/z Strategy:", input$mz_strategy, "\n")
      rv$optimized_windows <- optimize_windows(
        validated_data = rv$validated_data,
        optimization_plan = rv$optimization_plan,
        mz_strategy = input$mz_strategy,
        window_mode = "variable",
        rt_bin_width_min = rt_bin_width_final
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
    # Guard clause: return "waiting" state early if no data loaded
    if (!rv$data_loaded || is.null(rv$validated_data)) {
      return(infoBox(
        title = "Data Status",
        value = "Waiting",
        subtitle = "Upload parquet file",
        icon = icon("cloud-upload-alt"),
        color = "yellow",
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

    infoBox(
      title = "Precursors Loaded",
      value = format(n_precursors, big.mark = ","),
      subtitle = gradient_len,
      icon = icon("check-circle"),
      color = "green",
      fill = TRUE
    )
  })

  # --- Output: Optimization Status Info Box ---
  output$optimization_status <- renderInfoBox({
    # Guard clause: return "pending" state early if not optimized
    if (!rv$optimization_complete || is.null(rv$optimized_windows)) {
      return(infoBox(
        title = "Optimization",
        value = "Pending",
        subtitle = "Configure and run",
        icon = icon("cogs"),
        color = "yellow",
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

    infoBox(
      title = "Windows Generated",
      value = n_windows,
      subtitle = coverage,
      icon = icon("layer-group"),
      color = "blue",
      fill = TRUE
    )
  })

  # --- Output: Download Status Info Box ---
  output$download_status <- renderInfoBox({
    # Guard clause: return "waiting" state early if not ready
    if (!rv$optimization_complete) {
      return(infoBox(
        title = "Export",
        value = "Waiting",
        subtitle = "Run optimization first",
        icon = icon("hourglass-half"),
        color = "yellow",
        fill = TRUE
      ))
    }

    infoBox(
      title = "Export Ready",
      value = "Download",
      subtitle = "CSV & PDF available",
      icon = icon("file-download"),
      color = "green",
      fill = TRUE
    )
  })

  # --- Output: Conditional flags for UI ---
  output$data_loaded <- reactive({ rv$data_loaded })
  outputOptions(output, "data_loaded", suspendWhenHidden = FALSE)

  output$optimization_complete <- reactive({ rv$optimization_complete })
  outputOptions(output, "optimization_complete", suspendWhenHidden = FALSE)

  # --- Output: DPPP Quick Preview (NEW) ---
  output$fwhm_summary <- renderTable({
    req(rv$dppp_preview)
    fwhm <- rv$dppp_preview$fwhm_stats
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
    req(rv$dppp_preview)
    preview <- rv$dppp_preview$dppp_preview
    data.frame(
      `Cycle Time` = sprintf("%.1f sec", preview$cycle_time_sec),
      `DPPP (median)` = sprintf("%.1f", preview$dppp_median),
      `Satisfaction` = sprintf("%.0f%%", preview$satisfaction_pct),
      check.names = FALSE
    )
  }, striped = TRUE, hover = TRUE, spacing = "s")

  output$dppp_recommendation <- renderUI({
    req(rv$dppp_preview)
    rec_ct <- rv$dppp_preview$recommended_cycle_time
    target <- rv$dppp_preview$target_dppp

    tags$div(
      class = "recommendation-box",
      tags$div(
        style = "display: flex; align-items: center; gap: 8px;",
        icon("lightbulb", style = "color: #1abc9c; font-size: 18px;"),
        tags$strong("Recommendation", style = "color: #2c3e50;")
      ),
      tags$p(
        style = "margin: 8px 0 0 0; color: #34495e;",
        sprintf("For DPPP ≥ %.1f with 85%% satisfaction, use cycle time ≤ ", target),
        tags$strong(sprintf("%.2f sec", rec_ct), style = "color: #16a085;")
      )
    )
  })

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

    # Determine IT mode display
    is_orbitrap <- input$instrument %in% c("qexactive", "qexactive_hfx", "exploris", "eclipse", "fusion_lumos")
    it_mode_display <- if (is_orbitrap) {
      if (!is.null(input$use_custom_it) && input$use_custom_it) {
        sprintf("Custom (%d ms)", input$custom_it_ms)
      } else {
        "Auto (Sweet Spot)"
      }
    } else {
      "N/A (non-Orbitrap)"
    }

    data.frame(
      Metric = c(
        "Total Windows",
        "RT Bins",
        "RT Bin Width (min)",
        "IT Mode",
        "Mean Width (Da)",
        "Coverage (%)",
        "Recommended Cycle Time (sec)"
      ),
      Value = c(
        nrow(windows),
        length(unique(windows$rt_segment_id)),
        sprintf("%.1f", params$rt_bin_width_min),
        it_mode_display,
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
