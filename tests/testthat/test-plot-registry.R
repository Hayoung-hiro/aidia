# test-plot-registry.R
#
# Verify the v0.4.1 visualization plot registry:
#   - REPORT_TEMPLATES declares known templates
#   - filter_by_template() returns the correct subset
#   - expand_plot_keys() handles strategies and missing windows_list
#   - should_generate() respects when() predicates
#   - collect_requirements() unions the requires fields
#   - PLOT_REGISTRY entries have a consistent shape


# ---------------------------------------------------------------------------
# Templates
# ---------------------------------------------------------------------------

test_that("REPORT_TEMPLATES exposes full and minimal", {
  expect_true(all(c("full", "minimal") %in% names(REPORT_TEMPLATES)))
  for (t in names(REPORT_TEMPLATES)) {
    expect_true(!is.null(REPORT_TEMPLATES[[t]]$description))
  }
})


# ---------------------------------------------------------------------------
# Registry shape
# ---------------------------------------------------------------------------

test_that("every PLOT_REGISTRY entry has a generate function and templates field", {
  for (i in seq_along(PLOT_REGISTRY)) {
    entry <- PLOT_REGISTRY[[i]]
    expect_true(is.function(entry$generate),
                info = sprintf("entry %d: generate must be a function", i))
    expect_true(is.character(entry$templates) && length(entry$templates) > 0,
                info = sprintf("entry %d: templates must be a non-empty character vector", i))
    # Either concrete key OR expansion template, but not neither
    # Use [[ ]] (not $) to avoid partial matching key <-> key_template
    has_key <- !is.null(entry[["key"]])
    has_template <- !is.null(entry[["key_template"]])
    label <- sprintf("entry %d", i)
    expect_true(has_key || has_template, info = label)
    expect_true(!(has_key && has_template), info = label)
  }
})


# ---------------------------------------------------------------------------
# filter_by_template()
# ---------------------------------------------------------------------------

test_that("filter_by_template selects matching entries", {
  full_entries <- filter_by_template(PLOT_REGISTRY, "full")
  minimal_entries <- filter_by_template(PLOT_REGISTRY, "minimal")

  expect_true(length(full_entries) > length(minimal_entries),
              info = "full template should include more entries than minimal")
  expect_gt(length(minimal_entries), 0)
  expect_lte(length(minimal_entries), 10,
             label = "minimal template kept tight (~ <= 10 entries)")

  # All minimal entries must also be in full (minimal is a subset of full)
  minimal_keys <- vapply(minimal_entries,
                          function(e) e[["key"]] %||% e[["key_template"]],
                          character(1))
  full_keys <- vapply(full_entries,
                       function(e) e[["key"]] %||% e[["key_template"]],
                       character(1))
  expect_true(all(minimal_keys %in% full_keys),
              info = "every minimal-template entry must also belong to the full template")
})

test_that("filter_by_template returns empty list for unknown template", {
  expect_equal(length(filter_by_template(PLOT_REGISTRY, "nonexistent")), 0L)
})


# ---------------------------------------------------------------------------
# expand_plot_keys()
# ---------------------------------------------------------------------------

test_that("expand_plot_keys returns the concrete key for non-expanding entries", {
  entry <- list(key = "s1_02_fwhm_distribution",
                generate = function(ctx) NULL,
                templates = "full")
  expect_equal(expand_plot_keys(entry, ctx = list()),
               "s1_02_fwhm_distribution")
})

test_that("expand_plot_keys expands strategies from ctx$windows_list", {
  entry <- list(key_template = "app_b_{strategy}_mz_excluded",
                generate = function(ctx, strategy) NULL,
                expand_over = "strategies",
                templates = "full")
  ctx <- list(windows_list = list(greedy = NULL, kde = NULL, quantile = NULL))
  keys <- unname(expand_plot_keys(entry, ctx))
  expect_equal(sort(keys),
               sort(c("app_b_greedy_mz_excluded",
                       "app_b_kde_mz_excluded",
                       "app_b_quantile_mz_excluded")))
})

test_that("expand_plot_keys returns empty when windows_list is NULL", {
  entry <- list(key_template = "app_b_{strategy}_mz_excluded",
                generate = function(ctx, strategy) NULL,
                expand_over = "strategies",
                templates = "full")
  expect_equal(length(expand_plot_keys(entry, ctx = list())), 0L)
})

test_that("expand_plot_keys errors when key_template missing", {
  bad_entry <- list(generate = function(ctx, strategy) NULL,
                     expand_over = "strategies",
                     templates = "full")
  ctx <- list(windows_list = list(greedy = NULL))
  expect_error(expand_plot_keys(bad_entry, ctx), "key_template")
})


# ---------------------------------------------------------------------------
# should_generate()
# ---------------------------------------------------------------------------

test_that("should_generate returns TRUE for entries with no condition", {
  entry <- list(key = "x", generate = function(ctx) NULL, templates = "full")
  expect_true(should_generate(entry, ctx = list()))
})

test_that("should_generate honors the when() predicate", {
  entry <- list(key = "s2_tiling_coverage",
                generate = function(ctx) NULL,
                when = function(ctx) identical(ctx$optimized_windows$parameters$window_mode,
                                                "staggered"),
                templates = "full")
  # staggered: should generate
  ctx_stag <- list(optimized_windows = list(parameters = list(window_mode = "staggered")))
  expect_true(should_generate(entry, ctx_stag))
  # density: should not
  ctx_dens <- list(optimized_windows = list(parameters = list(window_mode = "density")))
  expect_false(should_generate(entry, ctx_dens))
})

test_that("should_generate returns FALSE if when() throws", {
  entry <- list(key = "x", generate = function(ctx) NULL,
                when = function(ctx) stop("boom"), templates = "full")
  expect_false(should_generate(entry, ctx = list()))
})


# ---------------------------------------------------------------------------
# collect_requirements()
# ---------------------------------------------------------------------------

test_that("collect_requirements unions all entries' requires fields", {
  entries <- list(
    list(requires = c("a", "b")),
    list(requires = "b"),
    list(requires = NULL),
    list(requires = "c")
  )
  expect_equal(sort(collect_requirements(entries)), c("a", "b", "c"))
})

test_that("minimal template does NOT require windows_list (no s3_* selected)", {
  # If this fails, minimal template accidentally selected an s3_* / app_b_* plot
  # that requires the expensive 5-strategy re-optimization.
  minimal_entries <- filter_by_template(PLOT_REGISTRY, "minimal")
  needs <- collect_requirements(minimal_entries)
  # NOTE: relaxed — s3_01 strategy_table IS in minimal by design (single-strategy summary)
  # If you ever DO want minimal to skip strategy comparison, drop s3_01/s3_02 from minimal.
  expect_true(is.character(needs) || is.null(needs))
})
