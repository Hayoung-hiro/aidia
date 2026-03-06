#' AIDIA Visualization Design System
#'
#' Provides a unified theme, color palettes, and formatting utilities
#' for all AIDIA plots. Ensures consistency across the 4-stage pipeline
#' and colorblind-safe strategy color mapping.
#'
#' @name aidia-design-system
NULL


# Strategy Color Palette (colorblind-safe) ---------------------------------

#' Strategy color palette for AIDIA
#'
#' Named vector of 5 colors for m/z optimization strategies.
#' Based on ColorBrewer/Viridis principles for accessibility.
#'
#' @export
aidia_strategy_colors <- c(
  greedy   = "#3498DB",  # Blue (GLOBAL)
  kde      = "#9B59B6",  # Purple (GLOBAL)
  quantile = "#1ABC9C",  # Teal (LOCAL)
  coverage = "#E74C3C",  # Red (LOCAL)
  outlier  = "#F39C12"   # Orange (LOCAL)
)

# General Color Constants ---------------------------------------------------

#' General purpose color palette for AIDIA plots
#'
#' Used for non-strategy elements (text, backgrounds, annotations)
#'
#' @export
aidia_colors <- list(
  primary   = "#2C3E50",  # Dark blue-gray (titles, text)
  secondary = "#7F8C8D",  # Gray (subtitles, annotations)
  accent    = "#E74C3C",  # Red (highlights, targets)
  success   = "#27AE60",  # Green (satisfied region)
  warning   = "#F39C12",  # Orange (caution)
  grid      = "#ECF0F1",  # Light gray (grid lines)
  bg        = "#FFFFFF",  # White background
  # Before/After comparison pair
  before      = "steelblue",   # Current/input state (fill)
  before_dark = "steelblue4",  # Current state (outline, text)
  after       = "coral",       # Optimized/required state (fill)
  after_dark  = "coral4",      # Optimized state (outline, text)
  # Before/After gray variant (density overlays)
  before_muted      = "#BDC3C7",  # Light gray fill
  before_muted_dark = "#95A5A6",  # Darker gray outline
  after_success     = "#1E8449"   # Dark green outline (after condition)
)

#' Charge-state color palette for AIDIA
#'
#' 5-color vector for charge state visualizations.
#' Based on the AIDIA palette for visual consistency.
#'
#' @export
aidia_charge_colors <- c(
  "#3498DB", "#27AE60", "#F39C12", "#E74C3C", "#9B59B6"
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
      # Text elements
      plot.title = element_text(
        face = "bold",
        size = base_size + 2,
        color = aidia_colors$primary,
        margin = margin(b = 8)
      ),
      plot.subtitle = element_text(
        size = base_size - 1,
        color = aidia_colors$secondary,
        margin = margin(b = 10)
      ),
      plot.caption = element_text(
        size = base_size - 3,
        color = aidia_colors$secondary,
        hjust = 1,  # Right-aligned
        margin = margin(t = 10)
      ),

      # Axis elements
      axis.title = element_text(
        size = base_size - 1,
        color = aidia_colors$primary,
        face = "bold"
      ),
      axis.text = element_text(
        size = base_size - 2,
        color = aidia_colors$primary
      ),

      # Legend elements
      legend.title = element_text(
        face = "bold",
        size = base_size - 2,
        color = aidia_colors$primary
      ),
      legend.text = element_text(
        size = base_size - 3,
        color = aidia_colors$primary
      ),
      legend.position = "right",

      # Panel elements
      panel.grid.major = element_line(
        color = aidia_colors$grid,
        linewidth = 0.3
      ),
      panel.grid.minor = element_blank(),
      panel.background = element_rect(fill = "transparent", color = NA),
      plot.background = element_rect(fill = "transparent", color = NA),

      # Facet elements (better spacing for multi-panel plots)
      strip.text = element_text(
        face = "bold",
        size = base_size - 1,
        color = aidia_colors$primary,
        margin = margin(b = 5, t = 5)
      ),
      strip.background = element_rect(
        fill = aidia_colors$grid,
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
#' @export
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
#' @export
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

