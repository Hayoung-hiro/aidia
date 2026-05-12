# Archived Exploration Scripts

These scripts were one-shot exploration tools used during the v0.4.0
reporting redesign. They are kept here for reference but are not part
of the active test suite.

| Script | Purpose |
|--------|---------|
| `test_3d_angles.R` | Compare `plot3D::persp3D` viewing angles (theta/phi) and floor-projection variants for the RT x m/z intensity surface |
| `test_3d_comparison.R` | Compare 3D surface renderers: `plot3D::persp3D` vs `rayshader` vs 2D contour reference |
| `test_plot_comparison.R` | Side-by-side PNG generation of redesigned plots (heatmap, FWHM, DPPP table, satisfaction) for visual comparison |
| `style_comparison.R` | Compare three publication theme/palette variants on a synthetic strategy bar chart |

If you want to revive any of these, copy back into `tests/manual/`
and run with `source(...)`. They use real data in `data/` and write
PNGs to `output_report_test/`.
