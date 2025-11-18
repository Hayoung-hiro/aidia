# DIA Window Optimizer for Astral Narrow-DIA

Advanced R-based tool for optimizing Data-Independent Acquisition (DIA) isolation windows, specifically designed for Thermo Fisher Astral mass spectrometer with narrow-DIA capability. Based on DPPP methodology from Doellinger et al. (2020, 2023).

## Features

- **Dynamic Window Optimization**: RT segment-based precursor distribution equalization
- **Technical Replicate Handling**: Automatic detection and median-based consensus with CV filtering (NEW v2.0)
- **Multiple Instrument Support**: Astral, Orbitrap, TimsTOF, and custom configurations
- **DPPP-Based Optimization**: Target DPPP of 1.25-1.5 for optimal sampling
- **Comprehensive Visualization**: Pre/post-optimization analysis plots
- **Multiple Export Formats**: CSV, TSV, and vendor-specific method files
- **Parquet Support**: Native support for DIA-NN parquet output files

## Installation

### Prerequisites

- R 4.0 or higher
- Required R packages:
  ```r
  install.packages(c("arrow", "dplyr", "ggplot2", "gridExtra", 
                     "jsonlite", "tidyr", "viridis", "scales"))
  ```

### Quick Start

1. Clone or download the project to your local machine
2. Ensure all required packages are installed
3. Run the optimization:

```r
# Set working directory
setwd("path/to/dia_window_optimizer")

# Source the main script
source("main.R")

# Quick optimization
result <- quick_optimize(
  proteome_file = "path/to/diann_output.parquet",
  instrument = "astral",
  target_dppp = 1.25
)
```

## Usage

### Configuration File Method

1. Create or modify the configuration file:
```json
{
  "proteome_file": "path/to/diann_output.parquet",
  "mz_range": [380, 980],
  "rt_segments": 5,
  "instrument_preset": "astral",
  "target_dppp": 1.25,
  "window_mode": "dynamic",
  "min_window_width": 2.0,
  "max_window_width": 80.0,
  "overlap_mode": "percentage",
  "overlap_value": 0.5,
  "output_format": "csv",
  "create_plots": true
}
```

2. Run optimization:
```r
result <- main_optimization(config_file = "config.json")
```

### Command Line Usage

```bash
# With configuration file
Rscript main.R config.json

# Direct parameters
Rscript main.R data.parquet astral 1.25
```

### Available Instruments

| Preset | Description | MS1 Time | MS2 Time | Max Hz |
|--------|-------------|----------|----------|--------|
| astral | Thermo Astral | 5.0 ms | 3.0 ms | 200 Hz |
| orbitrap | Thermo Orbitrap | 100.0 ms | 50.0 ms | 12 Hz |
| orbitrap_exploris | Orbitrap Exploris | 50.0 ms | 22.0 ms | 40 Hz |
| timstof | Bruker timsTOF | 10.0 ms | 2.0 ms | 100 Hz |
| timstof_pro | timsTOF Pro | 10.0 ms | 1.5 ms | 120 Hz |
| sciex_7600 | SCIEX 7600 ZenoTOF | 20.0 ms | 10.0 ms | 50 Hz |
| waters_synapt | Waters SYNAPT | 50.0 ms | 20.0 ms | 20 Hz |

## Technical Replicate Handling (NEW in v2.0)

### Automatic Replicate Detection

The optimizer **automatically detects** and handles technical replicates:

```r
# Load data with 3 technical replicates
result <- create_validated_dataset(
  proteome_file = "data/30min_3runs_report.parquet",
  enable_replicate_consensus = TRUE,  # Default
  max_cv_percent = 20                 # CV% filtering threshold
)

# Check replicate statistics
result$metadata$n_runs                # 3
result$metadata$n_precursors_before   # e.g., 15000 (5000 × 3 runs)
result$metadata$n_precursors_after    # e.g., 4200 (after consensus)
result$metadata$mean_fwhm_cv_pct      # e.g., 8.5%
```

### How It Works

1. **Auto-detection**: Checks for `Run` column in DIA-NN output
2. **Consensus creation**: Uses **median** (robust to outliers)
3. **Quality filtering**: Removes precursors with high CV% (>20% by default)
4. **Singleton preservation**: Precursors in only 1 run are always kept

### Configuration

```json
{
  "input_data": {
    "enable_replicate_consensus": true,
    "min_replicates": 1,
    "max_cv_percent": 20
  }
}
```

### When to Use

✅ **Use replicate handling when**:
- You have multiple LC-MS runs of the same sample
- DIA-NN analyzed multiple raw files together
- You want to improve data quality

❌ **Disable when**:
- You have a single run (auto-detected)
- You want to analyze runs separately

**Full Guide**: See [docs/REPLICATE_HANDLING_GUIDE.md](docs/REPLICATE_HANDLING_GUIDE.md)

## Input Data Requirements

### DIA-NN Output Files

The tool accepts DIA-NN output in the following formats:
- **Parquet files** (`.parquet`) - Recommended for large datasets
- **TSV files** (`.tsv`)
- **CSV files** (`.csv`)

### Required Columns

Your input file must contain these columns (alternative names are automatically detected):
- `RT.Start` or `RT` - Retention time in minutes
- `RT.Stop` or `RT_End` - End retention time
- `Precursor.Mz` or `m/z` - Precursor m/z value
- `FWHM` (optional) - Full Width Half Maximum in minutes

## Output Files

The tool generates several output files:

1. **Method File** (`optimized_windows.csv`): 
   - Window definitions for instrument programming
   - Contains: Window Index, Center m/z, Start m/z, End m/z, Width, RT Segment

2. **Configuration File** (`optimized_windows_config.json`):
   - Complete configuration for reproducibility

3. **Visualization Report** (`optimization_report.pdf`):
   - Pre-optimization analysis plots
   - Post-optimization results
   - Coverage analysis
   - Performance metrics

## Key Parameters

### Optimization Settings

- **target_dppp**: Target DPPP value (default: 1.25)
- **dppp_range**: Acceptable DPPP range [1.0, 5.0]
- **window_mode**: "dynamic" or "fixed" window sizing
- **rt_segments**: Number of RT segments for dynamic optimization

### Window Settings

- **min_window_width**: Minimum isolation window width (Da)
- **max_window_width**: Maximum isolation window width (Da)
- **overlap_mode**: "none", "fixed", or "percentage"
- **overlap_value**: Overlap amount (Da or percentage)

## Example Results

From the test with the provided parquet file:

```
=== OPTIMIZATION SUMMARY ===
Total precursors: 1,190,706
Optimized windows: 202
Achieved DPPP: 4.66
Scan rate: 1.7 Hz
Coverage: 503.8%
Processing time: 75.1 seconds
```

## Performance Notes

- **Large datasets**: Use parquet format for optimal performance
- **Memory usage**: ~1-2 GB RAM for 1M+ precursors
- **Processing time**: ~1-2 minutes for typical proteome datasets
- **Visualization**: Can take additional time for large datasets

## Troubleshooting

### Common Issues

1. **Missing packages**: Install all required R packages
2. **Memory errors**: Reduce RT segments or use data filtering
3. **Empty windows**: Adjust min_precursors_per_window parameter
4. **High DPPP**: Reduce target DPPP or increase window count

### Data Issues

- **RT unit conversion**: Tool automatically detects seconds vs minutes
- **Missing FWHM**: Tool estimates from RT width or uses default
- **Column names**: Alternative column names are automatically mapped

## Algorithm Details

### DPPP Calculation

DPPP = FWHM_seconds / cycle_time_seconds

Where:
- FWHM_seconds: Full Width Half Maximum in seconds
- cycle_time_seconds: Instrument duty cycle time

### Cycle Time Calculation

**Parallel Instruments (Astral, TimsTOF)**:
cycle_time = max(MS1_time, n_windows × MS2_time)

**Sequential Instruments (Orbitrap)**:
cycle_time = MS1_time + (n_windows × MS2_time)

### Dynamic Window Optimization

1. Divide RT range into specified segments
2. Analyze precursor distribution in each segment
3. Calculate optimal window widths for equal precursor distribution
4. Apply width and overlap constraints
5. Validate against instrument limitations

## References

- Doellinger et al. (2020): "DPPP methodology for DIA optimization"
- Doellinger et al. (2023): "Enhanced proteome coverage through RT-dependent windows"

## License

This project is open source. Please cite appropriately if used in publications.

## Support

For issues or questions, please check the troubleshooting section or create an issue in the project repository.