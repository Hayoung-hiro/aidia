# validation_helpers.R - Input Validation Utilities
#
# Purpose: Reusable input validation functions for type checking,
# range validation, and integer constraints. Used across all pipeline stages.


#' Validate Input Object Type
#'
#' Checks if an object inherits from expected class(es) and provides
#' informative error messages.
#'
#' @param obj Object to validate
#' @param expected_class Character vector, expected class name(s)
#' @param param_name Character, parameter name for error message
#'
#' @return NULL (invisible), throws error if validation fails
#' @keywords internal
validate_input_type <- function(obj, expected_class, param_name = "input") {
  if (!any(sapply(expected_class, function(cls) inherits(obj, cls)))) {
    stop(sprintf(
      "%s must be of type %s, but got: %s",
      param_name,
      paste(expected_class, collapse = " or "),
      paste(class(obj), collapse = ", ")
    ))
  }
  invisible(NULL)
}

#' Validate Numeric Range
#'
#' Checks if a numeric value is within specified range.
#'
#' @param value Numeric, value to check
#' @param min Numeric, minimum allowed value (inclusive, NULL = no min)
#' @param max Numeric, maximum allowed value (inclusive, NULL = no max)
#' @param param_name Character, parameter name for error message
#'
#' @return NULL (invisible), throws error if validation fails
#' @keywords internal
validate_numeric_range <- function(value, min = NULL, max = NULL,
                                   param_name = "value") {
  if (!is.numeric(value) || length(value) != 1) {
    stop(sprintf("%s must be a single numeric value", param_name))
  }

  if (!is.null(min) && value < min) {
    stop(sprintf("%s must be >= %.2f, got: %.2f", param_name, min, value))
  }

  if (!is.null(max) && value > max) {
    stop(sprintf("%s must be <= %.2f, got: %.2f", param_name, max, value))
  }

  invisible(NULL)
}

#' Validate Positive Integer
#'
#' Checks if a value is a positive integer.
#'
#' @param value Numeric, value to check
#' @param param_name Character, parameter name for error message
#' @param allow_zero Logical, allow zero (default: FALSE)
#'
#' @return NULL (invisible), throws error if validation fails
#' @keywords internal
validate_positive_integer <- function(value, param_name = "value",
                                      allow_zero = FALSE) {
  if (!is.numeric(value) || length(value) != 1) {
    stop(sprintf("%s must be a single numeric value", param_name))
  }

  if (value != floor(value)) {
    stop(sprintf("%s must be an integer, got: %.2f", param_name, value))
  }

  min_val <- if (allow_zero) 0 else 1
  if (value < min_val) {
    stop(sprintf("%s must be >= %d, got: %d", param_name, min_val, value))
  }

  invisible(NULL)
}
