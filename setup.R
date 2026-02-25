# =============================================================================
# AIDIA - Environment Setup Script
# =============================================================================
# Run this script ONCE to install/update all required packages
#
# Usage:
#   source("setup.R")
#
# =============================================================================

cat("\n")
cat("======================================================================\n")
cat("  AIDIA - Adaptive Isolation for DIA (Environment Setup)\n")
cat("======================================================================\n\n")

# --- Step 1: Check R version ---
cat("[1/4] Checking R version...\n")

r_version <- getRversion()
if (r_version < "4.0.0") {
  stop(sprintf("  R >= 4.0.0 required (current: %s). Please update R.", r_version))
} else {
  cat(sprintf("  OK R %s\n", r_version))
}

# --- Step 2: Install/Update Core Packages (Imports) ---
cat("\n[2/4] Checking core packages (Imports)...\n")

core_packages <- list(
  dplyr      = "1.1.0",
  tibble     = "3.0.0",
  tidyr      = "1.3.0",
  arrow      = "10.0.0",
  ggplot2    = "3.5.1",
  jsonlite   = "1.8.0",
  scales     = "1.4.0",
  ggridges   = "0.5.0",
  viridis    = "0.6.0",
  gridExtra  = "2.3"
)

needs_install <- character(0)
needs_update  <- character(0)

for (pkg in names(core_packages)) {
  min_ver <- core_packages[[pkg]]
  installed <- tryCatch(
    as.character(packageVersion(pkg)),
    error = function(e) NULL
  )

  if (is.null(installed)) {
    cat(sprintf("  %-12s: NOT INSTALLED (need >= %s)\n", pkg, min_ver))
    needs_install <- c(needs_install, pkg)
  } else if (package_version(installed) < package_version(min_ver)) {
    cat(sprintf("  %-12s: %s -> need >= %s (UPDATE)\n", pkg, installed, min_ver))
    needs_update <- c(needs_update, pkg)
  } else {
    cat(sprintf("  %-12s: %s OK\n", pkg, installed))
  }
}

to_install <- c(needs_install, needs_update)

if (length(to_install) > 0) {
  cat(sprintf("\n  Installing/updating %d package(s): %s\n",
              length(to_install), paste(to_install, collapse = ", ")))
  install.packages(to_install, repos = "https://cloud.r-project.org")
  cat("  OK Core packages updated\n")
} else {
  cat("\n  OK All core packages are up to date\n")
}

# --- Step 3: Install Optional Packages (Suggests) ---
cat("\n[3/4] Checking optional packages (Suggests)...\n")

optional_packages <- list(
  # Shiny web app
  shiny     = "1.7.0",
  bs4Dash   = "2.0.0",
  shinyjs   = "2.0.0",
  shinybusy = "0.3.0",
  DT        = "0.28",
  # Processing
  prospectr  = "0.2.0",
  yaml       = "2.3.0",
  # Development
  testthat   = "3.0.0"
)

missing_optional <- character(0)

for (pkg in names(optional_packages)) {
  installed <- tryCatch(
    as.character(packageVersion(pkg)),
    error = function(e) NULL
  )

  if (is.null(installed)) {
    cat(sprintf("  %-14s: not installed (optional)\n", pkg))
    missing_optional <- c(missing_optional, pkg)
  } else {
    cat(sprintf("  %-14s: %s OK\n", pkg, installed))
  }
}

if (length(missing_optional) > 0) {
  cat(sprintf("\n  %d optional package(s) not installed: %s\n",
              length(missing_optional), paste(missing_optional, collapse = ", ")))
  cat("  Installing optional packages...\n")
  install.packages(missing_optional, repos = "https://cloud.r-project.org")
  cat("  OK Optional packages installed\n")
} else {
  cat("\n  OK All optional packages installed\n")
}

# --- Step 4: Verify Installation ---
cat("\n[4/4] Verifying installation...\n")

verify_ok <- TRUE

for (pkg in names(core_packages)) {
  ok <- tryCatch({
    requireNamespace(pkg, quietly = TRUE)
  }, error = function(e) FALSE)

  if (!ok) {
    cat(sprintf("  FAIL: %s could not be loaded\n", pkg))
    verify_ok <- FALSE
  }
}

if (verify_ok) {
  cat("  OK All core packages load successfully\n")
} else {
  cat("  WARNING: Some packages failed to load. Check errors above.\n")
}

# --- Summary ---
cat("\n")
cat("======================================================================\n")
if (verify_ok && length(to_install) == 0) {
  cat("  Setup complete! Environment is ready.\n")
} else if (verify_ok) {
  cat("  Setup complete! Packages were updated successfully.\n")
} else {
  cat("  Setup incomplete. Please resolve errors above.\n")
}
cat("======================================================================\n")
cat("\n")
cat("Quick start:\n")
cat("  # Pipeline mode:\n")
cat("  source(\"main.R\")\n")
cat("  results <- run_complete_pipeline(data_dir = \"data\")\n")
cat("\n")
cat("  # Shiny app mode:\n")
cat("  devtools::load_all(); run_aidia_app()\n")
cat("\n")

# Cleanup temp file if exists
if (file.exists("_check_versions.R")) file.remove("_check_versions.R")
