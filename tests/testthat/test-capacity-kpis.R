# test-capacity-kpis.R
# Unit tests for R/capacity_kpis.R (PR 1 of acquisition-capacity-dashboard).
#
# Coverage (11 cases, matching implementation plan):
#   1.  compute_filled_ratio with fixture eval
#   2.  compute_dppp_headroom
#   3.  compute_cycle_headroom_pct
#   4.  compute_window_headroom_pct
#   5.  classify_capacity_kpi boundary mapping (4 KPIs)
#   6.  capacity_kpi_thresholds defaults and override
#   7.  summarize_bottleneck for each of the 8 rules
#   8.  NA-safe behaviour when filled_window_ratio is NA
#   9.  Spec-limited handling (window headroom -> 0)
#   10. Sequential header text
#   11. Parallel header text

# =============================================================================
# Test fixtures
# =============================================================================

make_test_plan <- function(...) {
  defaults <- list(
    window_count_per_bin       = 50L,
    required_cycle_time_sec    = 1.0,
    actual_cycle_time_sec      = 0.85,
    diagnosis = list(
      current_cycle_time_sec     = 0.85,
      current_ct_is_estimated    = FALSE,
      current_satisfaction_ratio = 0.7,
      current_dppp_mean          = 14.0,
      current_dppp_median        = 14.0,
      current_dppp_sd            = 1.0,
      n_satisfied                = 70L,
      n_total                    = 100L
    ),
    feasibility = list(
      is_feasible      = TRUE,
      cycle_time_ok    = TRUE,
      scan_rate_ok     = TRUE,
      window_range_ok  = TRUE
    ),
    instrument = list(
      preset     = "exploris_480",
      name       = "Exploris 480",
      cycle_mode = "sequential"
    ),
    parameters = list(
      target_dppp         = 7.0,
      target_satisfaction = 0.7,
      max_windows         = 300L
    ),
    it_optimization = list(is_spec_limited = FALSE),
    duty_cycle_sync = NULL
  )
  overrides <- list(...)
  for (nm in names(overrides)) defaults[[nm]] <- overrides[[nm]]
  structure(defaults, class = c("OptimizationPlan", "list"))
}

make_test_windows <- function() {
  structure(list(), class = c("OptimizedWindows", "list"))
}

make_test_eval <- function(n_total = 100L, n_empty = 15L) {
  list(
    overall       = list(n_total_windows = n_total),
    quality_flags = list(empty_windows = if (n_empty > 0) seq_len(n_empty) else integer(0))
  )
}

make_kpis <- function(filled = "OK", dppp = "OK", cycle = "OK", win = "OK",
                      is_spec_limited = FALSE) {
  list(
    values = c(
      filled_window_ratio       = NA_real_,
      dppp_headroom_x           = NA_real_,
      cycle_time_headroom_pct   = NA_real_,
      window_count_headroom_pct = NA_real_
    ),
    grades = c(
      filled_window_ratio       = filled,
      dppp_headroom_x           = dppp,
      cycle_time_headroom_pct   = cycle,
      window_count_headroom_pct = win
    ),
    is_spec_limited = is_spec_limited,
    thresholds      = capacity_kpi_thresholds()
  )
}

# Bottleneck messages (must match capacity_kpis.R exactly).
MSG_R1 <- "DPPP target not met - cycle too long for required peak sampling. Reduce window count or shorten transient."
MSG_R2 <- "Many empty windows - review m/z strategy or RT binning."
MSG_R3 <- "Some empty windows - consider tightening m/z strategy."
MSG_R4 <- "Cycle and windows near ceiling with DPPP slack - IT or m/z width tradeoff available."
MSG_R5 <- "Underutilized - add more windows or shorten cycle."
MSG_R6 <- "Large DPPP headroom - opportunity to lengthen IT for better ion statistics."
MSG_R7 <- "Well balanced."
MSG_R8 <- "See individual KPIs for details."

# =============================================================================
# 1. compute_filled_ratio
# =============================================================================

test_that("compute_filled_ratio returns 1 - empty / total", {
  # 15 empty / 100 total -> 0.85
  ev <- make_test_eval(n_total = 100L, n_empty = 15L)
  expect_equal(compute_filled_ratio(ev), 0.85)

  # all filled
  ev2 <- make_test_eval(n_total = 50L, n_empty = 0L)
  expect_equal(compute_filled_ratio(ev2), 1.0)

  # NULL evaluation -> NA
  expect_true(is.na(compute_filled_ratio(NULL)))

  # zero total -> NA (defensive)
  ev_bad <- list(overall = list(n_total_windows = 0L),
                 quality_flags = list(empty_windows = integer(0)))
  expect_true(is.na(compute_filled_ratio(ev_bad)))
})

# =============================================================================
# 2. compute_dppp_headroom
# =============================================================================

test_that("compute_dppp_headroom returns dppp_median / target_dppp", {
  expect_equal(compute_dppp_headroom(14, 7), 2.0)
  expect_equal(compute_dppp_headroom(7, 7), 1.0)
  expect_equal(compute_dppp_headroom(3.5, 7), 0.5)
  expect_true(is.na(compute_dppp_headroom(NULL, 7)))
  expect_true(is.na(compute_dppp_headroom(14, 0)))
})

# =============================================================================
# 3. compute_cycle_headroom_pct
# =============================================================================

test_that("compute_cycle_headroom_pct returns (required - actual) / required * 100", {
  expect_equal(compute_cycle_headroom_pct(1.0, 0.85), 15.0)
  expect_equal(compute_cycle_headroom_pct(1.0, 1.0), 0.0)
  expect_equal(compute_cycle_headroom_pct(1.0, 1.10), -10.0)
  expect_true(is.na(compute_cycle_headroom_pct(NA, 0.85)))
  expect_true(is.na(compute_cycle_headroom_pct(0, 0.85)))
})

# =============================================================================
# 4. compute_window_headroom_pct
# =============================================================================

test_that("compute_window_headroom_pct returns (max - n) / max * 100", {
  expect_equal(compute_window_headroom_pct(300, 100), 200 / 300 * 100)
  expect_equal(round(compute_window_headroom_pct(300, 100), 1), 66.7)
  expect_equal(compute_window_headroom_pct(100, 100), 0)
  expect_true(is.na(compute_window_headroom_pct(0, 100)))
})

# =============================================================================
# 5. classify_capacity_kpi at threshold boundaries
# =============================================================================

test_that("classify_capacity_kpi maps values to Bad/Warn/OK/Info", {
  th <- capacity_kpi_thresholds()

  # filled_window_ratio: bad < 0.70 <= warn < 0.90 <= OK
  expect_equal(classify_capacity_kpi(0.65, "filled_window_ratio", th), "Bad")
  expect_equal(classify_capacity_kpi(0.70, "filled_window_ratio", th), "Warn")
  expect_equal(classify_capacity_kpi(0.85, "filled_window_ratio", th), "Warn")
  expect_equal(classify_capacity_kpi(0.90, "filled_window_ratio", th), "OK")
  expect_equal(classify_capacity_kpi(0.99, "filled_window_ratio", th), "OK")

  # dppp_headroom_x: bad < 1.0 <= OK < 2.0 <= Info
  expect_equal(classify_capacity_kpi(0.5, "dppp_headroom_x", th), "Bad")
  expect_equal(classify_capacity_kpi(1.0, "dppp_headroom_x", th), "OK")
  expect_equal(classify_capacity_kpi(1.5, "dppp_headroom_x", th), "OK")
  expect_equal(classify_capacity_kpi(2.0, "dppp_headroom_x", th), "Info")
  expect_equal(classify_capacity_kpi(30,  "dppp_headroom_x", th), "Info")

  # cycle_time_headroom_pct: bad < 0 <= OK < 15 <= Info
  expect_equal(classify_capacity_kpi(-5,  "cycle_time_headroom_pct", th), "Bad")
  expect_equal(classify_capacity_kpi(0,   "cycle_time_headroom_pct", th), "OK")
  expect_equal(classify_capacity_kpi(10,  "cycle_time_headroom_pct", th), "OK")
  expect_equal(classify_capacity_kpi(15,  "cycle_time_headroom_pct", th), "Info")
  expect_equal(classify_capacity_kpi(50,  "cycle_time_headroom_pct", th), "Info")

  # window_count_headroom_pct: OK < 30 <= Info (no Bad/Warn band)
  expect_equal(classify_capacity_kpi(0,   "window_count_headroom_pct", th), "OK")
  expect_equal(classify_capacity_kpi(20,  "window_count_headroom_pct", th), "OK")
  expect_equal(classify_capacity_kpi(30,  "window_count_headroom_pct", th), "Info")
  expect_equal(classify_capacity_kpi(60,  "window_count_headroom_pct", th), "Info")

  # NA / NULL value -> "NA"
  expect_equal(classify_capacity_kpi(NA_real_, "filled_window_ratio", th), "NA")
  expect_equal(classify_capacity_kpi(NULL,     "dppp_headroom_x",     th), "NA")
})

# =============================================================================
# 6. capacity_kpi_thresholds defaults + override
# =============================================================================

test_that("capacity_kpi_thresholds returns the documented default table", {
  th <- capacity_kpi_thresholds()

  expect_equal(th$filled_window_ratio,       list(bad = 0.70, warn = 0.90))
  expect_equal(th$dppp_headroom_x,           list(bad = 1.0,  info = 2.0))
  expect_equal(th$cycle_time_headroom_pct,   list(bad = 0.0,  info = 15.0))
  expect_equal(th$window_count_headroom_pct, list(info = 30.0))
})

test_that("capacity_kpi_thresholds merges overrides per KPI", {
  custom <- capacity_kpi_thresholds(
    filled_window_ratio = list(bad = 0.60, warn = 0.85),
    dppp_headroom_x     = list(bad = 1.0,  info = 3.0)
  )

  expect_equal(custom$filled_window_ratio,       list(bad = 0.60, warn = 0.85))
  expect_equal(custom$dppp_headroom_x,           list(bad = 1.0,  info = 3.0))
  # Untouched KPIs keep defaults
  expect_equal(custom$cycle_time_headroom_pct,   list(bad = 0.0,  info = 15.0))
  expect_equal(custom$window_count_headroom_pct, list(info = 30.0))
})

test_that("capacity_kpi_thresholds rejects non-list overrides", {
  expect_error(
    capacity_kpi_thresholds(filled_window_ratio = c(0.5, 0.8)),
    "must be a named list"
  )
})

# =============================================================================
# 7. summarize_bottleneck: each of the 8 rules
# =============================================================================

test_that("rule 1: dppp=Bad -> DPPP target not met", {
  msg <- summarize_bottleneck(make_kpis(dppp = "Bad", cycle = "Bad"))
  expect_equal(msg, MSG_R1)
})

test_that("rule 2: filled=Bad -> many empty windows (when dppp is not Bad)", {
  msg <- summarize_bottleneck(make_kpis(filled = "Bad", dppp = "OK"))
  expect_equal(msg, MSG_R2)
})

test_that("rule 3: filled=Warn with no Bad -> some empty windows", {
  msg <- summarize_bottleneck(make_kpis(filled = "Warn", dppp = "OK", cycle = "OK"))
  expect_equal(msg, MSG_R3)
})

test_that("rule 4: cycle=OK & win=OK & dppp=Info -> tradeoff available", {
  # filled = NA so rule 6 (which requires filled=OK) cannot fire.
  msg <- summarize_bottleneck(make_kpis(filled = "NA", dppp = "Info",
                                        cycle = "OK", win = "OK"))
  expect_equal(msg, MSG_R4)
})

test_that("rule 5: cycle=Info & win=Info -> underutilized", {
  msg <- summarize_bottleneck(make_kpis(filled = "OK", dppp = "Info",
                                        cycle = "Info", win = "Info"))
  expect_equal(msg, MSG_R5)
})

test_that("rule 6: dppp=Info with filled/cycle/win all OK -> IT-only advice", {
  # filled = OK distinguishes rule 6 from rule 4. Rule 4 now requires
  # filled != "OK", so this input falls through to rule 6.
  msg <- summarize_bottleneck(make_kpis(filled = "OK", dppp = "Info",
                                        cycle = "OK", win = "OK"))
  expect_equal(msg, MSG_R6)
})

test_that("rule 4 vs rule 6: filled NA -> rule 4, filled OK -> rule 6", {
  # Same dppp/cycle/win pattern; filled state alone routes the message.
  msg_4 <- summarize_bottleneck(make_kpis(filled = "NA", dppp = "Info",
                                          cycle = "OK", win = "OK"))
  expect_equal(msg_4, MSG_R4)

  msg_6 <- summarize_bottleneck(make_kpis(filled = "OK", dppp = "Info",
                                          cycle = "OK", win = "OK"))
  expect_equal(msg_6, MSG_R6)
})

test_that("rule 7: all OK -> well balanced", {
  msg <- summarize_bottleneck(make_kpis(filled = "OK", dppp = "OK",
                                        cycle = "OK", win = "OK"))
  expect_equal(msg, MSG_R7)
})

test_that("rule 8: fallback when no other rule matches", {
  # All grades NA -> only rule 7 could fire if filled were unknown but
  # others OK. Setting cycle = Warn (unreachable in practice but a valid
  # grade) breaks every rule and falls through to the fallback message.
  msg <- summarize_bottleneck(make_kpis(filled = "NA", dppp = "OK",
                                        cycle = "Warn", win = "OK"))
  expect_equal(msg, MSG_R8)
})

# =============================================================================
# 8. NA-safe behaviour: rules #2 / #3 skipped when filled is NA
# =============================================================================

test_that("filled_ratio = NA skips rules 2 and 3 but rule 1 still fires", {
  # Rule 1 wins regardless of filled state
  msg1 <- summarize_bottleneck(make_kpis(filled = "NA", dppp = "Bad"))
  expect_equal(msg1, MSG_R1)
})

test_that("filled_ratio = NA with all-OK still reaches rule 7", {
  # No Bad / Warn from filled, and other rules don't match -> rule 7 fires
  msg <- summarize_bottleneck(make_kpis(filled = "NA", dppp = "OK",
                                        cycle = "OK", win = "OK"))
  expect_equal(msg, MSG_R7)
})

test_that("get_capacity_kpis with evaluation = NULL yields NA filled ratio", {
  plan <- make_test_plan()
  windows <- make_test_windows()
  kpis <- get_capacity_kpis(plan, windows, evaluation = NULL)
  expect_true(is.na(kpis$values[["filled_window_ratio"]]))
  expect_equal(kpis$grades[["filled_window_ratio"]], "NA")
  # Other KPIs unaffected
  expect_equal(kpis$values[["dppp_headroom_x"]], 2.0)
  expect_equal(kpis$values[["cycle_time_headroom_pct"]], 15.0)
})

# =============================================================================
# 9. Spec-limited handling: window headroom forced to 0
# =============================================================================

test_that("is_spec_limited = TRUE forces window_count_headroom_pct to 0", {
  plan <- make_test_plan(
    it_optimization = list(is_spec_limited = TRUE),
    window_count_per_bin = 150L
  )
  windows <- make_test_windows()
  kpis <- get_capacity_kpis(plan, windows)

  expect_equal(kpis$values[["window_count_headroom_pct"]], 0)
  expect_equal(kpis$grades[["window_count_headroom_pct"]], "OK")
  expect_true(kpis$is_spec_limited)
})

# =============================================================================
# 10. Sequential header text
# =============================================================================

test_that("capacity_header_text for sequential instrument names target DPPP", {
  plan <- make_test_plan(duty_cycle_sync = NULL)
  msg <- capacity_header_text(plan)
  expect_equal(msg,
               "Sequential instrument - DPPP-bound at target 7.0.")
})

# =============================================================================
# 11. Parallel header text
# =============================================================================

test_that("capacity_header_text for parallel instrument shows sync %", {
  plan <- make_test_plan(
    window_count_per_bin = 50L,
    duty_cycle_sync = list(
      duty_cycle_pct  = 80.0,
      n_sync_optimal  = 51L,
      ms1_idle_ms     = 5.0,
      ms2_idle_ms     = 0.0,
      sync_status     = "ms2_idle"
    )
  )
  msg <- capacity_header_text(plan)
  expect_equal(
    msg,
    "Parallel instrument - sync 80% (50 / 51 sync-optimal). DPPP-bound metrics may show high headroom."
  )
})
