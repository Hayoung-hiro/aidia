# ui_step1_data.R - Step 1: DATA & INSTRUMENT
# Upload, instrument configuration, cycle time, DPPP preview

step1_data_ui <- function() {
  tabItem(
    tabName = "data",

    # --- Row 1: Upload + Instrument side-by-side (2x1 layout, equal height) ---
    fluidRow(
      class = "equal-height-row",
      box(
        title = "Upload Data",
        status = "primary",
        solidHeader = TRUE,
        width = 4,

        div(
          style = "text-align: center; margin-bottom: 12px;",
          icon("cloud-upload-alt", class = "upload-icon"),
          tags$p("DIA-NN Parquet Report", class = "text-muted", style = "margin: 4px 0 0 0;")
        ),
        div(
          class = "upload-zone",
          fileInput(
            inputId = "parquet_file",
            label = NULL,
            accept = c(".parquet"),
            placeholder = "No file selected..."
          )
        ),
        helpText("Browse or drag to upload DIA-NN report",
                 style = "font-size: 11px; text-align: center;")
      ),

      # --- Instrument & Timing (always visible, independent of data upload) ---
      box(
        title = "Instrument & Timing",
        status = "warning",
        solidHeader = TRUE,
        width = 8,

      fluidRow(
        class = "instrument-row",
        # Column 1: Instrument Selection
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
          )
        ),

        # Column 2: MS1 Resolution (Orbitrap sequential + Astral parallel)
        column(3, class = "instrument-col-conditional",
          # Orbitrap sequential instruments: full MS1 resolution range
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
          # Astral instruments: MS1 on Orbitrap (typical 120K-240K)
          conditionalPanel(
            condition = "input.instrument == 'astral' || input.instrument == 'astral_zoom'",
            selectInput(
              inputId = "astral_ms1_resolution",
              label = "MS1 Resolution (Orbitrap)",
              choices = c(
                "60,000" = 60000,
                "120,000" = 120000,
                "240,000" = 240000,
                "480,000" = 480000
              ),
              selected = 240000
            ),
            helpText("Astral MS1 acquired on Orbitrap analyzer",
                     style = "font-size: 10px;")
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
            condition = "input.instrument == 'astral' || input.instrument == 'astral_zoom'",
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
                     style = "font-size: 10px;")
          )
        ),

        # Column 4: Window Count
        column(2,
          numericInput(
            inputId = "current_window_count",
            label = "MS2 Window Count",
            value = 40,
            min = 10,
            max = 500,
            step = 5
          ),
          helpText("Isolation windows per cycle",
                   style = "font-size: 11px;")
        )
      ),

      # --- Injection Time (Orbitrap only) ---
      conditionalPanel(
        condition = "input.instrument == 'qexactive' || input.instrument == 'qexactive_hfx' || input.instrument == 'exploris' || input.instrument == 'eclipse' || input.instrument == 'fusion_lumos'",
        hr(style = "margin: 8px 0;"),
        fluidRow(
          column(4,
            tags$label("MS1 Max IT", class = "control-label"),
            div(
              style = "display: flex; gap: 8px; align-items: center;",
              checkboxInput("ms1_it_auto", "Auto", value = TRUE, width = "55px"),
              conditionalPanel(
                condition = "!input.ms1_it_auto",
                div(
                  style = "display: flex; align-items: center; gap: 4px;",
                  numericInput("ms1_it_custom", NULL, value = 50, min = 5, max = 500, step = 5, width = "90px"),
                  span("ms", class = "unit-label")
                )
              ),
              conditionalPanel(
                condition = "input.ms1_it_auto",
                span(textOutput("ms1_it_auto_value", inline = TRUE),
                     class = "text-accent", style = "font-weight: 600; font-size: 12px;")
              )
            )
          ),
          column(4,
            tags$label("MS2 Max IT", class = "control-label"),
            div(
              style = "display: flex; gap: 8px; align-items: center;",
              checkboxInput("ms2_it_auto", "Auto", value = TRUE, width = "55px"),
              conditionalPanel(
                condition = "!input.ms2_it_auto",
                div(
                  style = "display: flex; align-items: center; gap: 4px;",
                  numericInput("ms2_it_custom", NULL, value = 50, min = 5, max = 500, step = 5, width = "90px"),
                  span("ms", class = "unit-label")
                )
              ),
              conditionalPanel(
                condition = "input.ms2_it_auto",
                span(textOutput("ms2_it_auto_value", inline = TRUE),
                     class = "text-accent", style = "font-weight: 600; font-size: 12px;")
              )
            )
          ),
          column(4,
            div(style = "padding-top: 20px;",
              helpText("Auto = T_transient (Sweet Spot, 100% efficiency)",
                       style = "font-size: 10px;")
            )
          )
        )
      )
    )   # end Instrument box
    ),  # end fluidRow (Upload + Instrument)

    # --- Shown after data upload ---
    conditionalPanel(
      condition = "output.data_loaded",

      # DPPP Quick Preview (FIRST — overview before details)
      fluidRow(
        box(
          title = "DPPP Quick Preview",
          status = "info",
          solidHeader = TRUE,
          width = 12,
          collapsible = TRUE,

          fluidRow(
            class = "equal-height-row dppp-preview-section",
            column(4,
              tags$h4("Peak Width (FWHM) Distribution", class = "section-title"),
              plotOutput("fwhm_ridgeline", height = "240px")
            ),
            column(4,
              tags$h4("DPPP at Different Cycle Times", class = "section-title"),
              tags$p(
                class = "section-subtitle",
                "Target: DPPP >= ",
                textOutput("current_target_dppp", inline = TRUE)
              ),
              uiOutput("dppp_preview_table")
            ),
            column(4,
              tags$h4("Recommendation", class = "section-title"),
              uiOutput("dppp_recommendation")
            )
          )
        )
      ),

      # Cycle Time Calculation (SECOND — details after overview)
      fluidRow(
        box(
          title = "Cycle Time Calculation",
          status = "success",
          solidHeader = TRUE,
          width = 12,

          tags$h4("Based on Your Experiment Settings", class = "section-title"),
          fluidRow(
            column(6, tableOutput("cycle_time_detail_table")),
            column(6,
              tags$h4("Cycle Time Breakdown", class = "section-title"),
              uiOutput("cycle_time_visual"),
              hr(style = "margin: 10px 0;"),
              uiOutput("efficiency_detail")
            )
          )
        )
      )
    ),

    # --- Placeholder when no data ---
    conditionalPanel(
      condition = "!output.data_loaded",
      div(
        class = "placeholder-section",
        icon("cloud-upload-alt", class = "placeholder-icon"),
        h4("Upload a DIA-NN parquet file to begin"),
        p("Supported format: .parquet (DIA-NN report output)")
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
