# =============================================================================
# Shiny App Setup Script
# =============================================================================
# Run this script ONCE to set up the Shiny development environment
# =============================================================================

cat("
╔══════════════════════════════════════════════════════════════╗
║  AIDIA - Adaptive Isolation for DIA (Shiny App Setup)       ║
╚══════════════════════════════════════════════════════════════╝
")

# --- Step 1: Check and Install Required Packages ---
cat("\n[1/4] Checking required packages...\n")

required_packages <- c(
  "shiny",           # Core framework
  "bs4Dash",         # Dashboard layout (AdminLTE3 / Bootstrap 4)
  "shinybusy",       # Progress spinners
  "shinyjs",         # Progressive disclosure (toggle/hide)
  "DT",              # Interactive tables
  "arrow"            # Parquet support
)

missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]

if (length(missing_packages) > 0) {
  cat("   Installing missing packages:", paste(missing_packages, collapse = ", "), "\n")
  install.packages(missing_packages, repos = "https://cloud.r-project.org")
} else {
  cat("   ✓ All required packages are installed\n")
}

# --- Step 2: Verify Pipeline Functions ---
cat("\n[2/4] Verifying pipeline functions...\n")

pipeline_files <- c(
  "../R/stage1_data_validation.R",
  "../R/stage2_optimization_planning.R",
  "../R/stage3_window_optimization.R",
  "../R/utils_common.R",
  "../R/instrument_utils.R"
)

all_exist <- TRUE
for (f in pipeline_files) {
  full_path <- normalizePath(file.path(getwd(), f), mustWork = FALSE)
  if (file.exists(full_path)) {
    cat("   ✓", basename(f), "\n")
  } else {
    cat("   ✗", basename(f), "- NOT FOUND\n")
    all_exist <- FALSE
  }
}

if (!all_exist) {
  cat("\n   ⚠ Some pipeline files are missing!")
  cat("\n   Make sure you're running this from the shiny_app/ directory\n")
}

# --- Step 3: Create www/ directory if needed ---
cat("\n[3/4] Setting up directory structure...\n")

if (!dir.exists("www")) {
  dir.create("www")
  cat("   ✓ Created www/ directory\n")
} else {
  cat("   ✓ www/ directory exists\n")
}

# Create placeholder CSS
css_file <- "www/custom.css"
if (!file.exists(css_file)) {
  writeLines("/* Custom CSS for AIDIA Shiny App */

/* Info boxes */
.info-box {
  min-height: 90px;
  border-radius: 4px;
}

/* Box headers */
.box-header.with-border {
  border-bottom: 1px solid #f4f4f4;
}

/* Primary button */
.btn-primary {
  background-color: #3c8dbc;
  border-color: #367fa9;
}

.btn-primary:hover {
  background-color: #367fa9;
}

/* Success button */
.btn-success {
  background-color: #00a65a;
  border-color: #008d4c;
}

/* Progress bar */
.progress-bar {
  background-color: #00a65a;
}
", css_file)
  cat("   ✓ Created custom.css\n")
}

# --- Step 4: Test Load ---
cat("\n[4/4] Testing package loading...\n")

tryCatch({
  suppressPackageStartupMessages({
    library(shiny)
    library(bs4Dash)
    library(shinybusy)
    library(shinyjs)
    library(DT)
    library(arrow)
  })
  cat("   ✓ All packages loaded successfully\n")
}, error = function(e) {
  cat("   ✗ Error loading packages:", e$message, "\n")
})

# --- Summary ---
cat("\n")
cat("══════════════════════════════════════════════════════════════\n")
cat("Setup complete!\n")
cat("══════════════════════════════════════════════════════════════\n")
cat("\nTo run the Shiny app:\n")
cat("\n  Option 1: From R console (in shiny_app/ directory)\n")
cat("    > shiny::runApp()\n")
cat("\n  Option 2: From project root\n")
cat("    > shiny::runApp('shiny_app')\n")
cat("\n  Option 3: From RStudio\n")
cat("    Click 'Run App' button in app.R\n")
cat("\n")
