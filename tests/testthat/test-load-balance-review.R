.load_review_fixture <- function() {
  list(result = list(windows = data.frame(rt_segment_id = 1:2,
    rt_start = c(0, 10), rt_end = c(10, 20), mz_start = 900,
    mz_end = 1000, window_width = 100)),
    data = list(data = data.frame(Precursor.Mz = c(910, 920), RT.Apex = c(5, 15))),
    plan = list(original_method = fixed_method_config(2, 400, 500)))
}

test_that("load comparison retains an entirely empty original method", {
  f <- .load_review_fixture()
  p <- plot_precursor_load_balance(f$result, f$data, f$plan)
  expect_setequal(as.character(unique(p$data$group)), c("Baseline", "Optimized"))
  expect_equal(p$data$precursor_count[p$data$group == "Baseline"], rep(0, 4))
  expect_false(grepl("NaN|Inf", p$labels$subtitle))
  expect_no_warning(ggplot2::ggplotGrob(p))
})

test_that("load comparison shares explicit membership and deterministic placement", {
  f <- .load_review_fixture()
  f$data$data$rt_group <- c(2, 2)
  p <- plot_precursor_load_balance(f$result, f$data, f$plan)
  expect_equal(p$data$precursor_count[p$data$group == "Optimized"], c(0, 2))
  first <- ggplot2::ggplot_build(p)$data[[2]]$x
  second <- ggplot2::ggplot_build(p)$data[[2]]$x
  expect_equal(first, second)
})
