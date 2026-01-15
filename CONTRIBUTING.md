# Contributing to DIAoptimizer

 

This document provides guidelines for contributing to the DIAoptimizer project.

 

## Table of Contents

 

1. [Code Style](#code-style)

2. [Naming Conventions](#naming-conventions)

3. [Function Design](#function-design)

4. [Error Handling](#error-handling)

5. [Documentation](#documentation)

6. [Testing](#testing)

7. [Git Workflow](#git-workflow)

 

---

 

## Code Style

 

### General Principles

 

- Use **tidyverse conventions** (dplyr, ggplot2, tidyr)

- Prefer **functional programming** style over imperative

- Keep functions **focused and single-purpose**

- Maximum function length: **300 lines** (ideally < 100 lines)

- Use **2 spaces** for indentation (R standard)

 

### Code Formatting

 

```r

# Good: Clear spacing and structure

result <- data %>%

  filter(value > threshold) %>%

  group_by(category) %>%

  summarise(

    mean_val = mean(value),

    sd_val = sd(value),

    .groups = "drop"

  )

 

# Bad: Cramped and hard to read

result<-data%>%filter(value>threshold)%>%group_by(category)%>%summarise(mean_val=mean(value),sd_val=sd(value),.groups="drop")

```

 

### String Handling

 

```r

# Good: Use paste0() or paste() for concatenation

message <- paste0(

  "Error: File not found.\n",

  "Path: ", file_path, "\n",

  "Please check the file exists."

)

 

# Good: Use sprintf() for formatted strings

message <- sprintf("Processed %d items in %.2f seconds", n_items, elapsed_time)

 

# Bad: R doesn't support + for string concatenation!

message <- "Error: " + "File not found"  # This will FAIL!

```

 

---

 

## Naming Conventions

 

### Functions

 

Use **verb prefixes** to indicate the function's purpose:

 

| Prefix | Purpose | Example |

|--------|---------|---------|

| `load_*` | Data loading from files | `load_diann_data()` |

| `validate_*` | Data validation | `validate_data()` |

| `calculate_*` | Mathematical computations | `calculate_dppp()` |

| `analyze_*` | Analysis functions | `analyze_coverage()` |

| `diagnose_*` | Diagnostic functions | `diagnose_dppp_status()` |

| `segment_*` | RT segmentation | `segment_rt_by_time()` |

| `optimize_*` | Optimization algorithms | `optimize_windows()` |

| `generate_*` | Window/plot generation | `generate_visualizations()` |

| `compare_*` | Comparison functions | `compare_strategies()` |

| `export_*` | File export | `export_method_file()` |

| `plot_*` | Visualization functions | `plot_dppp_comparison()` |

| `create_*` | Object creation | `create_validated_dataset()` |

| `get_*` | Getter functions | `get_instrument_config()` |

| `is_*` / `has_*` | Boolean checks | `is_feasible()`, `has_metadata()` |

 

```r

# Good: Clear, descriptive names with appropriate prefix

validate_precursor_data <- function(data) { ... }

calculate_satisfaction_ratio <- function(dppp_values, target) { ... }

export_method_file_csv <- function(windows, output_path) { ... }

 

# Bad: Vague or inconsistent naming

process_data <- function(data) { ... }       # Too vague

do_calculation <- function(x, y) { ... }     # Unclear purpose

checkData <- function(data) { ... }          # Wrong case style

```

 

### Variables

 

Use **snake_case** for all variable names:

 

```r

# Good: Descriptive snake_case names

n_precursors <- nrow(data)

rt_bin_width_min <- 5

target_dppp <- 7.0

current_satisfaction_ratio <- 0.85

 

# Bad: Inconsistent naming styles

nPrecursors <- nrow(data)        # camelCase

rt.bin.width <- 5                # dots (reserved for S3)

N <- nrow(data)                  # Too short, unclear

```

 

### Standard Variable Names

 

Use these **consistent names** throughout the codebase:

 

| Concept | Standard Name | Avoid |

|---------|---------------|-------|

| Number of bins | `n_bins` | `num_bins`, `n_rt_bins`, `nbins` |

| Number of windows | `n_windows` | `num_windows`, `window_count` |

| RT segment ID | `rt_segment_id` | `segment_id`, `bin_id` |

| Window ID | `window_id` | `win_id`, `id` |

| m/z range | `mz_min`, `mz_max` | `mz_start`, `mz_stop` |

| RT range | `rt_start`, `rt_end` | `rt_min`, `rt_max` (use for overall range) |

| Precursor count | `n_precursors` | `precursor_count`, `num_prec` |

 

### Constants

 

Use **UPPER_SNAKE_CASE** for constants:

 

```r

# Good

DPPP_FACTOR <- 1.7

DEFAULT_TARGET_DPPP <- 7.0

MAX_WINDOWS_PER_BIN <- 100

 

# Bad

dppp_factor <- 1.7    # Looks like a variable

DpppFactor <- 1.7     # Wrong case style

```

 

---

 

## Function Design

 

### Function Signature

 

```r

#' Brief description of function purpose

#'

#' Longer description if needed, explaining the algorithm,

#' use cases, or important caveats.

#'

#' @param data Data frame with required columns (RT.Start, Precursor.Mz, FWHM)

#' @param target_dppp Numeric, target DPPP value (default: 7.0)

#' @param verbose Logical, print progress messages (default: TRUE)

#'

#' @return List with components:

#'   - `result`: The main result

#'   - `statistics`: Summary statistics

#'   - `metadata`: Processing metadata

#'

#' @examples

#' result <- calculate_dppp(data, target_dppp = 7.0)

#'

#' @export

calculate_dppp <- function(

  data,

  target_dppp = 7.0,

  verbose = TRUE

) {

  # Function body

}

```

 

### Parameter Order

 

1. **Required parameters** first (no defaults)

2. **Optional parameters** with sensible defaults

3. **Control parameters** last (verbose, debug, etc.)

 

```r

# Good: Clear parameter ordering

optimize_windows <- function(

  validated_data,           # Required

  optimization_plan,        # Required

  rt_bin_width_min = 5,     # Optional with default

  mz_strategy = "quantile", # Optional with default

  verbose = TRUE            # Control parameter

) { ... }

```

 

### Return Values

 

Use **consistent return structures**:

 

```r

# Good: Structured return with clear components

return(structure(

  list(

    windows = window_data,

    statistics = list(

      total_windows = nrow(window_data),

      mean_width = mean(window_data$width),

      coverage_pct = coverage * 100

    ),

    parameters = list(

      strategy = mz_strategy,

      bin_width = rt_bin_width_min

    ),

    metadata = list(

      timestamp = Sys.time(),

      version = "2.0"

    )

  ),

  class = c("OptimizedWindows", "list")

))

```

 

---

 

## Error Handling

 

### Error Patterns

 

Use **early validation** with clear error messages:

 

```r

# Good: Early validation with informative message

validate_input <- function(data, threshold) {

  # Check required columns

 

  required_cols <- c("RT.Start", "Precursor.Mz", "FWHM")

  missing_cols <- setdiff(required_cols, names(data))

 

  if (length(missing_cols) > 0) {

    stop(paste0(

      "Required columns missing from data:\n",

      "  Missing: ", paste(missing_cols, collapse = ", "), "\n",

      "  Available: ", paste(names(data), collapse = ", ")

    ))

  }

 

  # Check threshold range

 

  if (!is.numeric(threshold) || threshold < 0 || threshold > 1) {

    stop(sprintf(

      "threshold must be a numeric value between 0 and 1.\n  Received: %s (class: %s)",

      as.character(threshold),

      class(threshold)

    ))

  }

}

```

 

### Warning Patterns

 

Use warnings for **non-fatal issues**:

 

```r

# Good: Warning for suboptimal but recoverable situation

if (n_precursors < 100) {

  warning(sprintf(

    "Low precursor count (%d) may result in unreliable optimization.\n%s",

    n_precursors,

    "Consider using more data or adjusting parameters."

  ))

}

```

 

### Message Patterns

 

Use messages for **progress updates**:

 

```r

# Good: Clear progress messages

if (verbose) {

  cat(sprintf("Step 1/3: Loading data from %s...\n", basename(file_path)))

  cat(sprintf("  Loaded %s precursors\n", format(n_precursors, big.mark = ",")))

}

```

 

### Avoid Silent Failures

 

```r

# Bad: Silent failure

if (is.null(data)) {

  return(NULL)  # Caller has no idea what went wrong

}

 

# Good: Explicit error

if (is.null(data)) {

  stop("Input data is NULL. Please provide a valid data frame.")

}

```

 

---

 

## Documentation

 

### roxygen2 Format

 

All exported functions must have roxygen2 documentation:

 

```r

#' Calculate DPPP (Data Points Per Peak) Distribution

#'

#' Calculates DPPP values for all precursors based on their FWHM and

#' the specified cycle time. Uses the Spectronaut standard formula:

#' DPPP = (FWHM_seconds * 1.7) / cycle_time_seconds

#'

#' @param fwhm_minutes Numeric vector, FWHM values in minutes

#' @param cycle_time_sec Numeric, cycle time in seconds

#'

#' @return Numeric vector of DPPP values

#'

#' @details

#' The factor 1.7 comes from the assumption that chromatographic peak

#' width equals 1.7 × FWHM (Gaussian peak approximation).

#'

#' @examples

#' fwhm <- c(0.3, 0.4, 0.5)  # minutes

#' dppp <- calculate_dppp_values(fwhm, cycle_time_sec = 2.0)

#'

#' @seealso [diagnose_dppp_status()] for complete DPPP analysis

#'

#' @export

calculate_dppp_values <- function(fwhm_minutes, cycle_time_sec) {

  fwhm_seconds <- fwhm_minutes * 60

  dppp <- (fwhm_seconds * 1.7) / cycle_time_sec

  return(dppp)

}

```

 

### Inline Comments

 

Use comments to explain **why**, not **what**:

 

```r

# Good: Explains the reasoning

# Use P5-P95 quantiles to exclude outliers while maintaining 90% coverage

mz_min <- quantile(mz_values, 0.05, na.rm = TRUE)

mz_max <- quantile(mz_values, 0.95, na.rm = TRUE)

 

# Bad: States the obvious

# Calculate the 5th percentile

mz_min <- quantile(mz_values, 0.05, na.rm = TRUE)

```

 

### Section Headers

 

Use consistent section headers in large files:

 

```r

# =============================================================================

# Section Name

# =============================================================================

 

#' Function documentation...

function_name <- function() { ... }

 

# -----------------------------------------------------------------------------

# Subsection Name

# -----------------------------------------------------------------------------

```

 

---

 

## Testing

 

### Test File Location

 

```

tests/

├── testthat/

│   ├── test-stage1.R

│   ├── test-stage2.R

│   ├── test-stage3.R

│   └── test-stage4.R

├── manual/

│   └── test_pipeline.R

└── fixtures/

    └── sample_data.rds

```

 

### Test Naming

 

```r

# Good: Descriptive test names

test_that("calculate_dppp returns correct values for known inputs", {

  fwhm <- c(0.5)  # 30 seconds

  cycle_time <- 1.0  # 1 second

  expected_dppp <- (30 * 1.7) / 1.0  # = 51

 

  result <- calculate_dppp_values(fwhm, cycle_time)

  expect_equal(result, expected_dppp)

})

 

test_that("validate_data stops on missing FWHM column", {

  bad_data <- data.frame(RT.Start = 1:10, Precursor.Mz = 400:409)

  expect_error(validate_data(bad_data), "FWHM")

})

```

 

---

 

## Git Workflow

 

### Commit Messages

 

Use conventional commit format:

 

```

type(scope): brief description

 

Longer explanation if needed.

 

- Bullet points for multiple changes

- Keep lines under 72 characters

```

 

**Types:**

- `feat`: New feature

- `fix`: Bug fix

- `docs`: Documentation only

- `refactor`: Code change that neither fixes a bug nor adds a feature

- `test`: Adding or updating tests

- `chore`: Maintenance tasks

 

**Examples:**

```

fix(data_loader): use paste0() instead of + for string concatenation

 

R doesn't support + operator for strings. This caused runtime errors

when FWHM column was missing from input data.

 

refactor(stage4): remove internal source() calls

 

Dependencies should be loaded at initialization, not inside functions.

This improves performance and makes dependencies explicit.

 

docs: add CONTRIBUTING.md with coding standards

```

 

### Branch Naming

 

```

feature/add-smoothing-strategy

fix/string-concatenation-bug

refactor/split-large-functions

docs/update-readme

```

 

---

 

## Quick Reference Card

 

### Do's

 

- Use `paste0()` or `sprintf()` for strings

- Use `snake_case` for variables and functions

- Validate inputs early with clear error messages

- Document all exported functions with roxygen2

- Keep functions under 300 lines

- Use consistent naming (see tables above)

 

### Don'ts

 

- Don't use `+` for string concatenation

- Don't use `source()` inside functions

- Don't silently return NULL on errors

- Don't leave commented-out code in production

- Don't use camelCase or dots in variable names

- Don't create functions over 300 lines

 

---

 

## Questions?

 

If you have questions about these guidelines, please:

1. Check existing code for examples

2. Read the relevant documentation in `docs/`

3. Open an issue for discussion

 

Thank you for contributing to DIAoptimizer!