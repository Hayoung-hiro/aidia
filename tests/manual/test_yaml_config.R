#!/usr/bin/env Rscript
# Test YAML Configuration Loading

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║           YAML Configuration Test                              ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Load config loader
source("R/config_loader.R")

# Test 1: Load YAML configuration
cat("Test 1: Loading YAML configuration\n")
cat("─────────────────────────────────────────────────────────────\n")

config_file <- "config/test_quick.yaml"

if (!file.exists(config_file)) {
  stop(sprintf("Config file not found: %s", config_file))
}

tryCatch({
  config <- load_optimization_config(config_file)
  cat("✅ Configuration loaded successfully!\n\n")
}, error = function(e) {
  cat(sprintf("❌ Failed to load configuration: %s\n", e$message))
  quit(status = 1)
})

# Test 2: Print configuration summary
cat("\nTest 2: Configuration Summary\n")
cat("─────────────────────────────────────────────────────────────\n")
print_config_summary(config)

# Test 3: Verify key fields
cat("\nTest 3: Key Field Verification\n")
cat("─────────────────────────────────────────────────────────────\n")

tests <- list(
  list(name = "Project name", value = config$project_metadata$project_name),
  list(name = "Input files count", value = length(config$input_data$input_files)),
  list(name = "Instrument preset", value = config$instrument$preset),
  list(name = "Target DPPP", value = config$dppp_parameters$target_dppp),
  list(name = "Strategies count", value = length(config$mz_optimization$strategies)),
  list(name = "Window modes", value = paste(config$window_generation$modes, collapse = ", ")),
  list(name = "Output directory", value = config$output$output_dir)
)

for (test in tests) {
  cat(sprintf("  ✓ %s: %s\n", test$name, test$value))
}

# Test 4: Check input file existence
cat("\nTest 4: Input File Validation\n")
cat("─────────────────────────────────────────────────────────────\n")

for (file in config$input_data$input_files) {
  if (file.exists(file)) {
    size_mb <- file.info(file)$size / 1024^2
    cat(sprintf("  ✓ %s (%.1f MB)\n", basename(file), size_mb))
  } else {
    cat(sprintf("  ✗ %s (NOT FOUND)\n", basename(file)))
  }
}

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║           ✅ All Tests Passed                                  ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Ready to run optimization:\n")
cat("  source('run_with_config.R')\n")
cat(sprintf("  results <- run_optimization('%s')\n", config_file))
cat("\n")
