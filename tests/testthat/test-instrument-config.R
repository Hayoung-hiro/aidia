# test-instrument-config.R
#
# Unit tests at the external interface of R/instrument_config.R.
# Verifies JSON loading, classification predicates, listing, validation,
# and width recommendations after the v0.4.1 split from instrument_utils.R.


# ---------------------------------------------------------------------------
# get_instrument_config()
# ---------------------------------------------------------------------------

test_that("get_instrument_config returns a config for known presets", {
  for (preset in c("astral", "exploris", "qexactive_hfx", "fusion_lumos")) {
    config <- get_instrument_config(preset)
    expect_true(is.list(config))
    expect_true(!is.null(config$name))
    expect_true(!is.null(config$analyzer_type))
    expect_true(!is.null(config$cycle_calculation))
    expect_true(!is.null(config$ms1_scans_per_cycle))
  }
})

test_that("get_instrument_config errors on unknown preset", {
  expect_error(
    get_instrument_config("nonexistent_instrument_xyz"),
    "Unknown instrument preset"
  )
})


# ---------------------------------------------------------------------------
# Classification predicates
# ---------------------------------------------------------------------------

test_that("is_orbitrap_instrument identifies Orbitrap presets", {
  expect_true(is_orbitrap_instrument("exploris"))
  expect_true(is_orbitrap_instrument("qexactive_hfx"))
  expect_true(is_orbitrap_instrument("fusion_lumos"))
  expect_false(is_orbitrap_instrument("astral"))
})

test_that("is_astral_instrument identifies Astral presets", {
  expect_true(is_astral_instrument("astral"))
  expect_false(is_astral_instrument("exploris"))
  expect_false(is_astral_instrument("qexactive_hfx"))
})

test_that("classification predicates are mutually exclusive for known analyzers", {
  for (preset in c("astral", "exploris", "qexactive_hfx", "fusion_lumos")) {
    n_true <- sum(c(is_orbitrap_instrument(preset), is_astral_instrument(preset)))
    expect_equal(n_true, 1L,
                 info = sprintf("preset '%s' should match exactly one analyzer", preset))
  }
})


# ---------------------------------------------------------------------------
# list_available_instruments()
# ---------------------------------------------------------------------------

test_that("list_available_instruments returns a data frame with expected columns", {
  df <- list_available_instruments()

  expect_s3_class(df, "data.frame")
  expect_true(nrow(df) >= 4)  # at least Astral, Exploris, QE HF-X, Fusion Lumos
  expect_named(df, c("Preset", "Name", "MS1_Time_ms", "MS2_Time_ms",
                     "Max_Hz", "Cycle_Calc", "MS1_Scans"))

  # Cycle_Calc must be one of the documented values
  expect_true(all(df$Cycle_Calc %in% c("parallel", "sequential")))
})

test_that("list_available_instruments preset column matches get_instrument_config", {
  df <- list_available_instruments()
  # Each listed preset must be retrievable
  for (preset in df$Preset) {
    expect_true(is.list(get_instrument_config(preset)),
                info = sprintf("preset '%s' from listing not retrievable", preset))
  }
})


# ---------------------------------------------------------------------------
# get_instrument_width_recommendations()
# ---------------------------------------------------------------------------

test_that("get_instrument_width_recommendations returns min/max width", {
  config <- get_instrument_config("astral")
  recs <- get_instrument_width_recommendations(config)

  expect_named(recs, c("min_width_da", "max_width_da"))
  expect_true(is.numeric(recs$min_width_da))
  expect_true(is.numeric(recs$max_width_da))
  expect_lt(recs$min_width_da, recs$max_width_da)
})

test_that("get_instrument_width_recommendations falls back when fields missing", {
  # Empty config -> defaults (2 Da min, 80 Da max)
  recs <- get_instrument_width_recommendations(list())
  expect_equal(recs$min_width_da, 2)
  expect_equal(recs$max_width_da, 80)
})
