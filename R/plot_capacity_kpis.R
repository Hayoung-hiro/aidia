# plot_capacity_kpis.R - Acquisition Capacity KPI Gauge Strip
#
# Purpose: Render the four capacity KPIs from get_capacity_kpis() as a strip
# of four semicircular gauges. Shiny-only by design -- no PLOT_REGISTRY
# entry. PDF report intentionally excludes the KPI dashboard.
#
# Visual structure (per KPI panel):
#   - Outer rim arc carries Bad / Warn / OK / Info zone bands in light tints
#     (information-grade reference scale).
#   - Inner ring (the half-circle) shows the current value as a grade-colored
#     fill from 0 up to the normalized value, on top of a pale neutral base.
#   - Center text reports the raw value in the grade color. NA values render
#     a gray gauge with center "N/A".
#
# Implementation: direct cartesian polygons (not coord_polar) + coord_fixed
# so the panel aspect ratio is forced to 2:1 and the half-circle fills the
# panel without leaving an empty lower half. No ggforce / gridExtra /
# patchwork dependency added.
#
# Dependencies: ggplot2, capacity_kpis.R, theme_aidia.R.


# =============================================================================
# Internal: visual specs and color tables
# =============================================================================

#' Per-KPI visual cap, panel title, and value formatter
#' @keywords internal
#' @noRd
.capacity_kpi_visual_specs <- function() {
  list(
    filled_window_ratio = list(
      cap   = 1.0,
      title = "Filled Windows",
      fmt   = function(v) sprintf("%.0f%%", v * 100)
    ),
    dppp_headroom_x = list(
      # Spec cap = 5x: Info threshold is 2x, so the dial saturates at 5x
      # without losing information. Astral routinely reports >= 30x; the
      # center text shows the actual value.
      cap   = 5.0,
      title = "DPPP Headroom",
      fmt   = function(v) {
        if (v >= 5.0) sprintf("%.0fx", v) else sprintf("%.1fx", v)
      }
    ),
    cycle_time_headroom_pct = list(
      cap   = 50.0,
      title = "Cycle Headroom",
      fmt   = function(v) sprintf("%.0f%%", v)
    ),
    window_count_headroom_pct = list(
      cap   = 100.0,
      title = "Window Headroom",
      fmt   = function(v) sprintf("%.0f%%", v)
    )
  )
}

#' Grade -> dark fill color (inner ring + center text)
#' @keywords internal
#' @noRd
.capacity_grade_colors <- c(
  Bad     = "#C75B5B",
  Warn    = "#D4923A",
  OK      = "#2D9B83",
  Info    = "#4878A8",
  "NA"    = "#B0BEC5"
)

#' Grade -> light tint color (outer-rim zone band)
#' @keywords internal
#' @noRd
.capacity_zone_tints <- c(
  Bad  = "#F4D6D6",
  Warn = "#F4E4C9",
  OK   = "#C7E8DE",
  Info = "#C5D6E8"
)

#' Per-KPI normalized zone bands (in 0..1 units)
#'
#' Each KPI's zone bands are computed from its threshold table and the
#' visual cap, expressed in the shared 0..1 normalized space used by the
#' gauge. Bands that fall outside the visible range (e.g. cycle headroom
#' Bad at negative values) are omitted -- the Bad state surfaces via the
#' empty inner ring + red center text instead.
#'
#' @keywords internal
#' @noRd
.capacity_zone_bands <- function(thresholds, specs) {
  list(
    filled_window_ratio = data.frame(
      grade = c("Bad", "Warn", "OK"),
      vmin  = c(0,
                thresholds$filled_window_ratio$bad,
                thresholds$filled_window_ratio$warn),
      vmax  = c(thresholds$filled_window_ratio$bad,
                thresholds$filled_window_ratio$warn,
                1.0),
      stringsAsFactors = FALSE
    ),
    dppp_headroom_x = data.frame(
      grade = c("Bad", "OK", "Info"),
      vmin  = c(0,
                thresholds$dppp_headroom_x$bad  / specs$dppp_headroom_x$cap,
                thresholds$dppp_headroom_x$info / specs$dppp_headroom_x$cap),
      vmax  = c(thresholds$dppp_headroom_x$bad  / specs$dppp_headroom_x$cap,
                thresholds$dppp_headroom_x$info / specs$dppp_headroom_x$cap,
                1.0),
      stringsAsFactors = FALSE
    ),
    cycle_time_headroom_pct = data.frame(
      grade = c("OK", "Info"),
      vmin  = c(0,
                thresholds$cycle_time_headroom_pct$info /
                  specs$cycle_time_headroom_pct$cap),
      vmax  = c(thresholds$cycle_time_headroom_pct$info /
                  specs$cycle_time_headroom_pct$cap,
                1.0),
      stringsAsFactors = FALSE
    ),
    window_count_headroom_pct = data.frame(
      grade = c("OK", "Info"),
      vmin  = c(0,
                thresholds$window_count_headroom_pct$info /
                  specs$window_count_headroom_pct$cap),
      vmax  = c(thresholds$window_count_headroom_pct$info /
                  specs$window_count_headroom_pct$cap,
                1.0),
      stringsAsFactors = FALSE
    )
  )
}


# =============================================================================
# Internal: half-circle polygon generator
# =============================================================================

#' Generate an annular arc polygon between two normalized values
#'
#' Returns a data.frame of (x, y) vertices forming a closed annular arc
#' polygon. The arc spans normalized values `v_start..v_end` on a unit
#' half-circle: v = 0 maps to angle pi (left tick), v = 1 maps to angle 0
#' (right tick). Polygon goes outward along the outer radius, then back
#' along the inner radius, closing the loop.
#'
#' @param v_start Numeric, normalized start value in 0..1.
#' @param v_end Numeric, normalized end value in 0..1 (must be >= v_start).
#' @param r_inner Numeric, inner radius.
#' @param r_outer Numeric, outer radius.
#' @param n_seg Integer, number of segments along the arc (default 60).
#' @return data.frame with columns `x`, `y`.
#' @keywords internal
#' @noRd
.arc_polygon <- function(v_start, v_end, r_inner, r_outer, n_seg = 60) {
  # Empty arc -> zero-width polygon (degenerate; drop via NULL caller-side)
  if (v_end <= v_start) return(NULL)

  # Map v in [0, 1] -> angle in [pi, 0] (left to right across the top)
  a_start <- pi - v_start * pi
  a_end   <- pi - v_end   * pi

  angles_out <- seq(a_start, a_end, length.out = n_seg)
  angles_in  <- rev(angles_out)

  data.frame(
    x = c(cos(angles_out) * r_outer, cos(angles_in) * r_inner),
    y = c(sin(angles_out) * r_outer, sin(angles_in) * r_inner),
    stringsAsFactors = FALSE
  )
}


# =============================================================================
# Main: plot_capacity_kpis
# =============================================================================

#' Plot Acquisition Capacity KPI Gauges
#'
#' Renders the four capacity KPIs from [get_capacity_kpis()] as a single
#' ggplot strip of four half-circle gauges drawn from direct cartesian
#' polygons (no `coord_polar`). Each gauge has an outer-rim
#' `Bad / Warn / OK / Info` zone band (light tints, scale reference) and an
#' inner ring filled to the current value in the grade color. Center text
#' shows the raw value. The DPPP gauge visually saturates at 5x; the
#' center text shows the actual value (Astral commonly reports >= 30x).
#' When `kpis$is_spec_limited` is TRUE, the window-headroom panel title is
#' annotated `(spec-limited)`.
#'
#' Shiny-only by design (no PDF report entry). Called from
#' `output$capacity_dashboard` in `inst/shiny_app/server_optimization.R`.
#'
#' @param kpis List returned by [get_capacity_kpis()].
#' @param thresholds Threshold list from [capacity_kpi_thresholds()]
#'   (defaults to `kpis$thresholds`).
#' @return A `ggplot` object.
#' @export
#'
#' @examples
#' \dontrun{
#' kpis <- get_capacity_kpis(plan, windows, evaluation)
#' plot_capacity_kpis(kpis)
#' }
plot_capacity_kpis <- function(kpis,
                               thresholds = kpis$thresholds %||%
                                            capacity_kpi_thresholds()) {

  specs        <- .capacity_kpi_visual_specs()
  values       <- kpis$values
  grades       <- kpis$grades
  spec_limited <- isTRUE(kpis$is_spec_limited)
  kpi_names    <- names(specs)

  # Panel titles (with optional spec-limited badge on the window gauge)
  panel_titles <- vapply(kpi_names, function(nm) {
    title <- specs[[nm]]$title
    if (spec_limited && identical(nm, "window_count_headroom_pct")) {
      title <- paste0(title, " (spec-limited)")
    }
    title
  }, character(1))
  panel_factor <- factor(panel_titles, levels = panel_titles)

  # Radii (in normalized units; outer rim is a narrow band beyond inner ring)
  R_INNER_BOTTOM <- 0.45
  R_INNER_TOP    <- 0.85
  R_RIM_BOTTOM   <- 0.88
  R_RIM_TOP      <- 1.00
  N_SEG          <- 60

  # ---- Inner ring base (full half-circle, pale neutral) --------------------
  base_rows <- lapply(kpi_names, function(nm) {
    poly <- .arc_polygon(0, 1, R_INNER_BOTTOM, R_INNER_TOP, N_SEG)
    if (is.null(poly)) return(NULL)
    poly$kpi   <- panel_factor[match(nm, kpi_names)]
    poly$group <- paste0("base_", nm)
    poly
  })
  base_df <- do.call(rbind, base_rows)

  # ---- Inner ring current-value fill ---------------------------------------
  fill_rows <- lapply(kpi_names, function(nm) {
    spec  <- specs[[nm]]
    val   <- values[[nm]]
    grade <- grades[[nm]]

    norm <- if (is.na(val) || identical(grade, "NA")) {
      0
    } else {
      max(0, min(val, spec$cap)) / spec$cap
    }

    if (norm <= 0) return(NULL)

    poly <- .arc_polygon(0, norm, R_INNER_BOTTOM, R_INNER_TOP, N_SEG)
    if (is.null(poly)) return(NULL)
    poly$kpi   <- panel_factor[match(nm, kpi_names)]
    poly$group <- paste0("fill_", nm)
    poly$fill  <- unname(.capacity_grade_colors[[grade]])
    poly
  })
  fill_df <- do.call(rbind, Filter(Negate(is.null), fill_rows))

  # ---- Outer rim zone bands ------------------------------------------------
  zone_table <- .capacity_zone_bands(thresholds, specs)
  zone_rows <- list()
  for (nm in kpi_names) {
    bands <- zone_table[[nm]]
    for (i in seq_len(nrow(bands))) {
      poly <- .arc_polygon(bands$vmin[i], bands$vmax[i],
                           R_RIM_BOTTOM, R_RIM_TOP, N_SEG)
      if (is.null(poly)) next
      poly$kpi   <- panel_factor[match(nm, kpi_names)]
      poly$group <- paste0("zone_", nm, "_", bands$grade[i])
      poly$fill  <- unname(.capacity_zone_tints[bands$grade[i]])
      zone_rows[[length(zone_rows) + 1L]] <- poly
    }
  }
  zones_df <- do.call(rbind, zone_rows)

  # ---- Center text ---------------------------------------------------------
  center_rows <- lapply(kpi_names, function(nm) {
    spec  <- specs[[nm]]
    val   <- values[[nm]]
    grade <- grades[[nm]]

    if (is.na(val) || identical(grade, "NA")) {
      label      <- "N/A"
      text_color <- "#78909C"
    } else {
      label      <- spec$fmt(val)
      text_color <- unname(.capacity_grade_colors[[grade]])
    }

    data.frame(
      kpi        = panel_factor[match(nm, kpi_names)],
      x          = 0,
      y          = 0.18,   # slightly above the baseline, inside the arc
      label      = label,
      text_color = text_color,
      stringsAsFactors = FALSE
    )
  })
  centers_df <- do.call(rbind, center_rows)

  # ---- Plot ----------------------------------------------------------------
  p <- ggplot2::ggplot() +
    # Inner ring base (pale neutral)
    ggplot2::geom_polygon(
      data = base_df,
      ggplot2::aes(x = .data$x, y = .data$y, group = .data$group),
      fill = "#F1F2F4"
    )

  if (!is.null(fill_df) && nrow(fill_df) > 0) {
    p <- p + ggplot2::geom_polygon(
      data = fill_df,
      ggplot2::aes(x = .data$x, y = .data$y,
                   group = .data$group, fill = .data$fill)
    )
  }

  if (!is.null(zones_df) && nrow(zones_df) > 0) {
    p <- p + ggplot2::geom_polygon(
      data = zones_df,
      ggplot2::aes(x = .data$x, y = .data$y,
                   group = .data$group, fill = .data$fill)
    )
  }

  p <- p +
    # Center text (raw value, grade color)
    ggplot2::geom_text(
      data = centers_df,
      ggplot2::aes(x = .data$x, y = .data$y,
                   label = .data$label, color = .data$text_color),
      size = 9, fontface = "bold", vjust = 0
    ) +
    ggplot2::scale_fill_identity() +
    ggplot2::scale_color_identity() +
    # Suppress any phantom guides from identity-mapped fill/color aes
    # (future-proof against theme changes that set legend.position).
    ggplot2::guides(color = "none", fill = "none") +
    # coord_fixed forces 1:1 aspect; xlim/ylim then control the panel shape.
    # xlim width 2.10 + ylim height 1.05 -> 2:1 panel aspect, so the
    # half-circle fills the panel without an empty lower half.
    ggplot2::coord_fixed(xlim = c(-1.05, 1.05),
                         ylim = c(0, 1.05),
                         expand = FALSE,
                         clip = "off") +
    ggplot2::facet_wrap(~ kpi, ncol = 4) +
    ggplot2::labs(x = NULL, y = NULL) +
    theme_aidia(base_size = 11) +
    ggplot2::theme(
      axis.text   = ggplot2::element_blank(),
      axis.ticks  = ggplot2::element_blank(),
      axis.line   = ggplot2::element_blank(),
      panel.grid  = ggplot2::element_blank(),
      strip.text  = ggplot2::element_text(face = "bold", size = 14,
                                          color = "gray15",
                                          margin = ggplot2::margin(b = 4)),
      strip.background = ggplot2::element_blank(),
      plot.margin   = ggplot2::margin(2, 2, 2, 2),
      panel.spacing = ggplot2::unit(0.2, "lines")
    )

  p
}
