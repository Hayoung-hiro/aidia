# install_packages.R - Install required packages for DIA Window Optimizer

cat("============================================================\n")
cat("Installing Required Packages for DIA Window Optimizer\n")
cat("============================================================\n\n")

# List of required packages
required_packages <- c(
  "dplyr",
  "ggplot2",
  "viridis",
  "scales",
  "tidyr",
  "arrow",
  "gridExtra",
  "prospectr",
  "jsonlite"
)

# Check and install missing packages
cat("Checking for required packages...\n\n")

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("Installing %s...\n", pkg))
    install.packages(pkg, repos = "https://cloud.r-project.org/")
  } else {
    cat(sprintf("✓ %s already installed\n", pkg))
  }
}

cat("\n============================================================\n")
cat("Package installation complete!\n")
cat("============================================================\n")
