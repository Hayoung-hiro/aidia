# ui_step3_results.R - Step 3: RESULTS (Optimization Output)

step3_results_ui <- function() {
  tabItem(
    tabName = "results",

    # --- Shown after optimization ---
    conditionalPanel(
      condition = "output.optimization_complete",

      # Status callout
      bs4Callout(
        title = "Optimization Complete",
        status = "success",
        width = 12,
        uiOutput("results_status_text")
      ),

      # Before/After Comparison Cards
      fluidRow(
        class = "equal-height-row",
        box(
          title = "BEFORE (Input Data)",
          status = "primary",
          solidHeader = TRUE,
          width = 6,
          uiOutput("before_summary")
        ),
        box(
          title = "AFTER (Optimized)",
          status = "success",
          solidHeader = TRUE,
          width = 6,
          uiOutput("after_summary")
        )
      ),

      # Detailed Results
      box(
        title = "Detailed Results",
        status = "info",
        solidHeader = FALSE,
        width = 12,
        collapsible = TRUE,

        fluidRow(
          column(6, tableOutput("optimization_summary")),
          column(6,
            h5("m/z Range Summary", style = "margin-top: 0; color: #2c3e50; font-weight: 600;"),
            uiOutput("mz_range_summary")
          )
        )
      ),

      # Window Preview
      box(
        title = "Window Preview",
        status = "info",
        solidHeader = TRUE,
        width = 12,
        collapsible = TRUE,
        collapsed = TRUE,

        DT::dataTableOutput("window_preview")
      ),

      # Downloads
      box(
        title = "Downloads",
        status = "success",
        solidHeader = FALSE,
        width = 12,

        # Sample/Project Naming (for output files)
        fluidRow(
          column(4,
            textInput(
              inputId = "sample_name",
              label = "Sample/Project Name",
              value = "",
              placeholder = "e.g., HeLa_digest"
            )
          ),
          column(4,
            textInput(
              inputId = "condition",
              label = "Condition/Note",
              value = "",
              placeholder = "e.g., 60min_gradient"
            )
          ),
          column(4,
            div(style = "padding-top: 25px;",
              helpText("Used in output file names. Leave blank for defaults.",
                       style = "font-size: 11px; color: #7f8c8d;")
            )
          )
        ),

        hr(),

        fluidRow(
          column(6,
            downloadButton("download_csv", "Download CSV Method File",
                           class = "btn-success btn-lg btn-block")
          ),
          column(6,
            downloadButton("download_pdf", "Download PDF Report",
                           class = "btn-info btn-lg btn-block")
          )
        )
      )
    ),

    # --- Placeholder when no results ---
    conditionalPanel(
      condition = "!output.optimization_complete",
      div(
        style = "text-align: center; padding: 60px 20px;",
        icon("cogs", style = "font-size: 64px; color: #bdc3c7; margin-bottom: 20px;"),
        h4("Run optimization to see results",
           style = "color: #7f8c8d; font-weight: 400;"),
        p("Configure your settings in the Strategy step, then run optimization.",
          style = "color: #95a5a6; font-size: 13px;")
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
