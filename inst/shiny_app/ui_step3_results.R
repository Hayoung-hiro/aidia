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

      # --- Row 4: Precursor Distribution + Temporal Density ---
      fluidRow(
        box(
          title = "Precursor Distribution Across Windows",
          status = "primary",
          solidHeader = TRUE,
          width = 12,
          plotOutput("plot_precursors_per_window", height = "400px")
        )
      ),
      fluidRow(
        box(
          title = "Precursor Temporal Density (Co-Elution Proxy)",
          status = "info",
          solidHeader = TRUE,
          width = 12,
          collapsible = TRUE,
          collapsed = FALSE,
          plotOutput("plot_temporal_density", height = "400px"),
          tags$div(
            class = "text-muted", style = "font-size: 11px; padding: 8px 0;",
            icon("info-circle"),
            " Based on identified precursors only (lower bound). ",
            "Higher density = more co-eluting precursors = harder deconvolution. ",
            "Values are relative — useful for comparing strategies, not as absolute co-isolation counts."
          )
        )
      ),

      # --- Row 5: Detailed Table + Window Preview (collapsed) ---
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

      # --- Row 6: Downloads ---
      fluidRow(
        # Method File Download (left)
        box(
          title = "Download Method File",
          status = "success",
          solidHeader = TRUE,
          width = 8,

          fluidRow(
            column(3,
              textInput("sample_name", "Sample/Project Name",
                        value = "", placeholder = "e.g., HeLa_digest")
            ),
            column(3,
              textInput("condition", "Condition/Note",
                        value = "", placeholder = "e.g., 60min_gradient")
            ),
            column(3,
              selectInput("export_format", "Export Format",
                choices = c(
                  "Thermo Targeted Mass List" = "thermo",
                  "Center Mass List" = "center_mass",
                  "m/z Range List" = "mz_range"
                ),
                selected = "thermo"
              )
            ),
            column(3,
              div(style = "padding-top: 25px;",
                downloadButton("download_method", "Download Method",
                               class = "btn-success btn-block")
              )
            )
          ),
          # Format preview
          uiOutput("export_format_preview")
        ),
        # Other Downloads (right)
        box(
          title = "Other Downloads",
          status = "secondary",
          solidHeader = TRUE,
          width = 4,
          div(style = "display: flex; flex-direction: column; gap: 8px;",
            downloadButton("download_pdf", "PDF Report",
                           class = "btn-info btn-block"),
            downloadButton("download_batch_zip", "Batch Export (5 strategies, ZIP)",
                           class = "btn-warning btn-block")
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
