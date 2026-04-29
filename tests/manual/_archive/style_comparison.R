# Style Comparison: 3 publication theme variants
# Run: source("tests/manual/style_comparison.R")

library(ggplot2)
library(grid)
library(gridExtra)

# --- Demo data ---
set.seed(42)
demo <- data.frame(
  category = factor(
    c("Greedy", "KDE", "Quantile", "Coverage", "Outlier"),
    levels = c("Greedy", "KDE", "Quantile", "Coverage", "Outlier")
  ),
  coverage = c(58.0, 99.2, 90.0, 95.0, 99.8),
  width    = c(2.01, 5.69, 4.06, 4.50, 5.69)
)

# --- Palettes ---
pal_muted   <- c("#4878A8", "#7B68AE", "#2D9B83", "#C75B5B", "#D4923A")
pal_vibrant <- c("#3498DB", "#9B59B6", "#1ABC9C", "#E74C3C", "#F39C12")

# --- Bar chart builder ---
make_bar <- function(theme_fn, title, palette) {
  ggplot(demo, aes(x = category, y = coverage, fill = category)) +
    geom_col(width = 0.7, show.legend = FALSE) +
    geom_text(aes(label = sprintf("%.1f%%", coverage)),
              vjust = -0.5, size = 3.5, fontface = "bold") +
    scale_fill_manual(values = palette) +
    scale_y_continuous(
      limits = c(0, 115), breaks = seq(0, 100, 25),
      expand = expansion(mult = c(0, 0.02))
    ) +
    labs(
      title = title,
      subtitle = "Strategy coverage comparison (demo data)",
      x = NULL, y = "Coverage (%)",
      caption = "5,815 precursors | Astral | Density mode"
    ) +
    theme_fn()
}

# --- Style A: Current theme_aidia (minimal + soft grid) ---
theme_A <- function() {
  theme_minimal(base_size = 12) +
    theme(
      plot.title    = element_text(face = "bold", size = 14, color = "#2C3E50"),
      plot.subtitle = element_text(size = 11, color = "#7F8C8D"),
      plot.caption  = element_text(size = 9, color = "#7F8C8D", hjust = 1),
      axis.title    = element_text(face = "bold", size = 11, color = "#2C3E50"),
      axis.text     = element_text(size = 10, color = "#2C3E50"),
      panel.grid.major   = element_line(color = "#ECF0F1", linewidth = 0.3),
      panel.grid.minor   = element_blank(),
      panel.grid.major.x = element_blank(),
      plot.background    = element_rect(fill = "white", color = NA)
    )
}

# --- Style B: Classic Academic (axis lines, no grid, like J. Proteome Res.) ---
theme_B <- function() {
  theme_classic(base_size = 12) +
    theme(
      plot.title    = element_text(face = "bold", size = 14, color = "gray10",
                                   margin = margin(b = 6)),
      plot.subtitle = element_text(size = 10.5, color = "gray40",
                                   margin = margin(b = 10)),
      plot.caption  = element_text(size = 9, color = "gray50", hjust = 1),
      axis.title    = element_text(face = "bold", size = 11),
      axis.text     = element_text(size = 10, color = "gray20"),
      axis.line     = element_line(color = "gray30", linewidth = 0.4),
      axis.ticks    = element_line(color = "gray30", linewidth = 0.3),
      plot.background = element_rect(fill = "white", color = NA)
    )
}

# --- Style C: Nature/Science (high contrast, minimal, bold axes) ---
theme_C <- function() {
  theme_minimal(base_size = 12) +
    theme(
      plot.title    = element_text(face = "bold", size = 13, color = "black",
                                   margin = margin(b = 4)),
      plot.subtitle = element_text(size = 10, color = "gray30",
                                   margin = margin(b = 8)),
      plot.caption  = element_text(size = 8.5, color = "gray45", hjust = 1),
      axis.title    = element_text(face = "bold", size = 11, color = "black"),
      axis.text     = element_text(size = 10, color = "black"),
      axis.line     = element_line(color = "black", linewidth = 0.5),
      axis.ticks    = element_line(color = "black", linewidth = 0.3),
      panel.grid    = element_blank(),
      panel.border  = element_blank(),
      plot.background = element_rect(fill = "white", color = NA)
    )
}

# --- Generate ---
p_A <- make_bar(theme_A, "Style A: Current (Minimal + Soft Grid)", pal_vibrant)
p_B <- make_bar(theme_B, "Style B: Classic Academic (Axis Lines, No Grid)", pal_muted)
p_C <- make_bar(theme_C, "Style C: Nature/Science (High Contrast, Bold)", pal_muted)

outdir <- "output_report_test"
if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

# Save individually for easy comparison
ggsave(file.path(outdir, "style_A_current.png"), p_A,
       width = 8, height = 5, dpi = 200, bg = "white")
ggsave(file.path(outdir, "style_B_classic.png"), p_B,
       width = 8, height = 5, dpi = 200, bg = "white")
ggsave(file.path(outdir, "style_C_nature.png"), p_C,
       width = 8, height = 5, dpi = 200, bg = "white")

cat("OK saved 3 style comparisons to", outdir, "\n")
