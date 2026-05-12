# Test: 3D surface viewing angle + smoothing comparison
# Run: source("tests/manual/test_3d_angles.R")

devtools::load_all()

outdir <- "output_report_test/pass1/S1_Input"
if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

cat("=== Loading data ===\n")
validated <- create_validated_dataset("data/30min_report.parquet")
precursor_data <- validated$data
rt <- precursor_data$RT.Apex
mz <- precursor_data$Precursor.Mz
qty <- precursor_data$Precursor.Quantity

# --- Shared: build smooth intensity grid ---
n_grid <- 40  # coarser = smoother
rt_breaks <- seq(min(rt), max(rt), length.out = n_grid + 1)
mz_breaks <- seq(min(mz), max(mz), length.out = n_grid + 1)
rt_mids <- (rt_breaks[-1] + rt_breaks[-(n_grid + 1)]) / 2
mz_mids <- (mz_breaks[-1] + mz_breaks[-(n_grid + 1)]) / 2

rt_bin <- findInterval(rt, rt_breaks, all.inside = TRUE)
mz_bin <- findInterval(mz, mz_breaks, all.inside = TRUE)

z_raw <- matrix(0, nrow = n_grid, ncol = n_grid)
for (i in seq_along(rt_bin)) {
  z_raw[rt_bin[i], mz_bin[i]] <- z_raw[rt_bin[i], mz_bin[i]] + qty[i]
}

# Strong Gaussian smooth (kernel 7x7)
kern_size <- 7
sigma <- 2.0
kx <- seq(-(kern_size - 1) / 2, (kern_size - 1) / 2)
kern_1d <- exp(-kx^2 / (2 * sigma^2))
kern_2d <- outer(kern_1d, kern_1d)
kern_2d <- kern_2d / sum(kern_2d)

pad <- (kern_size - 1) / 2
z_padded <- matrix(0, nrow = n_grid + 2 * pad, ncol = n_grid + 2 * pad)
z_padded[(pad + 1):(pad + n_grid), (pad + 1):(pad + n_grid)] <- z_raw
for (i in seq_len(pad)) {
  z_padded[i, ] <- z_padded[2 * pad + 1 - i, ]
  z_padded[n_grid + pad + i, ] <- z_padded[n_grid + pad - i + 1, ]
}
for (j in seq_len(pad)) {
  z_padded[, j] <- z_padded[, 2 * pad + 1 - j]
  z_padded[, n_grid + pad + j] <- z_padded[, n_grid + pad - j + 1]
}
z_smooth <- matrix(0, nrow = n_grid, ncol = n_grid)
for (i in seq_len(n_grid)) {
  for (j in seq_len(n_grid)) {
    z_smooth[i, j] <- sum(z_padded[i:(i + kern_size - 1), j:(j + kern_size - 1)] * kern_2d)
  }
}

z_plot <- log10(z_smooth + 1)
# Transpose for x=m/z, y=RT
z_t <- t(z_plot)
col_pal <- grDevices::hcl.colors(256, palette = "Inferno")

render_view <- function(filename, theta, phi, contour = FALSE, image = FALSE,
                        main_suffix = "") {
  png(file.path(outdir, filename), width = 1400, height = 1000, res = 150)
  old_par <- par(mar = c(2, 2, 3, 4), bg = "white")

  args <- list(
    x = mz_mids, y = rt_mids, z = z_t,
    colvar = z_t,
    col = col_pal,
    colkey = list(side = 4, length = 0.6, width = 0.8,
                  cex.axis = 0.8, cex.clab = 0.9),
    theta = theta, phi = phi,
    lighting = TRUE, shade = 0.4,
    border = NA,
    bty = "b2",
    xlab = "m/z (Da)", ylab = "RT (min)",
    zlab = "log10(Intensity)",
    main = sprintf("Intensity Surface %s(theta=%d, phi=%d)",
                   main_suffix, theta, phi),
    cex.main = 1.0, font.main = 2,
    ticktype = "detailed",
    cex.axis = 0.7, cex.lab = 0.85
  )

  if (contour) args$contour <- list(side = "zmin", col = "gray40", lwd = 0.5)
  if (image) args$image <- list(side = "zmin", col = col_pal)

  do.call(plot3D::persp3D, args)
  par(old_par)
  dev.off()
  cat(sprintf("  -> %s\n", filename))
}

cat("\n=== Generating angle comparisons ===\n")

# A: Current angle
render_view("3d_A_current.png", theta = 40, phi = 25)

# B: Rotated to see peaks from m/z side
render_view("3d_B_mz_front.png", theta = -50, phi = 30)

# C: Bird's eye (high phi)
render_view("3d_C_birds_eye.png", theta = -40, phi = 45)

# D: With floor contour projection
render_view("3d_D_contour_floor.png", theta = -50, phi = 30,
            contour = TRUE, main_suffix = "+ contour ")

# E: With floor heatmap projection
render_view("3d_E_image_floor.png", theta = -50, phi = 30,
            image = TRUE, main_suffix = "+ heatmap ")

cat("\n=== Done! Compare 3d_A through 3d_E ===\n")
