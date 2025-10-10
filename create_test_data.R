# create_test_data.R
# Generate synthetic DIA-NN data for testing redesigned modules

library(arrow)
library(dplyr)

set.seed(42)

cat("Generating synthetic DIA-NN test data...\n")

# Parameters for realistic proteome distribution
n_precursors <- 50000
rt_range <- c(10, 110)  # minutes
mz_range <- c(400, 1000)
mean_fwhm_sec <- 30

# Generate precursor data with realistic distribution
# Higher density in middle RT range (typical gradient elution pattern)
rt_values <- c(
  rnorm(n_precursors * 0.3, mean = 40, sd = 10),  # Early elution
  rnorm(n_precursors * 0.5, mean = 60, sd = 15),  # Main elution
  rnorm(n_precursors * 0.2, mean = 80, sd = 8)    # Late elution
)
rt_values <- pmin(pmax(rt_values, rt_range[1]), rt_range[2])

# m/z distribution (typical peptide mass distribution)
# Higher density in 600-800 range (typical for tryptic peptides)
mz_values <- c(
  rnorm(n_precursors * 0.2, mean = 500, sd = 50),
  rnorm(n_precursors * 0.6, mean = 700, sd = 80),
  rnorm(n_precursors * 0.2, mean = 850, sd = 60)
)
mz_values <- pmin(pmax(mz_values, mz_range[1]), mz_range[2])

# FWHM values (seconds, converted to minutes)
# Vary by RT (peaks get broader at higher RT due to diffusion)
fwhm_sec <- mean_fwhm_sec + (rt_values - mean(rt_values)) * 0.2 + rnorm(n_precursors, 0, 5)
fwhm_sec <- pmax(fwhm_sec, 15)  # Minimum 15 seconds
fwhm_min <- fwhm_sec / 60

# RT.Stop from FWHM (peak width ≈ 2.5 × FWHM)
rt_stop <- rt_values + (fwhm_min * 2.5)

# Create synthetic DIA-NN dataframe with all required columns
test_data <- data.frame(
  Protein.Group = paste0("PG", sample(1:5000, n_precursors, replace = TRUE)),
  Protein.Ids = paste0("P", sprintf("%05d", sample(1:5000, n_precursors, replace = TRUE))),
  Protein.Names = paste0("Protein_", sample(1:5000, n_precursors, replace = TRUE)),
  Genes = paste0("GENE", sample(1:5000, n_precursors, replace = TRUE)),
  Precursor.Id = paste0("PRECURSOR_", 1:n_precursors),
  Modified.Sequence = paste0("_[Acetyl]PEPTIDE", sample(1:n_precursors)),
  Stripped.Sequence = paste0("PEPTIDE", sample(1:n_precursors)),
  Precursor.Charge = sample(2:4, n_precursors, replace = TRUE, prob = c(0.4, 0.5, 0.1)),
  Precursor.Mz = mz_values,
  RT.Start = rt_values,
  RT.Stop = rt_stop,
  FWHM = fwhm_min,
  Q.Value = runif(n_precursors, 0, 0.01),  # All pass 1% FDR
  PG.Q.Value = runif(n_precursors, 0, 0.05),  # Protein group FDR
  Global.Q.Value = runif(n_precursors, 0, 0.01),
  Precursor.Quantity = 10^rnorm(n_precursors, 6, 1.5),
  stringsAsFactors = FALSE
)

# Sort by RT for realism
test_data <- test_data %>% arrange(RT.Start)

cat(sprintf("Generated %d precursors\n", nrow(test_data)))
cat(sprintf("  m/z range: %.1f - %.1f\n", min(test_data$Precursor.Mz), max(test_data$Precursor.Mz)))
cat(sprintf("  RT range: %.1f - %.1f min\n", min(test_data$RT.Start), max(test_data$RT.Start)))
cat(sprintf("  Mean FWHM: %.2f sec (%.3f min)\n", mean(test_data$FWHM) * 60, mean(test_data$FWHM)))

# Save as parquet (efficient format)
cat("\nSaving as parquet...\n")
write_parquet(test_data, "test_data_synthetic.parquet")
cat("✓ Saved: test_data_synthetic.parquet\n")

# Also save as TSV for compatibility
cat("\nSaving as TSV...\n")
write.table(test_data, "test_data_synthetic.tsv",
            sep = "\t", quote = FALSE, row.names = FALSE)
cat("✓ Saved: test_data_synthetic.tsv\n")

cat("\n✅ Synthetic test data generated successfully\n")
cat("\nTo use in tests:\n")
cat('  data <- load_diann_data("test_data_synthetic.parquet")\n')
