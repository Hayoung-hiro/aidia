#' AIDIA Visualization Design System
#'
#' Provides a unified theme, color palettes, and formatting utilities
#' for all AIDIA plots. Ensures consistency across the 4-stage pipeline
#' and colorblind-safe strategy color mapping.
#'
#' @name aidia-design-system
NULL


# Strategy Order & Color Palette -------------------------------------------

#' Canonical strategy display order
#'
#' Preferred ordering of strategies for facets, legends, and comparisons.
#' GLOBAL strategies first (greedy, kde), then LOCAL (quantile, coverage, outlier).
#'
#' @keywords internal
STRATEGY_PREFERRED_ORDER <- c("greedy", "kde", "quantile", "coverage", "outlier")

# Strategy Color Palette (colorblind-safe) ---------------------------------

#' Strategy color palette for AIDIA
#'
#' Named vector of 5 colors for m/z optimization strategies.
#' Muted, publication-ready palette (colorblind-safe).
#'
#' @keywords internal
aidia_strategy_colors <- c(
  greedy   = "#4878A8",  # Steel blue (GLOBAL)
  kde      = "#7B68AE",  # Muted purple (GLOBAL)
  quantile = "#2D9B83",  # Sage teal (LOCAL)
  coverage = "#C75B5B",  # Dusty red (LOCAL)
  outlier  = "#D4923A"   # Amber (LOCAL)
)

# General Color Constants ---------------------------------------------------

#' General purpose color palette for AIDIA plots
#'
#' Used for non-strategy elements (text, backgrounds, annotations).
#' High-contrast, publication-ready palette.
#'
#' @keywords internal
aidia_colors <- list(
  primary   = "gray10",   # Near-black (titles, primary text)
  secondary = "gray40",   # Dark gray (subtitles, annotations)
  accent    = "#C75B5B",  # Dusty red (highlights, targets)
  success   = "#2D9B83",  # Sage teal (satisfied, met)
  warning   = "#D4923A",  # Amber (caution)
  grid      = "gray90",   # Light gray (table stripes)
  bg        = "#FFFFFF",  # White background
  # Before/After comparison pair
  before      = "#4878A8",  # Steel blue (current state fill)
  before_dark = "#2C5F8A",  # Dark steel (outline, text)
  after       = "#C75B5B",  # Dusty red (optimized state fill)
  after_dark  = "#8B3A3A",  # Dark red (outline, text)
  # Before/After gray variant (density overlays)
  before_muted      = "#B0BEC5",  # Cool gray fill
  before_muted_dark = "#78909C",  # Darker gray outline
  after_success     = "#1E7A64"   # Dark teal (after condition)
)

#' Charge-state color palette for AIDIA
#'
#' 5-color vector for charge state visualizations.
#' Based on the AIDIA palette for visual consistency.
#'
#' @keywords internal
aidia_charge_colors <- c(
  "#4878A8", "#2D9B83", "#D4923A", "#C75B5B", "#7B68AE"
)

# Theme Function ------------------------------------------------------------

#' AIDIA ggplot2 theme
#'
#' Consistent theme for all AIDIA plots. Based on theme_minimal() with
#' enhanced typography, spacing, and accessibility.
#'
#' @param base_size Base font size in points (default: 12)
#' @param base_family Font family (default: "")
#'
#' @return A ggplot2 theme object
#' @export
#'
#' @examples
#' \dontrun{
#' ggplot(data) + geom_point() + theme_aidia()
#' }
theme_aidia <- function(base_size = 12, base_family = "") {
  theme_minimal(base_size = base_size, base_family = base_family) +
    theme(
      # Text elements — high-contrast, publication-ready
      plot.title = element_text(
        face = "bold",
        size = base_size + 1,
        color = "black",
        margin = margin(b = 4)
      ),
      plot.subtitle = element_text(
        size = base_size - 1.5,
        color = "gray30",
        margin = margin(b = 8)
      ),
      plot.caption = element_text(
        size = base_size - 3,
        color = "gray45",
        hjust = 1,
        margin = margin(t = 8)
      ),

      # Axis elements — bold axis lines, visible ticks
      axis.title = element_text(
        size = base_size - 1,
        color = "black",
        face = "bold"
      ),
      axis.text = element_text(
        size = base_size - 2,
        color = "black"
      ),
      axis.line = element_line(
        color = "black",
        linewidth = 0.4
      ),
      axis.ticks = element_line(
        color = "black",
        linewidth = 0.3
      ),

      # Legend elements
      legend.title = element_text(
        face = "bold",
        size = base_size - 2,
        color = "black"
      ),
      legend.text = element_text(
        size = base_size - 3,
        color = "gray20"
      ),
      legend.position = "right",

      # Panel elements — no grid lines (clean publication style)
      panel.grid = element_blank(),
      panel.background = element_rect(fill = "white", color = NA),
      plot.background = element_rect(fill = "white", color = NA),

      # Facet elements
      strip.text = element_text(
        face = "bold",
        size = base_size - 1,
        color = "black",
        margin = margin(b = 5, t = 5)
      ),
      strip.background = element_rect(
        fill = "gray95",
        color = NA
      ),
      panel.spacing = unit(1, "lines")
    )
}

# Strategy Label Formatting -------------------------------------------------

#' Format strategy names to human-readable labels
#'
#' Converts internal strategy names to display-friendly labels with
#' algorithm descriptions. Used for plot legends and facet labels.
#'
#' @param strategy_name Character vector of strategy names
#'
#' @return Character vector of formatted labels
#' @export
#'
#' @examples
#' format_strategy_label("greedy")  # "Greedy (MacCoss)"
#' format_strategy_label(c("kde", "quantile"))
format_strategy_label <- function(strategy_name) {
  label_map <- c(
    greedy   = "Greedy (MacCoss)",
    kde      = "KDE (Density Peak)",
    quantile = "Quantile (P5-P95)",
    coverage = "Coverage (95%)",
    outlier  = "Outlier (+/-3 SD)"
  )

  # Return mapped label if exists, otherwise title-case the input
  vapply(strategy_name, function(s) {
    if (s %in% names(label_map)) {
      label_map[[s]]
    } else {
      # Fallback: capitalize first letter
      paste0(toupper(substr(s, 1, 1)), substr(s, 2, nchar(s)))
    }
  }, character(1), USE.NAMES = FALSE)
}

# ggplot2 Scale Functions ---------------------------------------------------

#' Color scale for strategy-based plots
#'
#' Maps strategy names to the AIDIA colorblind-safe palette.
#' Use with aes(color = strategy).
#'
#' @param ... Additional arguments passed to scale_color_manual()
#'
#' @return A ggplot2 scale object
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' ggplot(data, aes(x, y, color = strategy)) +
#'   geom_point() +
#'   scale_color_strategy()
#' }
scale_color_strategy <- function(...) {
  scale_color_manual(
    values = aidia_strategy_colors,
    labels = format_strategy_label,
    name = "Strategy",
    ...
  )
}

#' Fill scale for strategy-based plots
#'
#' Maps strategy names to the AIDIA colorblind-safe palette.
#' Use with aes(fill = strategy).
#'
#' @param ... Additional arguments passed to scale_fill_manual()
#'
#' @return A ggplot2 scale object
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' ggplot(data, aes(x, y, fill = strategy)) +
#'   geom_col() +
#'   scale_fill_strategy()
#' }
scale_fill_strategy <- function(...) {
  scale_fill_manual(
    values = aidia_strategy_colors,
    labels = format_strategy_label,
    name = "Strategy",
    ...
  )
}

