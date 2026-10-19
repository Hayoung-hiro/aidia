# Local source paths are recorded separately from session-owned working copies.
.shiny_upload_runs <- function(path, ms1) {
  column <- if (ms1) "run_name" else "Run"
  # Only read the run label column; validation and aggregation wait for Compute.
  tryCatch({
    data <- arrow::read_parquet(path, col_select = dplyr::any_of(column))
    runs <- sort(unique(as.character(data[[column]])))
    runs[!is.na(runs) & nzchar(runs)]
  }, error = function(e) character())
}

.shiny_local_uploads <- function(value) {
  paths <- trimws(strsplit(value %||% "", "[\r\n]+")[[1]])
  paths <- sub('^"(.*)"$', "\\1", paths)
  paths <- paths[nzchar(paths)]
  if (!length(paths)) stop("Enter at least one full parquet file path.")
  if (any(!grepl("^([A-Za-z]:[/\\\\]|/|\\\\\\\\)", paths))) stop("Enter full paths, not relative paths.")
  if (any(!file.exists(paths) | dir.exists(paths))) stop("A selected file does not exist. Check each path.")
  if (any(tolower(tools::file_ext(paths)) != "parquet")) stop("Select parquet files only.")
  paths <- normalizePath(paths, winslash = "/", mustWork = TRUE)
  data.frame(name = basename(paths), datapath = paths, source_path = paths)
}

# Keep selections until Compute, even when Shiny replaces its upload temp files.
server_upload_queue <- function(input, output, session, rv, invalidate_data, type) {
  ms1 <- identical(type, "ms1_features")
  prefix <- if (ms1) "ms1" else "diann"
  upload_id <- if (ms1) "ms1_files" else "parquet_file"
  remove_id <- if (ms1) "remove_feature_file" else "remove_diann_file"
  clear_id <- if (ms1) "clear_feature_files" else "clear_diann_files"
  output_id <- if (ms1) "feature_upload_queue" else "diann_upload_queue"
  staging_dir <- tempfile("aidia-input-uploads-")
  dir.create(staging_dir)
  session$onSessionEnded(function() unlink(staging_dir, recursive = TRUE))
  empty <- data.frame(id = integer(), name = character(), size = numeric(),
    datapath = character(), digest = character(), source_path = character(),
    runs = I(list()), stringsAsFactors = FALSE)
  files <- shiny::reactiveVal(empty)
  next_id <- 0L

  reset_picker <- function() {
    shinyjs::runjs(sprintf("$('#%s').val(''); $('#%s').closest('.shiny-input-container').find('input[type=text]').val('');", upload_id, upload_id))
  }
  add_files <- function(uploads) {
    previous <- files()
    added <- empty
    # Roll back a failed selection without changing the already queued files.
    tryCatch({
      if (!ms1 && nrow(uploads) != 1L) stop("Select one DIA-NN report containing all desired runs.")
      if (!"source_path" %in% names(uploads)) uploads$source_path <- uploads$name
      digests <- unname(tools::md5sum(uploads$datapath))
      if (anyNA(digests)) stop("An uploaded file is unavailable. Please select it again.")
      keep <- !duplicated(digests) & !digests %in% previous$digest
      if (any(!keep)) shiny::showNotification(
        "Identical files already in the list were skipped.", type = "message")
      uploads <- uploads[keep, , drop = FALSE]
      digests <- digests[keep]
      sizes <- file.info(uploads$datapath)$size
      if ((if (ms1) sum(previous$size) else 0) + sum(sizes) > getOption("shiny.maxRequestSize", 500 * 1024^2))
        stop("The queued files exceed the upload size limit. Remove files before adding more.")
      for (i in seq_len(nrow(uploads))) {
        next_id <<- next_id + 1L
        destination <- tempfile("feature-", tmpdir = staging_dir, fileext = ".parquet")
        if (!file.copy(uploads$datapath[i], destination)) {
          unlink(destination)
          stop("Could not retain an uploaded file. Please select it again.")
        }
        added <- rbind(added, data.frame(id = next_id, name = uploads$name[i],
          size = sizes[i], datapath = destination, digest = digests[i], source_path = uploads$source_path[i],
          runs = I(list(.shiny_upload_runs(destination, ms1)))))
      }
      if (nrow(added)) {
        files(if (ms1) rbind(previous, added) else added)
        if (!ms1) unlink(previous$datapath)
        invalidate_data()
      }
    }, error = function(e) {
      unlink(added$datapath)
      shiny::showNotification(conditionMessage(e), type = "error", duration = 10)
    })
  }
  shiny::observeEvent(input[[upload_id]], {
    shiny::req(identical(input$input_type, type))
    add_files(input[[upload_id]])
    reset_picker()
  })
  shiny::observeEvent(input[[paste0("add_", prefix, "_paths")]], {
    shiny::req(identical(input$input_type, type))
    if (!isTRUE(getOption("aidia.shiny.local_files", FALSE))) return()
    tryCatch({
      add_files(.shiny_local_uploads(input[[paste0(prefix, "_local_paths")]]))
    }, error = function(e) shiny::showNotification(conditionMessage(e), type = "error", duration = 10))
  })

  shiny::observeEvent(input[[remove_id]], {
    current <- files()
    remove <- as.character(current$id) %in% as.character(input[[remove_id]])
    if (any(remove)) {
      unlink(current$datapath[remove])
      files(current[!remove, , drop = FALSE])
      invalidate_data()
    }
  })
  clear <- function() {
    unlink(files()$datapath)
    files(empty)
    invalidate_data()
    reset_picker()
  }
  shiny::observeEvent(input[[clear_id]], clear())
  shiny::observeEvent(input$btn_new_analysis, clear())

  output[[output_id]] <- shiny::renderUI({
    current <- files()
    loaded <- isTRUE(rv$data_loaded) &&
      identical(rv$data_input_type, type)
    result <- shiny::tagList(
      shiny::tags$p(role = "status", sprintf("%d file(s) in the list. %s", nrow(current),
        if (!nrow(current)) if (ms1) "Add feature files from each folder." else "Add a DIA-NN report."
        else if (loaded) "Computed with the current settings."
        else "Ready to compute; click Compute when your selection is complete.")),
      if (nrow(current)) shiny::tags$table(class = "table table-sm",
        shiny::tags$thead(shiny::tags$tr(lapply(c("#", "Source / runs", "Size", ""), shiny::tags$th))),
        shiny::tags$tbody(lapply(seq_len(nrow(current)), function(i) {
          runs <- current$runs[[i]]
          run_label <- if (!length(runs)) shiny::tags$div("Run names unavailable; validate with Compute.")
            else if (length(runs) <= 3) shiny::tags$div(shiny::tags$strong("Run: "), paste(runs, collapse = ", "))
            else shiny::tags$details(shiny::tags$summary(sprintf("%d runs", length(runs))),
              shiny::tags$ul(lapply(runs, shiny::tags$li)))
          shiny::tags$tr(shiny::tags$td(i), shiny::tags$td(style = "overflow-wrap: anywhere;",
              run_label, shiny::tags$div(current$source_path[i])),
            shiny::tags$td(sprintf("%.2f MB", current$size[i] / 1024^2)),
            shiny::tags$td(shiny::tags$button(type = "button", class = "btn btn-outline-secondary btn-sm",
              `aria-label` = sprintf("Remove file %d: %s", i, current$source_path[i]),
              onclick = sprintf("Shiny.setInputValue('%s', '%d', {priority: 'event'})", remove_id, current$id[i]),
              "Remove")))
        }))))
    result
  })
  # Initialize even an empty queue while its input-type panel is hidden.
  shiny::outputOptions(output, output_id, suspendWhenHidden = FALSE)
  shiny::reactive(files())
}
