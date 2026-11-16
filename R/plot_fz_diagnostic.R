# Retain m/z when diagnosing a candidate chosen from the pooled phase profile.
# The map and local counts describe the full boundary lattice, not actual loss.
prepare_fz_diagnostic <- function(profile, by_charge = FALSE) {
  rows <- profile$precursors
  if (!nrow(rows)) return(data.frame())
  if (!by_charge) rows$charge <- factor(rep("All charges", nrow(rows)))
  rows$mz_lower <- floor(rows$mz / 10) * 10
  rows$phase_lower <- pmin(99L, floor(rows$phase / OPTIMAL_INCREMENT * 100)) *
    OPTIMAL_INCREMENT / 100
  cells <- stats::aggregate(list(n = rep(1L, nrow(rows))),
    rows[c("charge", "mz_lower", "phase_lower")], sum)
  strip <- interaction(cells$charge, cells$mz_lower, drop = TRUE)
  cells$fraction <- cells$n / ave(cells$n, strip, FUN = sum)
  cells
}

summarize_fz_mz_bins <- function(profile, offset, margin, by_charge = FALSE) {
  # Reuse the scorer's input validation; counts below use exact, unbinned phases.
  count_fz_margin(numeric(), offset, margin)
  rows <- profile$precursors
  if (!nrow(rows)) return(data.frame())
  if (!by_charge) rows$charge <- factor(rep("All charges", nrow(rows)))
  rows$mz_lower <- floor(rows$mz / 50) * 50
  distance <- abs((rows$phase - offset + OPTIMAL_INCREMENT / 2) %%
    OPTIMAL_INCREMENT - OPTIMAL_INCREMENT / 2)
  summary <- stats::aggregate(list(n = rep(1L, nrow(rows)),
    near = as.integer(distance <= margin + 1e-10)), rows[c("charge", "mz_lower")], sum)
  summary$fraction <- summary$near / summary$n
  summary[order(-summary$fraction, -summary$near, summary$charge, summary$mz_lower), ]
}

fz_margin_intervals <- function(offset, margin) {
  count_fz_margin(numeric(), offset, margin)
  offset <- offset %% OPTIMAL_INCREMENT
  shifts <- c(-OPTIMAL_INCREMENT, 0, OPTIMAL_INCREMENT)
  band <- data.frame(lower = pmax(0, offset - margin + shifts),
    upper = pmin(OPTIMAL_INCREMENT, offset + margin + shifts))
  band[band$upper > band$lower, , drop = FALSE]
}

plot_fz_diagnostic <- function(cells, offset, margin) {
  if (!nrow(cells)) return(create_insufficient_data_plot(
    title = "Offset by m/z", message = "No valid precursor m/z values"))
  band <- fz_margin_intervals(offset, margin)
  ggplot(cells) +
    geom_rect(aes(xmin = mz_lower, xmax = mz_lower + 10,
      ymin = phase_lower, ymax = phase_lower + OPTIMAL_INCREMENT / 100,
      fill = 100 * fraction)) +
    geom_rect(data = band, aes(ymin = lower, ymax = upper), xmin = -Inf,
      xmax = Inf, inherit.aes = FALSE, fill = aidia_colors$success, alpha = .12) +
    # White under-strokes keep both boundary types legible over dense cells.
    geom_hline(yintercept = unique(c(band$lower, band$upper)),
      color = "white", linetype = "dashed", linewidth = 1.1) +
    geom_hline(yintercept = unique(c(band$lower, band$upper)),
      color = aidia_colors$after_success, linetype = "dashed", linewidth = .55) +
    geom_hline(yintercept = offset, color = "white", linewidth = 1.7) +
    geom_hline(yintercept = offset, color = aidia_colors$after_success, linewidth = 1) +
    facet_grid(charge ~ .) +
    scale_fill_gradientn(colours = c("#E5EDF5", aidia_colors$before, aidia_colors$before_dark),
      values = c(0, .45, 1), trans = "sqrt", limits = c(0, 100),
      breaks = c(0, 5, 25, 100), name = "% within each 10 m/z strip") +
    scale_y_continuous(limits = c(0, OPTIMAL_INCREMENT),
      breaks = c(0, .25, .5, .75, 1), expand = expansion(mult = 0)) +
    scale_x_continuous(expand = expansion(mult = 0)) +
    labs(title = "Offset by m/z",
      subtitle = sprintf("Solid: offset %.4f | dashed: +/-%.3f m/z", offset, margin),
      x = "Precursor m/z", y = "m/z mod 1.00045475") +
    theme_aidia() +
    theme(legend.position = "bottom", panel.grid = element_blank(),
      plot.title = element_text(size = 12), plot.subtitle = element_text(size = 10),
      axis.title = element_text(size = 10))
}
