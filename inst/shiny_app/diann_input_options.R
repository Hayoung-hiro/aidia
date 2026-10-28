# Derive UI defaults from Stage 1 so changing the API default also changes the UI.
.shiny_diann_defaults <- function() {
  stage <- formals(aidia::create_validated_dataset)
  filters <- formals(getFromNamespace("filter_diann_quality", "aidia"))
  list(diann_aggregation = if (eval(stage$enable_replicate_consensus)) "consensus" else "pooled",
    diann_min_runs = if (is.null(eval(stage$min_replicates))) 0 else eval(stage$min_replicates),
    diann_quality_filters = eval(stage$apply_quality_filters),
    diann_q_value = eval(filters$q_value_threshold),
    diann_lib_q_value = eval(filters$lib_q_value_threshold),
    diann_global_q_value = eval(filters$global_q_value_threshold),
    diann_pg_q_value = eval(filters$pg_q_value_threshold),
    diann_global_filters = eval(filters$apply_empirical_lib_filter),
    diann_channel_filter = !is.null(eval(filters$channel_q_value_threshold)),
    diann_channel_q_value = if (is.null(eval(filters$channel_q_value_threshold))) 0.01 else eval(filters$channel_q_value_threshold))
}

.shiny_diann_arguments <- function(input) {
  defaults <- .shiny_diann_defaults()
  value <- function(id) if (id %in% names(input)) input[[id]] else defaults[[id]]
  aggregation <- value("diann_aggregation")
  if (length(aggregation) != 1L || !aggregation %in% c("consensus", "pooled")) stop("Choose a DIA-NN run combination method.")
  minimum <- if (identical(aggregation, "consensus")) value("diann_min_runs") else 0
  if (length(minimum) != 1L || !is.finite(minimum) || minimum < 0 || minimum != floor(minimum))
    stop("Minimum runs must be a whole number: 0 for automatic, or a positive count.")
  args <- list(enable_replicate_consensus = identical(aggregation, "consensus"),
    min_replicates = if (minimum == 0) NULL else minimum,
    apply_quality_filters = isTRUE(value("diann_quality_filters")))
  if (!args$apply_quality_filters) return(args)
  threshold <- function(id) {
    x <- value(id)
    if (length(x) != 1L || !is.finite(x) || x < 0 || x > 1)
      stop("Q-value thresholds must be numbers between 0 and 1.")
    x
  }
  c(args, list(q_value_threshold = threshold("diann_q_value"),
    lib_q_value_threshold = threshold("diann_lib_q_value"),
    pg_q_value_threshold = threshold("diann_pg_q_value"),
    apply_empirical_lib_filter = isTRUE(value("diann_global_filters")),
    global_q_value_threshold = if (isTRUE(value("diann_global_filters"))) threshold("diann_global_q_value") else NULL,
    channel_q_value_threshold = if (isTRUE(value("diann_channel_filter"))) threshold("diann_channel_q_value") else NULL))
}

diann_input_options_ui <- function() {
  defaults <- .shiny_diann_defaults()
  row <- .workflow_row
  threshold <- function(id, label) row(label,
    shiny::numericInput(id, NULL, value = defaults[[id]], min = 0, max = 1, step = 0.001))
  shiny::tagList(
    row("Combine runs", shiny::selectInput("diann_aggregation", NULL,
      choices = c("Precursor consensus (median)" = "consensus", "All detections" = "pooled"),
      selected = defaults$diann_aggregation)),
    shiny::conditionalPanel("input.diann_aggregation == 'consensus'",
      row("Minimum runs", shiny::numericInput("diann_min_runs", NULL,
        value = defaults$diann_min_runs, min = 0, step = 1)),
      shiny::p("0 uses half the runs remaining after quality filtering, rounded up. Consensus takes the median for each Precursor.Id. All detections keeps each run's observations after normal cleaning.")),
    shiny::tags$details(class = "config-more", shiny::tags$summary("DIA-NN quality filters"),
      shiny::checkboxInput("diann_quality_filters", "Apply Q-value filters", defaults$diann_quality_filters),
      shiny::conditionalPanel("input.diann_quality_filters",
        threshold("diann_q_value", "Q.Value"),
        threshold("diann_lib_q_value", "Lib.Q.Value"),
        threshold("diann_pg_q_value", "Protein-group Q"),
        shiny::checkboxInput("diann_global_filters", "Apply global filters", defaults$diann_global_filters),
        shiny::conditionalPanel("input.diann_global_filters", threshold("diann_global_q_value", "Global.Q.Value")),
        shiny::checkboxInput("diann_channel_filter", "Apply Channel.Q.Value filter (plexDIA)", defaults$diann_channel_filter),
        shiny::conditionalPanel("input.diann_channel_filter", threshold("diann_channel_q_value", "Channel.Q.Value"))),
      shiny::p("Filters apply only to columns present in the report. Protein-group Q applies to PG.Q.Value, Lib.PG.Q.Value, and (when global filters are enabled) Global.PG.Q.Value. These defaults match the existing DIA-NN loading pipeline. Change settings, then click Compute.")))
}

.shiny_diann_filter_summary <- function(options) {
  if (!isTRUE(options$apply_quality_filters)) return("Q-value filters: off")
  c(paste("Q.Value <=", options$q_value_threshold),
    paste("Lib.Q.Value <=", options$lib_q_value_threshold),
    paste("Protein-group Q <=", options$pg_q_value_threshold),
    if (isTRUE(options$apply_empirical_lib_filter))
      paste("Global filters: on; Global.Q.Value <=", options$global_q_value_threshold)
    else "Global filters: off",
    if (is.null(options$channel_q_value_threshold)) "Channel.Q.Value: off"
    else paste("Channel.Q.Value <=", options$channel_q_value_threshold),
    "Only columns present in the report are filtered.")
}

local_input_paths_ui <- function(prefix) {
  if (!isTRUE(getOption("aidia.shiny.local_files", FALSE))) return(NULL)
  shiny::tags$details(class = "config-more", shiny::tags$summary("Add by local path (shows full path)"),
    shiny::textAreaInput(paste0(prefix, "_local_paths"), "Full file path, one per line",
      placeholder = if (prefix == "ms1") "D:/data/run01/features.parquet" else "D:/data/report.parquet",
      rows = 3, width = "100%"),
    shiny::actionButton(paste0("add_", prefix, "_paths"), "Add paths"),
    shiny::p("Paths refer to the computer running AIDIA. Quoted paths copied from File Explorer are accepted. Browser uploads do not provide their original folder path."))
}
