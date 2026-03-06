# generate_schematic_previews.R - Generate schematic diagrams for Shiny previews
# Run: source("tests/manual/generate_schematic_previews.R")
#
# Creates conceptual diagrams using synthetic data to illustrate:
#   1. Window modes: fixed vs density vs staggered
#   2. Strategy concepts: how each defines m/z boundaries (1D algorithm view)

devtools::load_all(quiet = TRUE)

output_dir <- "inst/shiny_app/www/strategy_previews"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# =====================================================================
# Color palette (consistent with aidia design system)
# =====================================================================
col_window   <- "#3498DB"   # Blue - window fill
col_boundary <- "#2C3E50"   # Dark - boundary lines
col_precursor <- "#F39C12"  # Orange - precursor dots
col_density  <- "#E74C3C"   # Red - density curve
col_stagger  <- "#9B59B6"   # Purple - staggered offset
col_bg       <- "gray96"
col_grid     <- "gray88"
col_excluded <- "#CCCCCC"   # Gray - excluded points
col_included <- "#2ECC71"   # Green - included/selected
col_optimal  <- "#E74C3C"   # Red - optimal/best

# Common theme for strategy schematics
theme_schematic <- function() {
  theme_aidia() +
    theme(
      axis.text.y = element_blank(),
      axis.ticks.y = element_blank(),
      panel.grid.major.y = element_blank(),
      panel.grid.minor = element_blank(),
      plot.title = element_text(size = 15, face = "bold"),
      plot.subtitle = element_text(size = 10.5, color = "gray45"),
      plot.margin = margin(10, 15, 10, 15)
    )
}


# =====================================================================
# 1. Window Mode Schematics (fixed / density / staggered)
# =====================================================================
cat("--- Generating window mode schematics ---\n")

# Synthetic precursor distribution: bimodal in m/z
set.seed(42)
n_prec <- 300
mz_synth <- c(
  rnorm(180, mean = 550, sd = 40),   # Dense region
  rnorm(80, mean = 750, sd = 60),    # Sparse region
  rnorm(40, mean = 900, sd = 25)     # Small cluster
)
mz_synth <- mz_synth[mz_synth >= 400 & mz_synth <= 1000]

mz_range <- c(400, 1000)
n_windows <- 12

# --- Fixed windows ---
fixed_width <- (mz_range[2] - mz_range[1]) / n_windows
fixed_starts <- seq(mz_range[1], mz_range[2] - fixed_width, length.out = n_windows)
fixed_df <- data.frame(
  xmin = fixed_starts,
  xmax = fixed_starts + fixed_width,
  ymin = 0, ymax = 1,
  id = seq_along(fixed_starts)
)

# --- Density windows (narrow in dense, wide in sparse) ---
mz_sorted <- sort(mz_synth)
n_per_window <- ceiling(length(mz_sorted) / n_windows)
density_starts <- numeric(n_windows)
density_ends <- numeric(n_windows)
for (i in 1:n_windows) {
  idx_start <- (i - 1) * n_per_window + 1
  idx_end <- min(i * n_per_window, length(mz_sorted))
  if (idx_start > length(mz_sorted)) {
    density_starts[i] <- density_ends[i - 1]
    density_ends[i] <- mz_range[2]
  } else {
    density_starts[i] <- if (i == 1) mz_range[1] else density_ends[i - 1]
    density_ends[i] <- if (i == n_windows) mz_range[2] else mz_sorted[idx_end]
  }
}
density_df <- data.frame(
  xmin = density_starts,
  xmax = density_ends,
  ymin = 0, ymax = 1,
  id = 1:n_windows
)

# --- Staggered windows (alternating offset between odd/even cycles) ---
stagger_offset <- fixed_width * 0.5
odd_starts <- fixed_starts
even_starts <- fixed_starts + stagger_offset
even_starts <- even_starts[even_starts + fixed_width <= mz_range[2] + 1]

stagger_odd <- data.frame(
  xmin = odd_starts, xmax = odd_starts + fixed_width,
  ymin = 0.52, ymax = 1.0, cycle = "Odd cycle",
  id = seq_along(odd_starts)
)
stagger_even <- data.frame(
  xmin = even_starts, xmax = even_starts + fixed_width,
  ymin = 0.0, ymax = 0.48, cycle = "Even cycle",
  id = seq_along(even_starts)
)

# Precursor rug data
prec_df <- data.frame(mz = mz_synth)

# Density curve
dens <- density(mz_synth, from = mz_range[1], to = mz_range[2], n = 200)
dens_df <- data.frame(x = dens$x, y = dens$y / max(dens$y))

# === Plot: Fixed ===
p_fixed <- ggplot() +
  geom_rect(data = fixed_df,
            aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
            fill = col_window, alpha = 0.25, color = col_boundary, linewidth = 0.4) +
  geom_line(data = dens_df, aes(x = x, y = y),
            color = col_density, linewidth = 0.8, alpha = 0.7) +
  geom_rug(data = prec_df, aes(x = mz), sides = "b",
           color = col_precursor, alpha = 0.4, length = unit(0.04, "npc")) +
  scale_x_continuous(limits = mz_range, expand = c(0, 0)) +
  scale_y_continuous(limits = c(-0.08, 1.05), expand = c(0, 0)) +
  labs(title = "Fixed Width", subtitle = "Equal-width windows across m/z range",
       x = "m/z (Da)", y = NULL) +
  annotate("text", x = 550, y = 0.92, label = "Dense region:\nsame width",
           size = 3, color = "gray40", fontface = "italic") +
  annotate("text", x = 900, y = 0.92, label = "Sparse region:\nsame width",
           size = 3, color = "gray40", fontface = "italic") +
  theme_schematic()

# === Plot: Density ===
p_density <- ggplot() +
  geom_rect(data = density_df,
            aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
            fill = col_window, alpha = 0.25, color = col_boundary, linewidth = 0.4) +
  geom_line(data = dens_df, aes(x = x, y = y),
            color = col_density, linewidth = 0.8, alpha = 0.7) +
  geom_rug(data = prec_df, aes(x = mz), sides = "b",
           color = col_precursor, alpha = 0.4, length = unit(0.04, "npc")) +
  scale_x_continuous(limits = mz_range, expand = c(0, 0)) +
  scale_y_continuous(limits = c(-0.08, 1.05), expand = c(0, 0)) +
  labs(title = "Density (Variable Width)", subtitle = "Narrow where dense, wide where sparse",
       x = "m/z (Da)", y = NULL) +
  annotate("segment", x = 520, xend = 580, y = 0.92, yend = 0.92,
           arrow = arrow(ends = "both", length = unit(0.08, "inches")),
           color = "gray40", linewidth = 0.5) +
  annotate("text", x = 550, y = 0.97, label = "Narrow", size = 3, color = "gray40") +
  annotate("segment", x = 820, xend = 920, y = 0.92, yend = 0.92,
           arrow = arrow(ends = "both", length = unit(0.08, "inches")),
           color = "gray40", linewidth = 0.5) +
  annotate("text", x = 870, y = 0.97, label = "Wide", size = 3, color = "gray40") +
  theme_schematic()

# === Plot: Staggered ===
p_staggered <- ggplot() +
  geom_rect(data = stagger_odd,
            aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
            fill = col_window, alpha = 0.25, color = col_boundary, linewidth = 0.4) +
  geom_rect(data = stagger_even,
            aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
            fill = col_stagger, alpha = 0.20, color = col_stagger, linewidth = 0.4) +
  geom_hline(yintercept = 0.50, linetype = "dashed", color = "gray60", linewidth = 0.4) +
  annotate("text", x = mz_range[1] + 10, y = 0.76, label = "Odd cycle",
           hjust = 0, size = 3.2, fontface = "bold", color = col_boundary) +
  annotate("text", x = mz_range[1] + 10, y = 0.24, label = "Even cycle (offset)",
           hjust = 0, size = 3.2, fontface = "bold", color = col_stagger) +
  annotate("segment", x = fixed_starts[3], xend = even_starts[3],
           y = 0.50, yend = 0.50,
           arrow = arrow(ends = "both", length = unit(0.06, "inches")),
           color = col_density, linewidth = 0.6) +
  annotate("text", x = (fixed_starts[3] + even_starts[3]) / 2, y = 0.545,
           label = "offset", size = 2.8, color = col_density) +
  scale_x_continuous(limits = mz_range, expand = c(0, 0)) +
  scale_y_continuous(limits = c(-0.02, 1.05), expand = c(0, 0)) +
  labs(title = "Staggered (Offset)", subtitle = "Alternating half-window shift reduces boundary blind spots",
       x = "m/z (Da)", y = NULL) +
  theme_schematic()

# === Combined 3-panel ===
p_modes <- gridExtra::arrangeGrob(
  p_fixed, p_density, p_staggered,
  ncol = 1,
  top = grid::textGrob(
    "Window Placement Modes",
    gp = grid::gpar(fontsize = 16, fontface = "bold")
  ),
  bottom = grid::textGrob(
    "Orange ticks = precursors | Red curve = density | Blue/Purple = isolation windows",
    gp = grid::gpar(fontsize = 9, col = "gray50")
  )
)

ggsave(file.path(output_dir, "schematic_window_modes.png"), p_modes,
       width = 10, height = 10, dpi = 150, bg = "white")
cat("  Saved: schematic_window_modes.png\n")

# Also save individual panels
ggsave(file.path(output_dir, "schematic_mode_fixed.png"), p_fixed,
       width = 9, height = 3.5, dpi = 150, bg = "white")
ggsave(file.path(output_dir, "schematic_mode_density.png"), p_density,
       width = 9, height = 3.5, dpi = 150, bg = "white")
ggsave(file.path(output_dir, "schematic_mode_staggered.png"), p_staggered,
       width = 9, height = 3.5, dpi = 150, bg = "white")
cat("  Saved: individual mode panels\n")


# =====================================================================
# 2. Strategy Concept Schematics (1D algorithm view)
# =====================================================================
cat("\n--- Generating strategy concept schematics ---\n")

# Synthetic m/z data: skewed distribution with clear outliers
set.seed(777)
mz_main <- c(
  rnorm(200, mean = 600, sd = 50),    # Main cluster
  rnorm(80, mean = 750, sd = 30),     # Secondary cluster
  rnorm(15, mean = 450, sd = 20),     # Left outlier group
  rnorm(10, mean = 920, sd = 15)      # Right outlier group
)
mz_main <- sort(mz_main[mz_main >= 380 & mz_main <= 980])
n_total <- length(mz_main)

# Compute shared statistics
mz_mean <- mean(mz_main)
mz_sd <- sd(mz_main)
mz_q05 <- quantile(mz_main, 0.05)
mz_q95 <- quantile(mz_main, 0.95)
mz_dens <- density(mz_main, from = 380, to = 980, n = 500)
dens_curve <- data.frame(x = mz_dens$x, y = mz_dens$y / max(mz_dens$y))

# Histogram bin data for bar plots
hist_data <- data.frame(mz = mz_main)

# y-height for annotations
y_ann <- 1.08
y_label <- 1.18

# Common axis limits
xlims <- c(380, 980)


# =====================================================================
# GREEDY: Fixed-width window slides to find best position
# =====================================================================
cat("  Generating greedy schematic...\n")

greedy_width <- 200  # Fixed window width (Da)

# Try 3 candidate positions
candidates <- data.frame(
  pos = c(1, 2, 3),
  start = c(420, 520, 570),
  label = c("Position A", "Position B", "Position C (Best)")
)
candidates$end <- candidates$start + greedy_width

# Count precursors in each position
candidates$count <- sapply(1:nrow(candidates), function(i) {
  sum(mz_main >= candidates$start[i] & mz_main <= candidates$end[i])
})

# Mark precursors: inside best window vs outside
best_idx <- which.max(candidates$count)
best_start <- candidates$start[best_idx]
best_end <- candidates$end[best_idx]

point_df <- data.frame(
  mz = mz_main,
  y = runif(n_total, 0.02, 0.30),
  inside = mz_main >= best_start & mz_main <= best_end
)

# Candidate windows as rectangles at different y-levels
cand_rects <- data.frame(
  xmin = candidates$start,
  xmax = candidates$end,
  ymin = c(0.38, 0.58, 0.78),
  ymax = c(0.50, 0.70, 0.92),
  label = candidates$label,
  count = candidates$count,
  is_best = c(FALSE, FALSE, TRUE)
)

p_greedy <- ggplot() +
  # Precursor points (colored by best window membership)
  geom_point(data = point_df, aes(x = mz, y = y, color = inside),
             size = 1.3, alpha = 0.5, show.legend = FALSE) +
  scale_color_manual(values = c("TRUE" = col_included, "FALSE" = col_excluded)) +
  # Non-best candidate windows (dashed, gray)
  geom_rect(data = cand_rects[!cand_rects$is_best, ],
            aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
            fill = "gray80", alpha = 0.15, color = "gray50",
            linetype = "dashed", linewidth = 0.5) +
  # Best candidate window (solid, strategy color)
  geom_rect(data = cand_rects[cand_rects$is_best, ],
            aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
            fill = aidia_strategy_colors["greedy"], alpha = 0.20,
            color = aidia_strategy_colors["greedy"], linewidth = 1.0) +
  # Labels for each candidate
  annotate("text",
           x = cand_rects$xmin - 5,
           y = (cand_rects$ymin + cand_rects$ymax) / 2,
           label = sprintf("%s\nn = %d", cand_rects$label, cand_rects$count),
           hjust = 1, size = 3.0,
           color = ifelse(cand_rects$is_best, aidia_strategy_colors["greedy"], "gray50"),
           fontface = ifelse(cand_rects$is_best, "bold", "plain")) +
  # Width annotation on best window
  annotate("segment",
           x = best_start, xend = best_end,
           y = 0.96, yend = 0.96,
           arrow = arrow(ends = "both", length = unit(0.06, "inches")),
           color = aidia_strategy_colors["greedy"], linewidth = 0.6) +
  annotate("text", x = (best_start + best_end) / 2, y = 1.01,
           label = sprintf("Fixed %d Da", greedy_width),
           size = 3.2, fontface = "bold", color = aidia_strategy_colors["greedy"]) +
  # Sliding arrow
  annotate("segment", x = 480, xend = 630, y = 0.35, yend = 0.35,
           arrow = arrow(length = unit(0.1, "inches")),
           color = "gray40", linewidth = 0.5) +
  annotate("text", x = 555, y = 0.37, label = "slide window",
           size = 2.8, color = "gray40", fontface = "italic") +
  scale_x_continuous(limits = xlims, expand = c(0.02, 0)) +
  scale_y_continuous(limits = c(-0.02, 1.15), expand = c(0, 0)) +
  labs(
    title = "Greedy (MacCoss Lab)",
    subtitle = sprintf("Slide a fixed-width window (%d Da) to the position capturing the most precursors", greedy_width),
    x = "m/z (Da)", y = NULL
  ) +
  theme_schematic() +
  theme(plot.title = element_text(color = aidia_strategy_colors["greedy"]))

ggsave(file.path(output_dir, "schematic_greedy.png"), p_greedy,
       width = 9, height = 5.5, dpi = 150, bg = "white")
cat("    Saved: schematic_greedy.png\n")


# =====================================================================
# KDE: Find density peak, expand outward until threshold
# =====================================================================
cat("  Generating KDE schematic...\n")

kde_threshold <- 0.10
dens_above <- dens_curve$y >= kde_threshold
kde_start <- min(dens_curve$x[dens_above])
kde_end <- max(dens_curve$x[dens_above])

# Peak location
peak_x <- dens_curve$x[which.max(dens_curve$y)]

# Split density curve: above vs below threshold
dens_above_df <- dens_curve[dens_above, ]
dens_below_df <- dens_curve[!dens_above, ]

point_kde <- data.frame(
  mz = mz_main,
  y = runif(n_total, -0.06, -0.02),
  inside = mz_main >= kde_start & mz_main <= kde_end
)

p_kde <- ggplot() +
  # Shaded area above threshold
  geom_ribbon(data = dens_above_df,
              aes(x = x, ymin = kde_threshold, ymax = y),
              fill = aidia_strategy_colors["kde"], alpha = 0.20) +
  # Full density curve
  geom_line(data = dens_curve, aes(x = x, y = y),
            color = aidia_strategy_colors["kde"], linewidth = 1.0) +
  # Threshold line
  geom_hline(yintercept = kde_threshold, linetype = "dashed",
             color = col_optimal, linewidth = 0.5) +
  annotate("text", x = xlims[2] - 5, y = kde_threshold + 0.03,
           label = sprintf("Threshold = %.0f%%", kde_threshold * 100),
           hjust = 1, size = 3.0, color = col_optimal, fontface = "bold") +
  # Peak marker
  annotate("point", x = peak_x, y = 1.0,
           size = 3, shape = 18, color = aidia_strategy_colors["kde"]) +
  annotate("text", x = peak_x, y = 1.07,
           label = "Density\npeak", size = 2.8, fontface = "bold",
           color = aidia_strategy_colors["kde"]) +
  # Expansion arrows from peak
  annotate("segment", x = peak_x, xend = kde_start, y = 0.5, yend = 0.5,
           arrow = arrow(length = unit(0.08, "inches")),
           color = "gray40", linewidth = 0.4) +
  annotate("segment", x = peak_x, xend = kde_end, y = 0.5, yend = 0.5,
           arrow = arrow(length = unit(0.08, "inches")),
           color = "gray40", linewidth = 0.4) +
  annotate("text", x = peak_x, y = 0.54,
           label = "expand until threshold", size = 2.7,
           color = "gray40", fontface = "italic") +
  # Boundary lines
  geom_vline(xintercept = c(kde_start, kde_end),
             color = aidia_strategy_colors["kde"], linewidth = 0.7, linetype = "solid") +
  # Precursor rug (colored)
  geom_point(data = point_kde, aes(x = mz, y = y, color = inside),
             size = 1.0, alpha = 0.5, show.legend = FALSE) +
  scale_color_manual(values = c("TRUE" = aidia_strategy_colors["kde"],
                                "FALSE" = col_excluded)) +
  scale_x_continuous(limits = xlims, expand = c(0.02, 0)) +
  scale_y_continuous(limits = c(-0.10, 1.20), expand = c(0, 0)) +
  labs(
    title = "KDE (Kernel Density Estimation)",
    subtitle = "Find density peak, expand boundaries until density drops below threshold",
    x = "m/z (Da)", y = "Relative density"
  ) +
  theme_schematic() +
  theme(
    plot.title = element_text(color = aidia_strategy_colors["kde"]),
    axis.text.y = element_text(size = 8),
    axis.ticks.y = element_line()
  )

ggsave(file.path(output_dir, "schematic_kde.png"), p_kde,
       width = 9, height = 5.5, dpi = 150, bg = "white")
cat("    Saved: schematic_kde.png\n")


# =====================================================================
# QUANTILE: Take P5-P95, trim both tails
# =====================================================================
cat("  Generating quantile schematic...\n")

q_lower <- 0.05
q_upper <- 0.95
q_lo_val <- as.numeric(quantile(mz_main, q_lower))
q_hi_val <- as.numeric(quantile(mz_main, q_upper))

point_q <- data.frame(
  mz = mz_main,
  y = runif(n_total, 0.02, 0.25),
  region = ifelse(mz_main < q_lo_val, "left_tail",
                  ifelse(mz_main > q_hi_val, "right_tail", "included"))
)

n_included <- sum(point_q$region == "included")
n_left <- sum(point_q$region == "left_tail")
n_right <- sum(point_q$region == "right_tail")

p_quantile <- ggplot() +
  # Density curve
  geom_line(data = dens_curve, aes(x = x, y = y * 0.65 + 0.30),
            color = "gray70", linewidth = 0.6) +
  # Shaded tails on density
  geom_ribbon(data = dens_curve[dens_curve$x <= q_lo_val, ],
              aes(x = x, ymin = 0.30, ymax = y * 0.65 + 0.30),
              fill = col_excluded, alpha = 0.4) +
  geom_ribbon(data = dens_curve[dens_curve$x >= q_hi_val, ],
              aes(x = x, ymin = 0.30, ymax = y * 0.65 + 0.30),
              fill = col_excluded, alpha = 0.4) +
  # Included region on density
  geom_ribbon(data = dens_curve[dens_curve$x >= q_lo_val & dens_curve$x <= q_hi_val, ],
              aes(x = x, ymin = 0.30, ymax = y * 0.65 + 0.30),
              fill = aidia_strategy_colors["quantile"], alpha = 0.15) +
  # Precursor dots (colored by region)
  geom_point(data = point_q, aes(x = mz, y = y, color = region),
             size = 1.3, alpha = 0.5, show.legend = FALSE) +
  scale_color_manual(values = c(
    "included" = aidia_strategy_colors["quantile"],
    "left_tail" = col_excluded,
    "right_tail" = col_excluded
  )) +
  # Boundary lines
  geom_vline(xintercept = q_lo_val, color = aidia_strategy_colors["quantile"],
             linewidth = 1.0, linetype = "solid") +
  geom_vline(xintercept = q_hi_val, color = aidia_strategy_colors["quantile"],
             linewidth = 1.0, linetype = "solid") +
  # P5 / P95 labels
  annotate("text", x = q_lo_val, y = 1.02,
           label = sprintf("P5 = %.0f Da", q_lo_val),
           size = 3.3, fontface = "bold", color = aidia_strategy_colors["quantile"],
           hjust = 0.5) +
  annotate("text", x = q_hi_val, y = 1.02,
           label = sprintf("P95 = %.0f Da", q_hi_val),
           size = 3.3, fontface = "bold", color = aidia_strategy_colors["quantile"],
           hjust = 0.5) +
  # Tail annotations
  annotate("text", x = (xlims[1] + q_lo_val) / 2, y = 0.15,
           label = sprintf("Excluded\n%d (%.0f%%)", n_left, n_left/n_total*100),
           size = 2.8, color = "gray50", fontface = "italic") +
  annotate("text", x = (xlims[2] + q_hi_val) / 2, y = 0.15,
           label = sprintf("Excluded\n%d (%.0f%%)", n_right, n_right/n_total*100),
           size = 2.8, color = "gray50", fontface = "italic") +
  # Center bracket
  annotate("segment", x = q_lo_val + 5, xend = q_hi_val - 5,
           y = 1.10, yend = 1.10,
           arrow = arrow(ends = "both", length = unit(0.06, "inches")),
           color = aidia_strategy_colors["quantile"], linewidth = 0.5) +
  annotate("text", x = (q_lo_val + q_hi_val) / 2, y = 1.15,
           label = sprintf("90%% of data (%d precursors)", n_included),
           size = 3.0, color = aidia_strategy_colors["quantile"], fontface = "bold") +
  scale_x_continuous(limits = xlims, expand = c(0.02, 0)) +
  scale_y_continuous(limits = c(-0.02, 1.22), expand = c(0, 0)) +
  labs(
    title = "Quantile (Percentile Trim)",
    subtitle = sprintf("Keep precursors between P%.0f and P%.0f, discard both tails",
                        q_lower * 100, q_upper * 100),
    x = "m/z (Da)", y = NULL
  ) +
  theme_schematic() +
  theme(plot.title = element_text(color = aidia_strategy_colors["quantile"]))

ggsave(file.path(output_dir, "schematic_quantile.png"), p_quantile,
       width = 9, height = 5.5, dpi = 150, bg = "white")
cat("    Saved: schematic_quantile.png\n")


# =====================================================================
# OUTLIER: Mean +/- N*SD, mark and remove outliers
# =====================================================================
cat("  Generating outlier schematic...\n")

# Use 2.0 SD for schematic to clearly show outlier exclusion
# (default in package is 3.0 SD, but 2.0 shows the concept better)
sd_mult_display <- 2.0
out_lo <- mz_mean - sd_mult_display * mz_sd
out_hi <- mz_mean + sd_mult_display * mz_sd

point_out <- data.frame(
  mz = mz_main,
  y = runif(n_total, 0.02, 0.25),
  is_outlier = mz_main < out_lo | mz_main > out_hi
)

n_outliers <- sum(point_out$is_outlier)
n_kept <- n_total - n_outliers

p_outlier <- ggplot() +
  # Density curve
  geom_line(data = dens_curve, aes(x = x, y = y * 0.55 + 0.35),
            color = "gray70", linewidth = 0.6) +
  # Filled region between boundaries
  geom_ribbon(data = dens_curve[dens_curve$x >= out_lo & dens_curve$x <= out_hi, ],
              aes(x = x, ymin = 0.35, ymax = y * 0.55 + 0.35),
              fill = aidia_strategy_colors["outlier"], alpha = 0.12) +
  # Excluded tails on density (grayed out)
  geom_ribbon(data = dens_curve[dens_curve$x <= out_lo, ],
              aes(x = x, ymin = 0.35, ymax = y * 0.55 + 0.35),
              fill = col_excluded, alpha = 0.4) +
  geom_ribbon(data = dens_curve[dens_curve$x >= out_hi, ],
              aes(x = x, ymin = 0.35, ymax = y * 0.55 + 0.35),
              fill = col_excluded, alpha = 0.4) +
  # Precursor dots
  geom_point(data = point_out, aes(x = mz, y = y, color = is_outlier, shape = is_outlier),
             size = 1.5, alpha = 0.6, show.legend = FALSE) +
  scale_color_manual(values = c("FALSE" = aidia_strategy_colors["outlier"],
                                 "TRUE" = col_optimal)) +
  scale_shape_manual(values = c("FALSE" = 16, "TRUE" = 4)) +  # X for outliers
  # Mean line
  geom_vline(xintercept = mz_mean, color = "gray30",
             linewidth = 0.6, linetype = "solid") +
  annotate("text", x = mz_mean + 3, y = 1.02,
           label = sprintf("Mean = %.0f", mz_mean),
           hjust = 0, size = 3.0, color = "gray30", fontface = "bold") +
  # Boundary lines
  geom_vline(xintercept = out_lo, color = aidia_strategy_colors["outlier"],
             linewidth = 1.0, linetype = "solid") +
  geom_vline(xintercept = out_hi, color = aidia_strategy_colors["outlier"],
             linewidth = 1.0, linetype = "solid") +
  # SD labels
  annotate("text", x = out_lo, y = 1.02,
           label = sprintf("-2 SD\n%.0f Da", out_lo),
           size = 2.8, fontface = "bold", color = aidia_strategy_colors["outlier"],
           hjust = 0.5) +
  annotate("text", x = out_hi, y = 1.02,
           label = sprintf("+2 SD\n%.0f Da", out_hi),
           size = 2.8, fontface = "bold", color = aidia_strategy_colors["outlier"],
           hjust = 0.5) +
  # SD segments (mean to boundaries)
  annotate("segment", x = mz_mean, xend = out_lo,
           y = 0.92, yend = 0.92,
           arrow = arrow(length = unit(0.06, "inches")),
           color = "gray50", linewidth = 0.4) +
  annotate("segment", x = mz_mean, xend = out_hi,
           y = 0.92, yend = 0.92,
           arrow = arrow(length = unit(0.06, "inches")),
           color = "gray50", linewidth = 0.4) +
  annotate("text", x = (mz_mean + out_lo) / 2, y = 0.95,
           label = sprintf("2 x SD (%.0f)", mz_sd),
           size = 2.5, color = "gray50") +
  # Outlier annotation (left side)
  annotate("label", x = (xlims[1] + out_lo) / 2, y = 0.15,
           label = sprintf("Outliers: %d\n(%.1f%%)",
                           n_outliers, n_outliers/n_total*100),
           size = 2.8, fill = "white", label.size = 0.3,
           color = col_optimal, fontface = "bold") +
  # Kept count (center)
  annotate("text", x = mz_mean, y = 0.30,
           label = sprintf("Kept: %d (%.1f%%)", n_kept, n_kept/n_total*100),
           size = 3.0, color = aidia_strategy_colors["outlier"], fontface = "bold") +
  scale_x_continuous(limits = xlims, expand = c(0.02, 0)) +
  scale_y_continuous(limits = c(-0.02, 1.18), expand = c(0, 0)) +
  labs(
    title = sprintf("Outlier (Mean +/- N x SD)"),
    subtitle = "Use mean and standard deviation to exclude extreme values (shown: N=2 for clarity, default: N=3)",
    x = "m/z (Da)", y = NULL
  ) +
  theme_schematic() +
  theme(plot.title = element_text(color = aidia_strategy_colors["outlier"]))

ggsave(file.path(output_dir, "schematic_outlier.png"), p_outlier,
       width = 9, height = 5.5, dpi = 150, bg = "white")
cat("    Saved: schematic_outlier.png\n")


# =====================================================================
# COVERAGE: Find the narrowest window covering 95% of precursors
# =====================================================================
cat("  Generating coverage schematic...\n")

target_cov <- 0.95
n_need <- ceiling(n_total * target_cov)

# Sliding window approach: find narrowest contiguous range covering 95%
best_width <- Inf
best_lo <- NA
best_hi <- NA
for (i in 1:(n_total - n_need + 1)) {
  lo <- mz_main[i]
  hi <- mz_main[i + n_need - 1]
  w <- hi - lo
  if (w < best_width) {
    best_width <- w
    best_lo <- lo
    best_hi <- hi
  }
}

# Also show a wider "naive" range for comparison (e.g., full range)
naive_lo <- min(mz_main)
naive_hi <- max(mz_main)
naive_width <- naive_hi - naive_lo

point_cov <- data.frame(
  mz = mz_main,
  y = runif(n_total, 0.02, 0.25),
  inside = mz_main >= best_lo & mz_main <= best_hi
)

n_inside <- sum(point_cov$inside)

p_coverage <- ggplot() +
  # Density curve
  geom_line(data = dens_curve, aes(x = x, y = y * 0.50 + 0.45),
            color = "gray70", linewidth = 0.6) +
  # Full range bracket (wide, gray, dashed)
  annotate("rect",
           xmin = naive_lo - 3, xmax = naive_hi + 3,
           ymin = 0.35, ymax = 0.42,
           fill = "gray85", alpha = 0.5, color = "gray50",
           linetype = "dashed", linewidth = 0.4) +
  annotate("text",
           x = (naive_lo + naive_hi) / 2, y = 0.32,
           label = sprintf("Full range: %.0f Da (100%%)", naive_width),
           size = 2.8, color = "gray50") +
  # Optimal narrow range (colored, solid)
  annotate("rect",
           xmin = best_lo, xmax = best_hi,
           ymin = 0.35, ymax = 0.42,
           fill = aidia_strategy_colors["coverage"], alpha = 0.25,
           color = aidia_strategy_colors["coverage"], linewidth = 1.0) +
  # Precursor dots
  geom_point(data = point_cov, aes(x = mz, y = y, color = inside),
             size = 1.3, alpha = 0.5, show.legend = FALSE) +
  scale_color_manual(values = c("TRUE" = aidia_strategy_colors["coverage"],
                                "FALSE" = col_excluded)) +
  # Boundary lines
  geom_vline(xintercept = best_lo, color = aidia_strategy_colors["coverage"],
             linewidth = 1.0) +
  geom_vline(xintercept = best_hi, color = aidia_strategy_colors["coverage"],
             linewidth = 1.0) +
  # Width annotation
  annotate("segment", x = best_lo, xend = best_hi,
           y = 1.05, yend = 1.05,
           arrow = arrow(ends = "both", length = unit(0.06, "inches")),
           color = aidia_strategy_colors["coverage"], linewidth = 0.6) +
  annotate("text", x = (best_lo + best_hi) / 2, y = 1.12,
           label = sprintf("Narrowest %.0f Da covering %d%% (%d precursors)",
                           best_width, round(target_cov * 100), n_inside),
           size = 3.0, fontface = "bold", color = aidia_strategy_colors["coverage"]) +
  # Squeeze arrows
  annotate("segment", x = naive_lo, xend = best_lo,
           y = 0.385, yend = 0.385,
           arrow = arrow(length = unit(0.06, "inches")),
           color = aidia_strategy_colors["coverage"], linewidth = 0.4) +
  annotate("segment", x = naive_hi, xend = best_hi,
           y = 0.385, yend = 0.385,
           arrow = arrow(length = unit(0.06, "inches")),
           color = aidia_strategy_colors["coverage"], linewidth = 0.4) +
  annotate("text", x = (naive_lo + best_lo) / 2, y = 0.46,
           label = "squeeze", size = 2.5, color = aidia_strategy_colors["coverage"],
           fontface = "italic") +
  annotate("text", x = (naive_hi + best_hi) / 2, y = 0.46,
           label = "squeeze", size = 2.5, color = aidia_strategy_colors["coverage"],
           fontface = "italic") +
  scale_x_continuous(limits = xlims, expand = c(0.02, 0)) +
  scale_y_continuous(limits = c(-0.02, 1.20), expand = c(0, 0)) +
  labs(
    title = sprintf("Coverage (Target: %d%%)", round(target_cov * 100)),
    subtitle = "Find the narrowest m/z range that covers the target percentage of precursors",
    x = "m/z (Da)", y = NULL
  ) +
  theme_schematic() +
  theme(plot.title = element_text(color = aidia_strategy_colors["coverage"]))

ggsave(file.path(output_dir, "schematic_coverage.png"), p_coverage,
       width = 9, height = 5.5, dpi = 150, bg = "white")
cat("    Saved: schematic_coverage.png\n")


# =====================================================================
# 3. KDE vs Coverage comparison (bimodal case)
# =====================================================================
cat("\n--- Generating KDE vs Coverage comparison ---\n")

# Strongly bimodal data: two well-separated peaks with a clear valley
set.seed(2026)
mz_bimodal <- c(
  rnorm(160, mean = 520, sd = 30),   # Peak A (dominant)
  rnorm(100, mean = 820, sd = 35)    # Peak B (secondary)
)
mz_bimodal <- sort(mz_bimodal[mz_bimodal >= 380 & mz_bimodal <= 980])
n_bi <- length(mz_bimodal)

# Density curve for bimodal data
bi_dens <- density(mz_bimodal, from = 380, to = 980, n = 500)
bi_curve <- data.frame(x = bi_dens$x, y = bi_dens$y / max(bi_dens$y))

# --- KDE result: with threshold 0.15, the valley is below threshold ---
kde_thresh_bi <- 0.15
bi_above <- bi_curve$y >= kde_thresh_bi
# Find contiguous runs above threshold
runs <- rle(bi_above)
run_starts <- cumsum(c(1, runs$lengths[-length(runs$lengths)]))
# Find the longest TRUE run (= the dominant peak region)
true_runs <- which(runs$values)
run_lengths <- runs$lengths[true_runs]
longest_run <- true_runs[which.max(run_lengths)]
start_idx <- run_starts[longest_run]
end_idx <- start_idx + runs$lengths[longest_run] - 1
kde_lo_bi <- bi_curve$x[start_idx]
kde_hi_bi <- bi_curve$x[end_idx]

# Count precursors in KDE selection
n_kde_in <- sum(mz_bimodal >= kde_lo_bi & mz_bimodal <= kde_hi_bi)
kde_pct <- round(n_kde_in / n_bi * 100)

# --- Coverage result: narrowest range covering 90% ---
cov_target_bi <- 0.90
n_need_bi <- ceiling(n_bi * cov_target_bi)
best_w_bi <- Inf
best_lo_bi <- NA
best_hi_bi <- NA
for (i in 1:(n_bi - n_need_bi + 1)) {
  w <- mz_bimodal[i + n_need_bi - 1] - mz_bimodal[i]
  if (w < best_w_bi) {
    best_w_bi <- w
    best_lo_bi <- mz_bimodal[i]
    best_hi_bi <- mz_bimodal[i + n_need_bi - 1]
  }
}
n_cov_in <- sum(mz_bimodal >= best_lo_bi & mz_bimodal <= best_hi_bi)
cov_pct <- round(n_cov_in / n_bi * 100)

# Precursor point positions (shared y jitter)
set.seed(99)
bi_points <- data.frame(
  mz = mz_bimodal,
  y = runif(n_bi, -0.08, -0.02)
)

# --- Left panel: KDE on bimodal ---
bi_above_df <- bi_curve[bi_above, ]

# Separate the two peak regions for shading
peak_regions <- split(bi_curve[bi_above, ], cumsum(c(1, diff(which(bi_above)) != 1)))

p_kde_bi <- ggplot() +
  # Full density curve
  geom_line(data = bi_curve, aes(x = x, y = y),
            color = aidia_strategy_colors["kde"], linewidth = 1.0) +
  # Threshold line
  geom_hline(yintercept = kde_thresh_bi, linetype = "dashed",
             color = col_optimal, linewidth = 0.5)

# Shade each contiguous above-threshold region
for (region in peak_regions) {
  p_kde_bi <- p_kde_bi +
    geom_ribbon(data = region,
                aes(x = x, ymin = kde_thresh_bi, ymax = y),
                fill = aidia_strategy_colors["kde"], alpha = 0.20)
}

# KDE boundary lines (dominant peak only)
p_kde_bi <- p_kde_bi +
  geom_vline(xintercept = kde_lo_bi, color = aidia_strategy_colors["kde"],
             linewidth = 1.0) +
  geom_vline(xintercept = kde_hi_bi, color = aidia_strategy_colors["kde"],
             linewidth = 1.0) +
  # Threshold label
  annotate("text", x = 975, y = kde_thresh_bi + 0.04,
           label = sprintf("Threshold\n%.0f%%", kde_thresh_bi * 100),
           hjust = 1, size = 2.8, color = col_optimal, fontface = "bold") +
  # Valley annotation
  annotate("text", x = 670, y = 0.08,
           label = "Valley below\nthreshold",
           size = 2.8, color = "gray45", fontface = "italic") +
  annotate("segment", x = 670, y = 0.14, xend = 670, yend = kde_thresh_bi - 0.01,
           arrow = arrow(length = unit(0.05, "inches")),
           color = "gray45", linewidth = 0.3) +
  # Boundary width for dominant peak
  annotate("segment", x = kde_lo_bi, xend = kde_hi_bi,
           y = 1.06, yend = 1.06,
           arrow = arrow(ends = "both", length = unit(0.05, "inches")),
           color = aidia_strategy_colors["kde"], linewidth = 0.5) +
  annotate("text", x = (kde_lo_bi + kde_hi_bi) / 2, y = 1.12,
           label = sprintf("%.0f Da (%d%%)", kde_hi_bi - kde_lo_bi, kde_pct),
           size = 3.0, fontface = "bold", color = aidia_strategy_colors["kde"]) +
  # Precursor dots (colored by KDE selection)
  geom_point(data = transform(bi_points,
               inside = mz >= kde_lo_bi & mz <= kde_hi_bi),
             aes(x = mz, y = y, color = inside),
             size = 1.0, alpha = 0.5, show.legend = FALSE) +
  scale_color_manual(values = c("TRUE" = aidia_strategy_colors["kde"],
                                "FALSE" = col_excluded)) +
  scale_x_continuous(limits = c(380, 980), expand = c(0.02, 0)) +
  scale_y_continuous(limits = c(-0.12, 1.20), expand = c(0, 0)) +
  labs(
    title = "KDE: Selects dominant peak",
    subtitle = "Valley drops below threshold -> secondary peak excluded",
    x = "m/z (Da)", y = "Relative density"
  ) +
  theme_schematic() +
  theme(
    plot.title = element_text(color = aidia_strategy_colors["kde"], size = 13),
    plot.subtitle = element_text(size = 9.5),
    axis.text.y = element_text(size = 8),
    axis.ticks.y = element_line()
  )

# --- Right panel: Coverage on bimodal ---
p_cov_bi <- ggplot() +
  # Full density curve
  geom_line(data = bi_curve, aes(x = x, y = y),
            color = "gray70", linewidth = 0.6) +
  # Shaded region between boundaries
  geom_ribbon(data = bi_curve[bi_curve$x >= best_lo_bi & bi_curve$x <= best_hi_bi, ],
              aes(x = x, ymin = 0, ymax = y),
              fill = aidia_strategy_colors["coverage"], alpha = 0.15) +
  # Boundary lines
  geom_vline(xintercept = best_lo_bi, color = aidia_strategy_colors["coverage"],
             linewidth = 1.0) +
  geom_vline(xintercept = best_hi_bi, color = aidia_strategy_colors["coverage"],
             linewidth = 1.0) +
  # Width annotation
  annotate("segment", x = best_lo_bi, xend = best_hi_bi,
           y = 1.06, yend = 1.06,
           arrow = arrow(ends = "both", length = unit(0.05, "inches")),
           color = aidia_strategy_colors["coverage"], linewidth = 0.5) +
  annotate("text", x = (best_lo_bi + best_hi_bi) / 2, y = 1.12,
           label = sprintf("%.0f Da (%d%%)", best_w_bi, cov_pct),
           size = 3.0, fontface = "bold", color = aidia_strategy_colors["coverage"]) +
  # Valley annotation — must span it
  annotate("text", x = 670, y = 0.55,
           label = "Must span valley\nto reach 90%",
           size = 2.8, color = aidia_strategy_colors["coverage"], fontface = "italic") +
  annotate("segment", x = 610, xend = 730,
           y = 0.48, yend = 0.48,
           arrow = arrow(ends = "both", length = unit(0.05, "inches")),
           color = aidia_strategy_colors["coverage"], linewidth = 0.4) +
  # Precursor dots (colored by coverage selection)
  geom_point(data = transform(bi_points,
               inside = mz >= best_lo_bi & mz <= best_hi_bi),
             aes(x = mz, y = y, color = inside),
             size = 1.0, alpha = 0.5, show.legend = FALSE) +
  scale_color_manual(values = c("TRUE" = aidia_strategy_colors["coverage"],
                                "FALSE" = col_excluded)) +
  scale_x_continuous(limits = c(380, 980), expand = c(0.02, 0)) +
  scale_y_continuous(limits = c(-0.12, 1.20), expand = c(0, 0)) +
  labs(
    title = "Coverage: Spans both peaks",
    subtitle = "Needs 90% of precursors -> must include the sparse valley",
    x = "m/z (Da)", y = "Relative density"
  ) +
  theme_schematic() +
  theme(
    plot.title = element_text(color = aidia_strategy_colors["coverage"], size = 13),
    plot.subtitle = element_text(size = 9.5),
    axis.text.y = element_text(size = 8),
    axis.ticks.y = element_line()
  )

# --- Combined 2-panel comparison ---
p_kde_vs_cov <- gridExtra::arrangeGrob(
  p_kde_bi, p_cov_bi,
  ncol = 2,
  top = grid::textGrob(
    "KDE vs Coverage on Bimodal Distribution",
    gp = grid::gpar(fontsize = 15, fontface = "bold")
  ),
  bottom = grid::textGrob(
    "Same data, different strategies -> different boundaries. KDE is density-aware; Coverage is count-aware.",
    gp = grid::gpar(fontsize = 9.5, col = "gray45", fontface = "italic")
  )
)

ggsave(file.path(output_dir, "schematic_kde_vs_coverage.png"), p_kde_vs_cov,
       width = 14, height = 6, dpi = 150, bg = "white")
cat("  Saved: schematic_kde_vs_coverage.png\n")


# =====================================================================
# 4. Combined strategy concept overview (5 panels)
# =====================================================================
cat("\n--- Generating combined strategy overview ---\n")

# Compact versions of each plot (smaller text, no subtitle)
make_compact <- function(p, scolor) {
  p +
    labs(subtitle = NULL) +
    theme(
      plot.title = element_text(size = 11, face = "bold", color = scolor),
      axis.text = element_text(size = 7),
      plot.margin = margin(5, 8, 5, 8)
    )
}

panels <- list(
  make_compact(p_greedy, aidia_strategy_colors["greedy"]),
  make_compact(p_kde, aidia_strategy_colors["kde"]),
  make_compact(p_quantile, aidia_strategy_colors["quantile"]),
  make_compact(p_coverage, aidia_strategy_colors["coverage"]),
  make_compact(p_outlier, aidia_strategy_colors["outlier"])
)

# Legend grob
legend_grob <- grid::textGrob(
  paste0(
    "Green/Colored = included precursors\n",
    "Gray = excluded precursors\n",
    "X marks = outliers\n",
    "Dashed = candidate / comparison"
  ),
  gp = grid::gpar(fontsize = 8.5, col = "gray50", lineheight = 1.4)
)

p_all <- gridExtra::arrangeGrob(
  grobs = c(panels, list(legend_grob)),
  ncol = 3, nrow = 2,
  top = grid::textGrob(
    "m/z Boundary Strategy Comparison",
    gp = grid::gpar(fontsize = 15, fontface = "bold")
  )
)

ggsave(file.path(output_dir, "schematic_strategies_overview.png"), p_all,
       width = 15, height = 10, dpi = 150, bg = "white")
cat("  Saved: schematic_strategies_overview.png\n")


# =====================================================================
# Summary
# =====================================================================
cat("\n--- All generated files ---\n")
for (f in sort(list.files(output_dir, pattern = "\\.png$"))) {
  fpath <- file.path(output_dir, f)
  cat(sprintf("  %s (%.0f KB)\n", f, file.size(fpath) / 1024))
}
cat("\nSchematic generation complete.\n")
