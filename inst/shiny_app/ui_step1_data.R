# Step 1: the input report, its acquisition settings, and a sampling check.
step1_data_ui <- function() {
  help <- .workflow_help
  row <- .workflow_row
  section <- function(number, title, ...) .workflow_section("data", number, title, ...)
  parallel <- "input.instrument == 'astral' || input.instrument == 'astral_zoom'"
  sequential <- "input.instrument == 'qexactive' || input.instrument == 'qexactive_hfx' || input.instrument == 'exploris' || input.instrument == 'eclipse' || input.instrument == 'fusion_lumos'"
  auto_it <- function(ms) {
    div(class = "workflow-inline",
      checkboxInput(paste0(ms, "_it_auto"), "Auto max IT", value = TRUE),
      conditionalPanel(condition = paste0("!input.", ms, "_it_auto"),
        numericInput(paste0(ms, "_it_custom"), "Max IT (ms)", value = 50,
          min = 5, max = 500, step = 5)),
      conditionalPanel(condition = paste0("input.", ms, "_it_auto"),
        span(textOutput(paste0(ms, "_it_auto_value"), inline = TRUE), class = "workflow-inline-value")))
  }

  tabItem(tabName = "data",
    div(class = "configure-compact workflow-data",
      div(class = "workflow-heading",
        tags$p(class = "workflow-eyebrow", "STEP 1 OF 3"),
        h2("Prepare your data")),

      section("1", "Data file",
        row("DIA-NN report",
          fileInput("parquet_file", NULL, accept = c(".parquet"),
            placeholder = "Choose report.parquet", width = "100%"),
          info = help("DIA-NN report", p("Upload a DIA-NN report.parquet file, up to 500 MB. After validation, your data summary appears in the sidebar and peak sampling appears below.")))),

      section("2", "Input acquisition settings",
        div(class = "workflow-acquisition-grid",
          div(class = "workflow-acquisition-controls",
        row("Instrument",
          selectInput("instrument", "Instrument", choices = c(
            "Thermo Astral Zoom (270 Hz)" = "astral_zoom",
            "Thermo Astral (200 Hz)" = "astral",
            "Thermo Q Exactive (12 Hz)" = "qexactive",
            "Thermo Q Exactive HF-X (40 Hz)" = "qexactive_hfx",
            "Thermo Exploris 480 (40 Hz)" = "exploris",
            "Thermo Eclipse Tribrid (40 Hz)" = "eclipse",
            "Thermo Fusion Lumos (20 Hz)" = "fusion_lumos"), selected = "astral_zoom"),
          info = help("Input acquisition settings", p("Match these settings to the method used to acquire your uploaded report. They define the input cycle time used for comparison with the new method."))),
        row("MS1",
          conditionalPanel(condition = sequential, class = "workflow-inline",
            selectInput("ms1_resolution", "Resolution", choices = c(
              "15,000" = 15000, "30,000" = 30000, "60,000" = 60000,
              "120,000" = 120000, "240,000" = 240000, "480,000" = 480000), selected = 60000),
            auto_it("ms1")),
          conditionalPanel(condition = parallel,
            selectInput("astral_ms1_resolution", "Resolution (Orbitrap)", choices = c(
              "60,000" = 60000, "120,000" = 120000, "240,000" = 240000,
              "480,000" = 480000), selected = 240000)),
          info = help("MS1 resolution and injection time",
            p("Resolution is the Orbitrap MS1 setting, including for Astral instruments. Higher resolution increases transient duration."),
            p("For sequential instruments, Auto max IT matches maximum injection time to the transient. Turn Auto off to enter your input method's maximum injection time."))),
        row("MS2",
          conditionalPanel(condition = sequential, class = "workflow-inline",
            selectInput("ms2_resolution", "Resolution", choices = c(
              "7,500" = 7500, "15,000" = 15000, "30,000" = 30000, "45,000" = 45000,
              "60,000" = 60000, "120,000" = 120000, "240,000" = 240000), selected = 15000),
            auto_it("ms2")),
          conditionalPanel(condition = parallel,
            sliderInput("astral_ms2_it", "Injection time (ms)", min = 2, max = 40,
              value = 3, step = 0.5, post = " ms", ticks = FALSE)),
          info = help("MS2 resolution and injection time",
            p("Sequential instruments use the selected MS2 resolution and maximum injection time. Auto max IT matches the transient duration."),
            p("For Astral, use the slider to match MS2 injection time to your input method. Longer injection times change the calculated acquisition speed."))),
        row("Input windows",
          numericInput("current_window_count", "Per cycle", value = 40, min = 10, max = 500, step = 5),
          info = help("Input windows per cycle", p("Enter the number of windows in the method that produced your report. Configure the new window count in step 2."))),
        tags$details(class = "config-more",
          tags$summary("Original fixed m/z range (optional)"),
          row("Original m/z range",
            numericInput("original_mz_min", "Start", value = 400, min = 1, step = 1),
            numericInput("original_mz_max", "End", value = 1000, min = 1, step = 1),
            info = help("Original fixed method",
              p("Describe the input method's constant m/z range. The reference uses your input window count, with equal widths and no overlap. Defaults to 400-1000 m/z."),
              p("These settings define the comparison reference; they do not restrict optimization."))),
          uiOutput("original_fixed_width"))),
          div(class = "config-preview workflow-acquisition-preview",
            div(class = "config-preview-heading", tags$strong("Acquisition preview"),
              help("Acquisition preview",
                p("Updates from the input acquisition settings. For parallel instruments, the longer of MS1 and the MS2 window sequence determines cycle time. Sequential instruments add their durations."),
                p("After upload, estimated DPPP uses your median peak width and this input cycle time. This is the input method preview; configure the new method in step 2."))),
            uiOutput("acquisition_preview"))
        )),

      section("3", "Peak sampling check",
        conditionalPanel(condition = "!output.data_loaded",
          div(class = "workflow-empty", icon("chart-area"),
            span("Upload a report to see peak sampling."))),
        conditionalPanel(condition = "output.data_loaded",
          div(class = "workflow-check-grid",
            div(class = "workflow-pane",
              .workflow_subheading("Peak width distribution",
                help("Peak width (FWHM)", p("The distribution of full widths at half maximum in your report. Peak widths and cycle time determine how many data points sample each peak."))),
              div(class = "workflow-plot-scroll", plotOutput("fwhm_ridgeline", height = "240px"))),
            div(class = "workflow-pane",
              .workflow_subheading("Sampling by cycle time",
                help("Peak sampling (DPPP)", p("DPPP is the number of data points across a peak. Satisfaction is the percentage of peaks meeting your target. The target and required percentage are configured in step 2."))),
              div(class = "workflow-context", "Target DPPP: ", textOutput("current_target_dppp", inline = TRUE)),
              div(class = "workflow-table-scroll", uiOutput("dppp_preview_table")))),
          div(class = "workflow-recommendation", uiOutput("dppp_recommendation")),
          tags$details(class = "config-more workflow-details",
            tags$summary("Timing details"),
            div(class = "workflow-check-grid",
              div(class = "workflow-pane workflow-table-scroll", tableOutput("cycle_time_detail_table")),
              div(class = "workflow-pane",
                .workflow_subheading("Cycle time breakdown"),
                uiOutput("cycle_time_visual"), uiOutput("efficiency_detail"))))
        )),
      uiOutput("prepare_navigation_feedback"),
      div(class = "wizard-nav wizard-nav-right",
        actionButton("btn_to_setup", "Continue to window settings",
          class = "btn-primary", icon = icon("arrow-right")))
    )
  )
}
