test_that("the local diagnostic exposes a concentrated band hidden by pooling", {
  profile <- prepare_fz_profile(data.frame(
    Precursor.Mz = c(rep(420 * OPTIMAL_INCREMENT + .02, 990),
      rep(820 * OPTIMAL_INCREMENT + .25, 10)),
    Precursor.Charge = c(rep(2, 990), rep(3, 10))))
  local <- summarize_fz_mz_bins(profile, .25, .05)
  expect_equal(sum(local$near) / sum(local$n), .01)
  expect_equal(local$mz_lower[1], 800)
  expect_equal(local$fraction[1], 1)
  expect_equal(local$near[1], 10L)
  expect_equal(sum(local$near), count_fz_margin(profile$phase, .25, .05))
  by_charge <- summarize_fz_mz_bins(profile, .25, .05, TRUE)
  expect_equal(sum(by_charge$near), sum(local$near))
  expect_equal(by_charge$near[by_charge$charge == "2+"], 0)
})

test_that("map aggregation preserves sparse and unknown-charge precursors", {
  profile <- prepare_fz_profile(data.frame(Precursor.Mz = c(400.01, 400.01, 400.52, 810.2, NA),
    Precursor.Charge = c(2, 2, 3, NA, 4)))
  cells <- prepare_fz_diagnostic(profile, TRUE)
  expect_equal(sum(cells$n), 4)
  expect_setequal(as.character(unique(cells$charge)), c("2+", "3+", "Unknown"))
  normalized <- aggregate(cells$fraction, cells[c("charge", "mz_lower")], sum)
  expect_equal(normalized$x, rep(1, nrow(normalized)))
  all <- prepare_fz_diagnostic(profile)
  expect_equal(sum(all$n), 4)
  expect_equal(as.character(unique(all$charge)), "All charges")
  expect_equal(sum(all$fraction[all$mz_lower == 400]), 1)
})

test_that("diagnostic bands wrap at the seam and local counts use exact phases", {
  for (offset in c(.0001, .25, .9999)) {
    band <- fz_margin_intervals(offset, .05)
    expect_equal(sum(band$upper - band$lower), .1)
    expect_true(all(band$lower >= 0 & band$upper <= OPTIMAL_INCREMENT))
    profile <- prepare_fz_profile(data.frame(Precursor.Mz =
      500 * OPTIMAL_INCREMENT + c(.00001, OPTIMAL_INCREMENT - .00001,
        offset + .05, offset + .050001, offset - .05)))
    local <- summarize_fz_mz_bins(profile, offset, .05)
    expect_equal(sum(local$near), count_fz_margin(profile$phase, offset, .05))
  }
  expect_equal(nrow(fz_margin_intervals(.0001, .05)), 2)
})

test_that("2D plot uses the same selected offset in every charge panel", {
  profile <- prepare_fz_profile(data.frame(Precursor.Mz = c(450, 550, 650),
    Precursor.Charge = c(2, 3, 4)))
  cells <- prepare_fz_diagnostic(profile, TRUE)
  plot <- plot_fz_diagnostic(cells, .9999, .05)
  built <- ggplot2::ggplot_build(plot)
  expect_equal(nrow(built$layout$layout), 3)
  center_lines <- Filter(function(layer) "yintercept" %in% names(layer) &&
    all(layer$yintercept == .9999), built$data)
  expect_gt(length(center_lines), 0)
  for (line in center_lines) expect_equal(line$yintercept, rep(.9999, 3))
  expect_s3_class(ggplot2::ggplotGrob(plot), "gtable")
  empty <- prepare_fz_profile(data.frame(Precursor.Mz = numeric()))
  expect_equal(nrow(prepare_fz_diagnostic(empty)), 0)
  expect_equal(nrow(summarize_fz_mz_bins(empty, .25, .05)), 0)
  expect_s3_class(ggplot2::ggplotGrob(plot_fz_diagnostic(data.frame(), .25, .05)), "gtable")
})
