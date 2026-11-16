test_that("circular margin counts include seam neighbors and both band edges", {
  period <- OPTIMAL_INCREMENT
  phase <- c(.001, period - .001, .05, .25, .30, .35)
  offsets <- c(0, period, .30, .9999)
  actual <- count_fz_margin(phase, offsets, .05)
  expected <- vapply(offsets, function(offset) {
    distance <- abs(((phase - offset + period / 2) %% period) - period / 2)
    sum(distance <= .05 + 1e-10)
  }, integer(1))
  expect_equal(actual, expected)
  expect_equal(actual[1], actual[2])
  expect_equal(actual[3], 3L)
  expect_error(count_fz_margin(phase, .25, 0), "Margin")
  expect_error(count_fz_margin(phase, .25, period / 2), "Margin")
})

test_that("2+ priority never trades away its target to improve pooled counts", {
  other <- seq(0, OPTIMAL_INCREMENT, length.out = 20001)
  other <- other[abs(other - .25) > .012]
  data <- data.frame(Precursor.Mz = 500 * OPTIMAL_INCREMENT + c(rep(.25, 10), other),
    Precursor.Charge = c(rep(2L, 10), rep(3L, length(other))))
  profile <- prepare_fz_profile(data)
  z2 <- suggest_fz_offset(profile, "z2", .01)
  all <- suggest_fz_offset(profile, "all", .01)
  expect_equal(z2$target_count, 0L)
  expect_gt(count_fz_margin(profile$z2, all$offset, .01), 0L)
  expect_lt(all$all_count, z2$all_count)
  expect_equal(suggest_fz_offset(profile, "z2", .01), z2)
  expect_gte(z2$offset, .0001)
  expect_lte(z2$offset, .9999)
})

test_that("unknown charges stay in pooled scoring and missing 2+ is explicit", {
  data <- data.frame(Precursor.Mz = c(500, 501, 502, NA, Inf, -1),
    Precursor.Charge = factor(c("3", "4", NA, "2", "2", "2")))
  profile <- prepare_fz_profile(data)
  expect_equal(profile$n, 3L)
  expect_equal(profile$excluded, 3L)
  expect_equal(vapply(profile$groups, `[[`, character(1), "label"), c("3+", "4+", "Unknown"))
  expect_null(suggest_fz_offset(profile, "z2")$offset)
  expect_match(suggest_fz_offset(profile, "z2")$reason, "No 2\\+")
  expect_equal(suggest_fz_offset(profile, "all")$all_n, 3L)
  data$Precursor.Charge <- NULL
  expect_no_warning(unknown <- prepare_fz_profile(tibble::as_tibble(data)))
  expect_length(unknown$groups, 1)
  expect_equal(unknown$groups[[1]]$label, "Unknown")
  expect_null(suggest_fz_offset(prepare_fz_profile(data[FALSE, , drop = FALSE]), "all")$offset)
})

test_that("equal candidates retain 0.25 and charge histograms preserve counts", {
  profile <- prepare_fz_profile(data.frame(Precursor.Mz = rep(500 * OPTIMAL_INCREMENT + .02, 20),
    Precursor.Charge = 2))
  expect_equal(suggest_fz_offset(profile, "z2")$offset, .25)
  plot <- ggplot2::ggplot_build(plot_fz_phase_histogram(profile$z2, "2+ precursors"))
  expect_equal(sum(plot$data[[1]]$count), 20)
  expect_s3_class(ggplot2::ggplotGrob(plot_fz_phase_histogram(numeric(), "2+")), "gtable")
})

test_that("actual-edge assessment respects RT and counts overlapping cycles once", {
  data <- data.frame(Precursor.Mz = c(450.02, 450.02, 500, 600, 450.02),
    RT.Apex = c(.5, 1, 2, .5, NA), Precursor.Charge = c(2, 3, 4, 2, 2))
  windows <- data.frame(mz_start = c(400, 450, 440, 400),
    mz_end = c(450, 500, 490, 500), rt_start = c(0, 0, 0, 1), rt_end = c(1, 1, 1, 2))
  result <- summarize_fz_edges(data, windows, .05)
  expect_equal(result, list(all_n = 3L, all_count = 2L, z2_n = 1L, z2_count = 1L))
})

test_that("suggestion application writes the canonical custom offset and honors disabled mode", {
  env <- new.env(parent = environment())
  for (name in getNamespaceExports("shiny")) env[[name]] <- getExportedValue("shiny", name)
  sys.source(system.file("shiny_app", "server_fz_boundary.R", package = "aidia", mustWork = TRUE), env)
  sent <- list()
  env$updateNumericInput <- function(session, inputId, value, ...) sent[[inputId]] <<- value
  env$updateSelectInput <- function(session, inputId, selected, ...) sent[[inputId]] <<- selected
  server <- function(input, output, session) {
    rv <- shiny::reactiveValues(validated_data = structure(list(data = data.frame(
      Precursor.Mz = 500 * OPTIMAL_INCREMENT + seq(.01, .09, length.out = 20),
      Precursor.Charge = rep(2, 20))), class = c("ValidatedData", "list")))
    env$server_fz_boundary(input, output, session, rv)
  }
  shiny::testServer(server, {
    session$setInputs(fz_target = "z2", fz_margin = .05, fz_offset_preset = "0.18")
    expect_match(output$fz_recommendation$html, "Optimal offset: 0.2500")
    before <- output$fz_recommendation$html
    session$setInputs(fz_diagnostic_view = "charge")
    expect_equal(output$fz_recommendation$html, before)
    expect_match(output$fz_local_counts, "2[+]")
    expect_type(output$fz_diagnostic_plot, "list")
    session$setInputs(fz_diagnostic_view = "all")
    expect_equal(output$fz_recommendation$html, before)
    expect_match(output$fz_local_counts, "All charges")
    session$setInputs(fz_apply_suggestion = 1)
    expect_equal(sent$custom_fz_offset, .25)
    expect_equal(sent$fz_offset_preset, "custom")
    session$setInputs(fz_offset_preset = "custom", custom_fz_offset = .25)
    expect_match(output$fz_recommendation$html, "Applied")
    sent <<- list()
    session$setInputs(fz_offset_preset = "0", fz_apply_suggestion = 2)
    expect_length(sent, 0)
    session$setInputs(fz_offset_preset = "custom", fz_margin = NULL, fz_apply_suggestion = 3)
    expect_length(sent, 0)
    rv$validated_data$data$Precursor.Charge <- NULL
    session$setInputs(fz_margin = .05, fz_apply_suggestion = 4)
    expect_length(sent, 0)
    expect_match(output$fz_recommendation$html, "No 2\\+")
    session$setInputs(fz_target = "all", fz_apply_suggestion = 5)
    expect_equal(sent$fz_offset_preset, "custom")
    expect_equal(sent$custom_fz_offset, .25)
  })
})
