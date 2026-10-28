# Canonical mode keys. Legacy values are accepted at input and display boundaries;
# completed optimization settings always store the canonical keys.
.normalize_window_mode <- function(mode) {
  mode <- as.character(mode)
  mode[mode == "fixed"] <- "equal"
  mode
}

.normalize_rt_mode <- function(mode) {
  mode <- as.character(mode)
  mode[mode %in% c("fixed", "custom")] <- "uniform"
  mode
}

#' Format Window Generation Mode Labels
#' @param mode Character vector of current or legacy window mode keys.
#' @return Character vector of display labels.
#' @export
format_window_mode <- function(mode) {
  mode <- .normalize_window_mode(mode)
  labels <- c(equal = "Equal", density = "Density", staggered = "Staggered")
  known <- mode %in% names(labels)
  mode[known] <- labels[mode[known]]
  mode
}

#' Format RT Segmentation Mode Labels
#' @param mode Character vector of current or legacy RT mode keys.
#' @return Character vector of display labels.
#' @export
format_rt_mode <- function(mode) {
  mode <- .normalize_rt_mode(mode)
  labels <- c(uniform = "Uniform", adaptive = "Adaptive")
  known <- mode %in% names(labels)
  mode[known] <- labels[mode[known]]
  mode
}
