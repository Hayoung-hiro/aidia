# ui_step3_results.R - Step 3: RESULTS (Optimization Output)

step3_results_ui <- function() {
  tabItem(
    tabName = "results",

    # --- Shown after optimization ---
    conditionalPanel(
      condition = "output.optimization_complete",

      # --- Row 1: Status bar (compact, replaces full callout) ---
      div(
        class = "results-status-bar",
        icon("check-circle", class = "text-semantic-success"),
        tags$strong(" Optimization Complete"),
        tags$span(class = "text-muted", style = "margin-left: 12px;",
                  uiOutput("results_status_text", inline = TRUE))
      ),

      # --- Row 2: Summary KPIs ---
      fluidRow(
        class = "equal-height-row",
        valueBoxOutput("summary_box_cycle_time", width = 4),
        valueBoxOutput("summary_box_dppp", width = 4),
        valueBoxOutput("summary_box_windows", width = 4)
      ),

      # --- Row 3: Before/After + m/z Summary (3-column layout) ---
      fluidRow(
        class = "equal-height-row",
        box(
          title = "BEFORE (Input Data)",
          status = "primary",
          solidHeader = TRUE,
          width = 4,
          uiOutput("before_summary")
        ),
        box(
          title = "AFTER (Optimized)",
          status = "success",
          solidHeader = TRUE,
          width = 4,
          uiOutput("after_summary")
        ),
        box(
          title = "m/z Range Summary",
          status = "info",
          solidHeader = TRUE,
          width = 4,
          uiOutput("mz_range_summary")
        )
      ),

      # --- Row 4: Detailed Table + Window Preview (collapsed) ---
      fluidRow(
        box(
          title = "Detailed Results",
          status = "secondary",
          solidHeader = FALSE,
          width = 12,
          collapsible = TRUE,
          collapsed = TRUE,
          tableOutput("optimization_summary")
        )
      ),
      fluidRow(
        box(
          title = "Window Preview",
          status = "secondary",
          solidHeader = FALSE,
          width = 12,
          collapsible = TRUE,
          collapsed = TRUE,
          DT::dataTableOutput("window_preview")
        )
      ),

      # --- Row 5: Precursor Distribution Plot (collapsed) ---
      fluidRow(
        box(
          title = "Precursor Distribution Across Windows",
          status = "secondary",
          solidHeader = FALSE,
          width = 12,
          collapsible = TRUE,
          collapsed = TRUE,
          plotOutput("plot_precursors_per_window", height = "400px")
        )
      ),

      # --- Row 6: Downloads (expanded with format options) ---
      fluidRow(
        box(
          title = "Downloads",
          status = "success",
          solidHeader = TRUE,
          width = 12,

          fluidRow(
            column(3,
              textInput("sample_name", "Sample/Project Name",
                        value = "", placeholder = "e.g., HeLa_digest")
            ),
            column(3,
              textInput("condition", "Condition/Note",
                        value = "", placeholder = "e.g., 60min_gradient")
            ),
            column(6,
              div(style = "padding-top: 25px;",
                div(style = "display: flex; gap: 8px; flex-wrap: wrap;",
                  downloadButton("download_csv", "Thermo CSV",
                                 class = "btn-success"),
                  downloadButton("download_center_mass", "Center Mass",
                                 class = "btn-outline-success"),
                  downloadButton("download_mz_range", "m/z Range",
                                 class = "btn-outline-success"),
                  downloadButton("download_pdf", "PDF Report",
                                 class = "btn-info"),
                  downloadButton("download_batch_zip", "Batch Export (ZIP)",
                                 class = "btn-warning")
                )
              )
            )
          )
        )
      )
    ),

    # --- Placeholder when no results ---
    conditionalPanel(
      condition = "!output.optimization_complete",
      div(
        class = "placeholder-section",
        icon("cogs", class = "placeholder-icon"),
        h4("Run optimization to see results"),
        p("Configure your settings in the Strategy step, then run optimization.")
      )
    ),

    # Navigation
    div(
      class = "wizard-nav wizard-nav-between",
      actionButton("btn_to_setup_back", "Back to Strategy",
                   class = "btn-default btn-lg",
                   icon = icon("arrow-left")),
      actionButton("btn_new_analysis", "New Analysis",
                   class = "btn-primary btn-lg",
                   icon = icon("redo"))
    )
  )
}
