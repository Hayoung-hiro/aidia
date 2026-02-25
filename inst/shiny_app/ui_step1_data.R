# ui_step1_data.R - Step 1: DATA (File Upload + Data Confirmation)

step1_data_ui <- function() {
  tabItem(
    tabName = "data",

    # Upload & Naming (always visible)
    box(
      title = "Upload & Sample Naming",
      status = "primary",
      solidHeader = TRUE,
      width = 12,

      fluidRow(
        column(12,
          div(
            class = "upload-zone",
            fileInput(
              inputId = "parquet_file",
              label = "Upload DIA-NN Parquet File",
              accept = c(".parquet"),
              placeholder = "DIA-NN report..."
            )
          )
        )
      ),
      fluidRow(
        column(6,
          textInput(
            inputId = "sample_name",
            label = "Sample/Project Name",
            value = "",
            placeholder = "e.g., HeLa_digest"
          )
        ),
        column(6,
          textInput(
            inputId = "condition",
            label = "Condition/Note",
            value = "",
            placeholder = "e.g., 60min_gradient"
          )
        )
      ),
      helpText("Used in output file names. Leave blank to use defaults.",
               style = "font-size: 11px; color: #7f8c8d;")
    ),

    # --- Shown after data upload ---
    conditionalPanel(
      condition = "output.data_loaded",

      # Status Info Boxes
      fluidRow(
        bs4InfoBoxOutput("data_status", width = 4),
        bs4InfoBoxOutput("optimization_status", width = 4),
        bs4InfoBoxOutput("download_status", width = 4)
      ),

      # DPPP Quick Preview
      box(
        title = "DPPP Quick Preview",
        status = "warning",
        solidHeader = TRUE,
        width = 12,
        collapsible = TRUE,

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

      # Data Summary & Cycle Time Detail
      fluidRow(
        class = "equal-height-row",
        # Left: Data Summary
        box(
          title = "Data Summary",
          status = "primary",
          solidHeader = TRUE,
          width = 6,
          height = "100%",
          tableOutput("data_summary")
        ),

        # Right: Cycle Time Calculation Details
        box(
          title = "Cycle Time Calculation",
          status = "info",
          solidHeader = TRUE,
          width = 6,
          height = "100%",

          h5("Based on Your Experiment Settings", style = "margin-top: 0; color: #2c3e50;"),
          tableOutput("cycle_time_detail_table"),
          hr(style = "margin: 10px 0;"),

          h5("Cycle Time Breakdown"),
          uiOutput("cycle_time_visual"),
          hr(style = "margin: 10px 0;"),

          uiOutput("efficiency_detail")
        )
      )
    ),

    # --- Placeholder when no data ---
    conditionalPanel(
      condition = "!output.data_loaded",
      div(
        style = "text-align: center; padding: 60px 20px;",
        icon("cloud-upload-alt", style = "font-size: 64px; color: #bdc3c7; margin-bottom: 20px;"),
        h4("Upload a DIA-NN parquet file to begin",
           style = "color: #7f8c8d; font-weight: 400;"),
        p("Supported format: .parquet (DIA-NN report output)",
          style = "color: #95a5a6; font-size: 13px;")
      )
    ),

    # Navigation
    div(
      class = "wizard-nav wizard-nav-right",
      actionButton("btn_to_setup", "Continue to Setup",
                   class = "btn-primary btn-lg",
                   icon = icon("arrow-right"))
    )
  )
}
