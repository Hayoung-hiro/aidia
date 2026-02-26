# ui_step1_data.R - Step 1: DATA & INSTRUMENT
# Upload, instrument configuration, cycle time, DPPP preview

step1_data_ui <- function() {
  tabItem(
    tabName = "data",

    # --- Upload Zone ---
    box(
      title = "Upload Data",
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
      helpText("Browse to select file. Configure instrument settings below, then review data.",
               style = "font-size: 11px; color: #7f8c8d;")
    ),

    # --- Instrument & Timing (always visible, independent of data upload) ---
    box(
      title = "Instrument & Timing",
      status = "primary",
      solidHeader = TRUE,
      width = 12,

      fluidRow(
        # Column 1: Instrument Selection
        column(3,
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

        # Column 2: MS1 Resolution (Orbitrap only)
        column(3,
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
          )
        ),

        # Column 3: MS2 Resolution (Orbitrap) / Astral MS2 IT
        column(3,
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
          )
        ),

        # Column 4: Window Count
        column(3,
          numericInput(
            inputId = "current_window_count",
            label = "MS2 Window Count",
            value = 40,
            min = 10,
            max = 500,
            step = 5
          ),
          helpText("Isolation windows per cycle",
                   style = "font-size: 11px; color: #7f8c8d;")
        )
      ),

      helpText(
        icon("info-circle"), " ",
        "Injection Time, Acquisition settings available in ",
        tags$strong("Strategy > Expert Settings"),
        style = "font-size: 11px; color: #7f8c8d; margin-top: 4px;"
      )
    ),

    # --- Shown after data upload ---
    conditionalPanel(
      condition = "output.data_loaded",

      # Cycle Time Calculation
      box(
        title = "Cycle Time Calculation",
        status = "info",
        solidHeader = TRUE,
        width = 12,

        h5("Based on Your Experiment Settings", style = "margin-top: 0; color: #2c3e50;"),
        fluidRow(
          column(6, tableOutput("cycle_time_detail_table")),
          column(6,
            h5("Cycle Time Breakdown"),
            uiOutput("cycle_time_visual"),
            hr(style = "margin: 10px 0;"),
            uiOutput("efficiency_detail")
          )
        )
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
            # FWHM Distribution (ridgeline by charge, top 3)
            h5("Peak Width (FWHM) Distribution", style = "margin-top: 0;"),
            plotOutput("fwhm_ridgeline", height = "220px")
          ),
          column(4,
            # DPPP at Different Cycle Times
            h5("DPPP at Different Cycle Times"),
            helpText(
              "Target: DPPP >= ",
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
      actionButton("btn_to_setup", "Continue to Strategy",
                   class = "btn-primary btn-lg",
                   icon = icon("arrow-right"))
    )
  )
}
