# YAML Migration Guide

## Overview

As of **v2.1 (2025-11-17)**, DIA Window Optimizer has transitioned to **YAML** as the primary configuration format. JSON is still supported for legacy compatibility but is no longer recommended.

---

## Why YAML?

**Advantages over JSON**:
- ✅ **Human-readable**: Clean syntax without brackets and quotes
- ✅ **Editable**: Easy to modify in any text editor
- ✅ **Comments**: Add explanations with `# comment`
- ✅ **Industry standard**: Used by Docker, Kubernetes, GitHub Actions
- ✅ **No dependencies**: Simple parser implemented in base R

**Comparison Example**:

**JSON** (old):
```json
{
  "dppp_parameters": {
    "target_dppp": 7.0,
    "target_satisfaction": 0.70
  }
}
```

**YAML** (new):
```yaml
# DPPP Configuration
dppp_parameters:
  target_dppp: 7.0  # Quant mode
  target_satisfaction: 0.70  # 70% satisfaction
```

---

## Migration Steps

### Step 1: Convert Existing JSON to YAML

**Option A: Use Interactive Builder** (Recommended)
```r
source("scripts/config_builder.R")
config <- run_config_builder()
# Follow prompts to create new YAML config
```

**Option B: Manual Conversion**

**Before** (`config.json`):
```json
{
  "project_metadata": {
    "project_name": "MyProject",
    "date": "2025-11-17"
  },
  "input_data": {
    "input_files": ["data/30min_report.parquet"],
    "current_cycle_time": null
  },
  "instrument": {
    "preset": "fusion_lumos"
  }
}
```

**After** (`config.yaml`):
```yaml
project_metadata:
  project_name: "MyProject"
  date: "2025-11-17"

input_data:
  input_files:
    - "data/30min_report.parquet"
  current_cycle_time: null

instrument:
  preset: "fusion_lumos"
```

### Step 2: Update Script Calls

**Before**:
```r
source("run_with_config.R")
results <- run_optimization("config/myconfig.json")
```

**After**:
```r
source("run_with_config.R")
results <- run_optimization("config/myconfig.yaml")
# Or use .yml extension
results <- run_optimization("config/myconfig.yml")
```

**Note**: The function automatically detects file format. No code changes needed.

### Step 3: Verify Configuration

Test your converted YAML file:
```r
source("R/config_loader.R")
config <- load_optimization_config("config/myconfig.yaml")
print_config_summary(config)
```

---

## YAML Syntax Quick Reference

### Basic Structure

```yaml
# Comments start with #
key: value  # Inline comment

# Nested objects (indentation = 2 spaces)
parent:
  child: value
  another_child: 123

# Arrays (two styles)
# Style 1: Flow style
array: [item1, item2, item3]

# Style 2: Block style (recommended for readability)
array:
  - item1
  - item2
  - item3
```

### Data Types

```yaml
# Strings (quotes optional for simple strings)
string1: simple_string
string2: "string with spaces"
string3: 'single quotes work too'

# Numbers
integer: 42
float: 3.14

# Booleans
bool1: true
bool2: false
bool3: True   # Also valid
bool4: FALSE  # Also valid

# Null
nullable: null
also_null: ~
```

### Common Patterns in DIA Optimizer Configs

```yaml
# Multiple input files
input_data:
  input_files:
    - "data/30min_report.parquet"
    - "data/60min_report.parquet"
    - "data/90min_report.parquet"

# Multiple strategies
mz_optimization:
  strategies:
    - "quantile"
    - "smoothing"
    - "outlier"
    - "coverage"

# Null values (auto-detection)
input_data:
  current_cycle_time: null  # Auto-estimate

scan_settings:
  ms1_scans_per_cycle: null  # Auto-detect
```

---

## Validation and Error Handling

### Valid YAML

```yaml
# ✅ Correct indentation (2 spaces)
dppp_parameters:
  target_dppp: 7.0
  target_satisfaction: 0.70

# ✅ Consistent array style
input_files:
  - "file1.parquet"
  - "file2.parquet"

# ✅ Proper quoting for paths with spaces
input_files:
  - "data/sample data/30min_report.parquet"
```

### Invalid YAML (Common Mistakes)

```yaml
# ❌ Inconsistent indentation
dppp_parameters:
 target_dppp: 7.0  # 1 space
  target_satisfaction: 0.70  # 2 spaces

# ❌ Missing space after colon
dppp_parameters:
  target_dppp:7.0  # Missing space

# ❌ Unquoted strings with special characters
project_name: My Project: Version 2  # Colon causes issues

# ✅ Fix: Use quotes
project_name: "My Project: Version 2"
```

### Validation Workflow

```r
# Load configuration with validation
source("R/config_loader.R")

config <- load_optimization_config("config/myconfig.yaml")
# If invalid, you'll see:
# ❌ Configuration validation failed:
#    - Missing 'dppp_parameters' section
#    - instrument.preset is required

# If valid:
# ✅ Configuration loaded and validated successfully
```

---

## Backward Compatibility

### JSON Files Still Work

```r
# Legacy JSON files are automatically detected and supported
results <- run_optimization("config/legacy_config.json")
# Output: ℹ️  Note: JSON format is legacy. Consider converting to YAML...
```

### Conversion Script (Future Feature)

```r
# Planned for v2.2
source("scripts/json_to_yaml.R")
convert_json_to_yaml("config/old.json", "config/new.yaml")
```

---

## Best Practices

### 1. Use Comments Extensively

```yaml
dppp_parameters:
  # Target DPPP: 7.0 = Quant mode, 1.5 = ID mode
  target_dppp: 7.0

  # 70% of precursors should meet target DPPP
  target_satisfaction: 0.70
```

### 2. Organize by Sections

```yaml
# =============================================================================
# DPPP Configuration
# =============================================================================
dppp_parameters:
  target_dppp: 7.0
  target_satisfaction: 0.70

# =============================================================================
# Output Configuration
# =============================================================================
output:
  output_dir: "results"
  include_plots: true
```

### 3. Use Meaningful Names

```yaml
# ❌ Bad
project_metadata:
  project_name: "proj1"
  analyst: "usr"

# ✅ Good
project_metadata:
  project_name: "Fusion_Lumos_Quant_70pct_30min"
  analyst: "John Doe"
```

### 4. Version Control Your Configs

```bash
# Track configuration files in Git
git add config/*.yaml
git commit -m "Add Quant mode optimization config"

# Use descriptive filenames
config/
├── fusion_lumos_quant_70pct.yaml
├── astral_id_85pct.yaml
└── exploris_balanced.yaml
```

---

## Troubleshooting

### Issue: "Failed to parse configuration"

**Cause**: Invalid YAML syntax

**Solution**:
1. Check indentation (must be 2 spaces consistently)
2. Verify colons have space after them: `key: value`
3. Quote strings with special characters
4. Validate with online YAML linter (yamllint.com)

### Issue: "Configuration validation failed"

**Cause**: Missing required fields or invalid values

**Solution**:
```r
# Check validation errors
source("R/config_loader.R")
config <- load_optimization_config("config/myconfig.yaml")
# Read error messages for specific issues
```

### Issue: "Input file not found"

**Cause**: Incorrect file paths in `input_files`

**Solution**:
```yaml
# Use absolute paths or relative paths from project root
input_data:
  input_files:
    - "data/30min_report.parquet"  # Relative to project root
    # Or
    - "D:/Projects/dia_optimizer/data/30min_report.parquet"  # Absolute
```

---

## Example: Complete YAML Configuration

See [config/optimization_config.yaml](../config/optimization_config.yaml) for a fully-annotated example.

**Quick Start**:
```r
# Copy and customize template
file.copy("config/optimization_config.yaml", "config/myproject.yaml")
# Edit myproject.yaml with your parameters
# Run optimization
source("run_with_config.R")
results <- run_optimization("config/myproject.yaml")
```

---

## Support

**Resources**:
- [CONFIG_BUILDER_GUIDE.md](CONFIG_BUILDER_GUIDE.md) - Interactive builder guide
- [CLAUDE.md](../CLAUDE.md) - Main project documentation
- [config/optimization_config.yaml](../config/optimization_config.yaml) - Annotated template

**YAML Learning Resources**:
- Official YAML spec: https://yaml.org/spec/
- YAML tutorial: https://www.cloudbees.com/blog/yaml-tutorial-everything-you-need-get-started
- Online validator: https://www.yamllint.com/

---

**Version**: 1.0
**Last Updated**: 2025-11-17
**Status**: Production Ready
