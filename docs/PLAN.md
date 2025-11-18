# TDD Development Plan
# DIA Window Optimizer v2.0

**Created**: 2025-11-18
**TDD Framework**: Kent Beck's Test-Driven Development
**Architecture**: 3-Stage Streamlined Pipeline
**Base Document**: [PRD.md](PRD.md)

---

## 🎯 TDD Core Principles (Kent Beck)

### Red-Green-Refactor Cycle

```
┌─────────────────────────────────────────┐
│     Kent Beck's TDD Cycle               │
├─────────────────────────────────────────┤
│                                         │
│  1. 🔴 RED: Write a failing test        │
│     - Define expected behavior          │
│     - Test should fail (not yet impl.)  │
│     - Focus on ONE specific behavior    │
│                                         │
│  2. 🟢 GREEN: Make the test pass        │
│     - Write minimal code to pass        │
│     - Don't optimize yet                │
│     - Focus on correctness only         │
│                                         │
│  3. 🔵 REFACTOR: Clean up the code      │
│     - Improve design without changing   │
│       behavior                          │
│     - Tests must still pass             │
│     - Remove duplication                │
│                                         │
│  4. ♻️ REPEAT: Next failing test        │
│                                         │
└─────────────────────────────────────────┘
```

### TDD Mantras

1. **"Test First, Code Second"** - Always write test before implementation
2. **"One Test, One Assertion"** - Each test should verify one specific behavior
3. **"Baby Steps"** - Make smallest possible changes to pass tests
4. **"Fake It Till You Make It"** - Use hard-coded values initially, generalize later
5. **"Triangulation"** - Add more test cases to force generalization

---

## 📊 Overall Test Strategy

### Test Pyramid

```
                 ┌──────────┐
                 │  E2E     │  (5%)  - Full pipeline tests
                 │  Tests   │
                 └──────────┘
              ┌──────────────┐
              │ Integration  │  (25%) - Stage-to-stage tests
              │   Tests      │
              └──────────────┘
         ┌───────────────────────┐
         │    Unit Tests         │  (70%) - Function-level tests
         │                       │
         └───────────────────────┘
```

**Testing Focus**:
- **70% Unit Tests**: Individual function behavior
- **25% Integration Tests**: Module-to-module interaction
- **5% E2E Tests**: Full pipeline validation

### Test-First Workflow

```
For each Module:
  For each Function:
    1. Write test describing expected behavior (RED)
    2. Run test → Confirm it fails
    3. Write minimal code to pass test (GREEN)
    4. Run test → Confirm it passes
    5. Refactor code while keeping tests green (REFACTOR)
    6. Move to next function
```

---

## 🔴 RED Phase Examples

### Example 1: Data Loading (Stage 1)

#### RED: Write failing test first
```r
# tests/test_stage1_loading.R

test_that("load_diann_data successfully loads parquet with required columns", {
  # Arrange
  test_file <- "fixtures/test_data.parquet"

  # Act
  result <- load_diann_data(test_file)

  # Assert
  expect_s3_class(result, "data.frame")
  expect_true("RT.Start" %in% colnames(result))
  expect_true("Precursor.Mz" %in% colnames(result))
  expect_true("FWHM" %in% colnames(result))
  expect_gt(nrow(result), 0)
})
```

**Run test**: ❌ FAILS - `load_diann_data()` doesn't exist

---

### Example 2: DPPP Calculation (Stage 2)

#### RED: Write failing test first
```r
# tests/test_stage2_dppp.R

test_that("calculate_dppp uses Spectronaut formula correctly", {
  # Arrange
  fwhm_seconds <- 0.6  # 36 seconds
  cycle_time_seconds <- 2.0

  # Act
  result <- calculate_dppp(fwhm_seconds, cycle_time_seconds)

  # Assert
  expected <- (1.7 * 0.6) / 2.0  # = 0.51
  expect_equal(result, expected, tolerance = 0.001)
})
```

**Run test**: ❌ FAILS - `calculate_dppp()` doesn't exist

---

### Example 3: Replicate Consensus (Milestone 2)

#### RED: Write failing test first
```r
# tests/test_replicate_consensus.R

test_that("calculate_consensus returns median for replicates n>=2", {
  # Arrange
  test_data <- tibble(
    Precursor.Id = c("P1", "P1", "P1"),
    RT.Start = c(10.0, 10.2, 10.1),
    FWHM = c(0.5, 0.55, 0.52)
  )

  # Act
  result <- calculate_consensus(test_data, "RT.Start")

  # Assert
  expect_equal(result$consensus_value, 10.1)  # median of 10.0, 10.1, 10.2
  expect_equal(result$n_replicates, 3)
})
```

**Run test**: ❌ FAILS - `calculate_consensus()` doesn't exist

---

## 🟢 GREEN Phase Examples

### Example 1: Data Loading - Minimal Implementation

#### GREEN: Make test pass with simplest code
```r
# R/stage1_data_validation.R

load_diann_data <- function(file_path) {
  # Minimal implementation - just load file
  arrow::read_parquet(file_path)
}
```

**Run test**: ✅ PASSES

---

### Example 2: DPPP Calculation - Minimal Implementation

#### GREEN: Make test pass
```r
# R/stage2_optimization_planning.R

calculate_dppp <- function(fwhm_seconds, cycle_time_seconds) {
  # Spectronaut formula
  (1.7 * fwhm_seconds) / cycle_time_seconds
}
```

**Run test**: ✅ PASSES

---

### Example 3: Replicate Consensus - Minimal Implementation

#### GREEN: Make test pass
```r
# R/replicate_utils.R

calculate_consensus <- function(data, column_name) {
  values <- data[[column_name]]

  list(
    consensus_value = median(values),
    n_replicates = length(values)
  )
}
```

**Run test**: ✅ PASSES

---

## 🔵 REFACTOR Phase Examples

### Example 1: Data Loading - Add Error Handling

#### REFACTOR: Improve while keeping tests green
```r
# R/stage1_data_validation.R

load_diann_data <- function(file_path, rt_range = NULL, mz_range = NULL,
                            show_progress = TRUE) {
  # Validation
  if (!file.exists(file_path)) {
    stop("File not found: ", file_path)
  }

  # Load data
  data <- arrow::read_parquet(file_path)

  # Validate required columns
  required_cols <- c("RT.Start", "Precursor.Mz", "FWHM")
  missing <- setdiff(required_cols, colnames(data))
  if (length(missing) > 0) {
    stop("Missing required columns: ", paste(missing, collapse = ", "))
  }

  # Apply filters
  if (!is.null(rt_range)) {
    data <- data %>%
      filter(RT.Start >= rt_range[1], RT.Start <= rt_range[2])
  }

  if (!is.null(mz_range)) {
    data <- data %>%
      filter(Precursor.Mz >= mz_range[1], Precursor.Mz <= mz_range[2])
  }

  data
}
```

**Run test**: ✅ Still PASSES (behavior unchanged)

---

### Example 2: DPPP Calculation - Add Vectorization

#### REFACTOR: Support vector inputs
```r
# R/stage2_optimization_planning.R

calculate_dppp <- function(fwhm_seconds, cycle_time_seconds) {
  # Vectorized calculation
  (1.7 * fwhm_seconds) / cycle_time_seconds
}
```

**Run test**: ✅ Still PASSES

**Add new test for vectorization**:
```r
test_that("calculate_dppp works with vector inputs", {
  fwhm_vec <- c(0.5, 0.6, 0.7)
  cycle_time <- 2.0

  result <- calculate_dppp(fwhm_vec, cycle_time)

  expect_length(result, 3)
  expect_equal(result[1], (1.7 * 0.5) / 2.0)
})
```

---

### Example 3: Replicate Consensus - Add Geometric CV

#### REFACTOR: Add CV calculation
```r
# R/replicate_utils.R

calculate_consensus <- function(data, column_name) {
  values <- data[[column_name]]
  n <- length(values)

  list(
    consensus_value = median(values),
    n_replicates = n,
    cv_percent = if (n >= 2) geometric_cv(values) else NA_real_
  )
}

geometric_cv <- function(x) {
  if (length(x) < 2) return(NA_real_)

  log_x <- log(x)
  sigma_log <- sd(log_x)

  sqrt(exp(sigma_log^2) - 1) * 100
}
```

**Add new test**:
```r
test_that("calculate_consensus includes CV% for n>=2", {
  test_data <- tibble(
    Precursor.Id = c("P1", "P1", "P1"),
    RT.Start = c(10.0, 10.2, 10.1)
  )

  result <- calculate_consensus(test_data, "RT.Start")

  expect_true("cv_percent" %in% names(result))
  expect_gt(result$cv_percent, 0)
  expect_lt(result$cv_percent, 100)
})
```

**Run tests**: ✅ All PASS

---

## 📋 Milestone 2: Technical Replicate Management (TDD)

**Priority**: P0 (필수)
**Estimated Time**: 2 hours

### Phase 2.1: Core Functions (1 hour)

#### Task 2.1.1: Replicate Group Identification (15 min)

**🔴 RED**: Write test
```r
# tests/test_replicate_utils.R

test_that("identify_replicate_groups counts replicates correctly", {
  # Arrange
  test_data <- tibble(
    Precursor.Id = c("P1", "P1", "P1", "P2", "P2", "P3"),
    Run = c("R1", "R2", "R3", "R1", "R2", "R1"),
    RT.Start = c(10.5, 10.6, 10.4, 20.3, 20.5, 30.2)
  )

  # Act
  result <- identify_replicate_groups(test_data)

  # Assert
  expect_equal(result$n_precursors_unique, 3)
  expect_equal(result$replicate_counts["P1"], 3)
  expect_equal(result$replicate_counts["P2"], 2)
  expect_equal(result$replicate_counts["P3"], 1)
  expect_equal(result$n_singleton, 1)  # P3
  expect_equal(result$n_replicated, 2)  # P1, P2
})
```

**Run test**: ❌ FAILS

**🟢 GREEN**: Minimal implementation
```r
# R/replicate_utils.R

identify_replicate_groups <- function(data) {
  replicate_counts <- data %>%
    group_by(Precursor.Id) %>%
    summarize(n_replicates = n(), .groups = "drop") %>%
    deframe()

  list(
    n_precursors_unique = length(replicate_counts),
    replicate_counts = replicate_counts,
    n_singleton = sum(replicate_counts == 1),
    n_replicated = sum(replicate_counts > 1)
  )
}
```

**Run test**: ✅ PASSES

**🔵 REFACTOR**: Add validation and metadata
```r
identify_replicate_groups <- function(data) {
  # Validate columns
  if (!"Precursor.Id" %in% colnames(data)) {
    stop("Missing column: Precursor.Id")
  }
  if (!"Run" %in% colnames(data)) {
    stop("Missing column: Run")
  }

  # Count replicates
  replicate_counts <- data %>%
    group_by(Precursor.Id) %>%
    summarize(n_replicates = n(), .groups = "drop") %>%
    deframe()

  # Distribution analysis
  n_singleton <- sum(replicate_counts == 1)
  n_replicated <- sum(replicate_counts > 1)

  list(
    n_precursors_unique = length(replicate_counts),
    replicate_counts = replicate_counts,
    n_singleton = n_singleton,
    n_replicated = n_replicated,
    n_runs = length(unique(data$Run)),
    replicate_distribution = table(replicate_counts)
  )
}
```

**Run test**: ✅ Still PASSES

---

#### Task 2.1.2: Geometric CV Calculation (15 min)

**🔴 RED**: Write test
```r
test_that("geometric_cv calculates correctly for log-normal data", {
  # Arrange
  # Known values: log(10.0), log(10.2), log(10.1)
  # sd(log(x)) ≈ 0.00995
  # Geometric CV ≈ sqrt(exp(0.00995^2) - 1) * 100 ≈ 1.0%
  values <- c(10.0, 10.2, 10.1)

  # Act
  result <- geometric_cv(values)

  # Assert
  expect_type(result, "double")
  expect_gt(result, 0)
  expect_lt(result, 5)  # Should be ~1% for this data
})

test_that("geometric_cv returns NA for n<2", {
  expect_true(is.na(geometric_cv(c(10.0))))
  expect_true(is.na(geometric_cv(numeric(0))))
})
```

**Run test**: ❌ FAILS

**🟢 GREEN**: Implementation
```r
# R/replicate_utils.R

geometric_cv <- function(x) {
  # Remove NA values
  x <- x[!is.na(x)]

  if (length(x) < 2) return(NA_real_)

  # Geometric CV formula
  # CV = sqrt(exp(sd(log(x))^2) - 1) * 100
  log_x <- log(x)
  sigma_log <- sd(log_x)

  cv_pct <- sqrt(exp(sigma_log^2) - 1) * 100

  return(cv_pct)
}
```

**Run test**: ✅ PASSES

**Reference**: `docs/GEOMETRIC_CV_GUIDE.md`

---

#### Task 2.1.3: Consensus Calculation (30 min)

**🔴 RED**: Write comprehensive tests
```r
test_that("calculate_consensus_dataset handles replicates correctly", {
  # Arrange
  test_data <- tibble(
    Precursor.Id = c("P1", "P1", "P1", "P2", "P3"),
    Run = c("R1", "R2", "R3", "R1", "R1"),
    RT.Start = c(10.0, 10.2, 10.1, 20.0, 30.0),
    Precursor.Mz = c(400, 401, 400.5, 500, 600),
    FWHM = c(0.5, 0.55, 0.52, 0.6, 0.45)
  )

  # Act
  result <- calculate_consensus_dataset(test_data)

  # Assert - P1 (n=3)
  p1 <- result %>% filter(Precursor.Id == "P1")
  expect_equal(p1$RT.Start, 10.1)  # median
  expect_equal(p1$n_replicates, 3)
  expect_false(is.na(p1$RT_CV_pct))

  # Assert - P3 (n=1)
  p3 <- result %>% filter(Precursor.Id == "P3")
  expect_equal(p3$RT.Start, 30.0)  # original
  expect_equal(p3$n_replicates, 1)
  expect_true(is.na(p3$RT_CV_pct))  # Singleton CV = NA
})
```

**Run test**: ❌ FAILS

**🟢 GREEN**: Implementation
```r
# R/replicate_utils.R

calculate_consensus_dataset <- function(data, min_replicates = 1,
                                        max_cv_percent = 20) {
  # Group by Precursor.Id
  consensus <- data %>%
    group_by(Precursor.Id) %>%
    summarise(
      # Median values (robust to outliers)
      RT.Start = median(RT.Start, na.rm = TRUE),
      Precursor.Mz = median(Precursor.Mz, na.rm = TRUE),
      FWHM = median(FWHM, na.rm = TRUE),

      # Geometric CV% calculation
      RT_CV_pct = if (n() >= 2) geometric_cv(RT.Start) else NA_real_,
      Mz_CV_pct = if (n() >= 2) geometric_cv(Precursor.Mz) else NA_real_,
      FWHM_CV_pct = if (n() >= 2) geometric_cv(FWHM) else NA_real_,

      n_replicates = n(),
      .groups = "drop"
    )

  # CV filtering (keep singletons)
  consensus %>%
    filter(
      n_replicates >= min_replicates,
      (n_replicates == 1 | is.na(FWHM_CV_pct) | FWHM_CV_pct <= max_cv_percent)
    )
}
```

**Run test**: ✅ PASSES

**🔵 REFACTOR**: Add metadata
```r
calculate_consensus_dataset <- function(data, min_replicates = 1,
                                        max_cv_percent = 20) {
  n_before <- nrow(data)

  # Identify replicates
  rep_info <- identify_replicate_groups(data)

  # Calculate consensus
  consensus <- data %>%
    group_by(Precursor.Id) %>%
    summarise(
      RT.Start = median(RT.Start, na.rm = TRUE),
      Precursor.Mz = median(Precursor.Mz, na.rm = TRUE),
      FWHM = median(FWHM, na.rm = TRUE),

      RT_CV_pct = if (n() >= 2) geometric_cv(RT.Start) else NA_real_,
      Mz_CV_pct = if (n() >= 2) geometric_cv(Precursor.Mz) else NA_real_,
      FWHM_CV_pct = if (n() >= 2) geometric_cv(FWHM) else NA_real_,

      n_replicates = n(),
      .groups = "drop"
    )

  # CV filtering
  filtered <- consensus %>%
    filter(
      n_replicates >= min_replicates,
      (n_replicates == 1 | is.na(FWHM_CV_pct) | FWHM_CV_pct <= max_cv_percent)
    )

  # Add metadata
  attr(filtered, "metadata") <- list(
    n_runs = rep_info$n_runs,
    n_precursors_before = n_before,
    n_precursors_unique = rep_info$n_precursors_unique,
    n_precursors_after = nrow(filtered),
    n_singleton = sum(filtered$n_replicates == 1),
    n_replicated = sum(filtered$n_replicates > 1),
    n_filtered_cv = nrow(consensus) - nrow(filtered),
    mean_rt_cv_pct = mean(filtered$RT_CV_pct, na.rm = TRUE),
    mean_fwhm_cv_pct = mean(filtered$FWHM_CV_pct, na.rm = TRUE)
  )

  filtered
}
```

**Run test**: ✅ Still PASSES

---

### Phase 2.2: Stage 1 Integration (30 min)

#### Task 2.2.1: Extend create_validated_dataset() (20 min)

**🔴 RED**: Write integration test
```r
# tests/test_stage1_integration.R

test_that("create_validated_dataset handles replicates when enabled", {
  # Arrange
  test_file <- "fixtures/3_replicates_data.parquet"

  # Act
  result <- create_validated_dataset(
    test_file,
    enable_replicate_consensus = TRUE,
    max_cv_percent = 20
  )

  # Assert
  expect_s3_class(result, "ValidatedData")
  expect_true("n_runs" %in% names(result$metadata))
  expect_gt(result$metadata$n_runs, 1)
  expect_true("mean_fwhm_cv_pct" %in% names(result$metadata))

  # Check data has CV columns
  expect_true("RT_CV_pct" %in% colnames(result$data))
  expect_true("n_replicates" %in% colnames(result$data))
})

test_that("create_validated_dataset works with single run", {
  test_file <- "fixtures/single_run_data.parquet"

  result <- create_validated_dataset(
    test_file,
    enable_replicate_consensus = TRUE
  )

  expect_equal(result$metadata$n_runs, 1)
  expect_false("RT_CV_pct" %in% colnames(result$data))  # No CV for single run
})
```

**Run test**: ❌ FAILS

**🟢 GREEN**: Modify Stage 1
```r
# R/stage1_data_validation.R

create_validated_dataset <- function(
  proteome_file,
  apply_quality_filters = TRUE,
  enable_replicate_consensus = TRUE,
  min_replicates = 1,
  max_cv_percent = 20,
  rt_range = NULL,
  mz_range = NULL
) {

  # Load data
  data_raw <- load_diann_data(proteome_file, rt_range, mz_range)

  # Quality filters
  if (apply_quality_filters) {
    data_qc <- apply_diann_quality_filters(data_raw)
  } else {
    data_qc <- data_raw
  }

  # Check for replicates
  n_runs <- length(unique(data_qc$Run))

  # Replicate handling
  if (n_runs > 1 && enable_replicate_consensus) {
    cat(sprintf("\n📊 Detected %d runs (technical replicates)\n", n_runs))
    cat("   Creating consensus dataset...\n\n")

    data_final <- calculate_consensus_dataset(
      data_qc,
      min_replicates = min_replicates,
      max_cv_percent = max_cv_percent
    )

    # Extract metadata
    consensus_meta <- attr(data_final, "metadata")

  } else {
    cat("\n📊 Single run detected (no replication)\n\n")
    data_final <- data_qc
    consensus_meta <- list(n_runs = 1)
  }

  # Construct ValidatedData object
  metadata <- list(
    n_precursors = nrow(data_final),
    rt_range = range(data_final$RT.Start),
    mz_range = range(data_final$Precursor.Mz),
    fwhm_stats = list(
      mean = mean(data_final$FWHM),
      median = median(data_final$FWHM),
      sd = sd(data_final$FWHM)
    )
  )

  # Merge replicate metadata
  metadata <- c(metadata, consensus_meta)

  structure(
    list(
      data = data_final,
      metadata = metadata
    ),
    class = c("ValidatedData", "list")
  )
}
```

**Run test**: ✅ PASSES

---

#### Task 2.2.2: Update Configuration (10 min)

**🔴 RED**: Write config test
```r
test_that("load_config reads replicate parameters correctly", {
  # Arrange
  test_config <- '{
    "input_data": {
      "enable_replicate_consensus": true,
      "min_replicates": 1,
      "max_cv_percent": 20
    }
  }'
  writeLines(test_config, "test_config.json")

  # Act
  config <- load_config("test_config.json")

  # Assert
  expect_true(config$input_data$enable_replicate_consensus)
  expect_equal(config$input_data$max_cv_percent, 20)

  # Cleanup
  unlink("test_config.json")
})
```

**🟢 GREEN**: Update config structure
```json
// config/optimization_config.json

{
  "input_data": {
    "input_files": ["data/30min_report.parquet"],
    "current_cycle_time": 2.0,

    "enable_replicate_consensus": true,
    "min_replicates": 1,
    "max_cv_percent": 20
  },

  "optimization": {
    "target_dppp": 7.0,
    "instrument_type": "astral",
    "mz_strategy": "smoothing",
    "window_mode": "variable"
  }
}
```

---

### Phase 2.3: Testing & Validation (30 min)

#### Task 2.3.1: Unit Tests (20 min)

**Complete test suite**:
```r
# tests/test_replicate_utils.R

# Test 1: Replicate identification
test_that("identify_replicate_groups works", { ... })

# Test 2: Geometric CV calculation
test_that("geometric_cv is accurate", { ... })

# Test 3: Consensus calculation
test_that("calculate_consensus_dataset handles mixed replicates", {
  # Test with mix of n=1, n=2, n=3
})

# Test 4: CV filtering
test_that("CV filtering keeps singletons", {
  # Verify singletons kept regardless of CV threshold
})

# Test 5: Edge cases
test_that("consensus handles NA values correctly", { ... })
test_that("consensus handles identical values", { ... })
```

#### Task 2.3.2: Integration Testing (10 min)

**Real data test**:
```r
# tests/test_milestone2_integration.R

test_that("Milestone 2 works with real 30min gradient data", {
  # Use actual 3-replicate data
  result <- create_validated_dataset(
    "data/30min_3runs_report.parquet",
    enable_replicate_consensus = TRUE
  )

  # Assertions
  expect_equal(result$metadata$n_runs, 3)
  expect_lt(result$metadata$mean_fwhm_cv_pct, 20)
  expect_gt(result$metadata$n_singleton + result$metadata$n_replicated,
            result$metadata$n_precursors * 0.9)  # >90% retention
})
```

---

## 📋 Milestone 3: Documentation & Validation (TDD for Docs)

**Priority**: P1 (높음)
**Estimated Time**: 1 hour

### Documentation Testing Approach

**Principle**: Documentation should be testable through code examples

#### Task 3.1: README Update with Runnable Examples (30 min)

**Documentation Test**:
```r
# tests/test_documentation_examples.R

test_that("README replicate example runs correctly", {
  # This test verifies that documentation examples actually work

  # Example from README
  result <- create_validated_dataset(
    "data/example_3runs.parquet",
    enable_replicate_consensus = TRUE,
    min_replicates = 1,
    max_cv_percent = 20
  )

  # Verify documented behavior
  expect_true("RT_CV_pct" %in% colnames(result$data))
  expect_gt(result$metadata$n_runs, 1)
})
```

**README Content** (verified by test):
```markdown
# README.md

## Technical Replicate Handling

### Quick Start
```r
# Load data with 3 technical replicates
validated <- create_validated_dataset(
  "report.parquet",
  enable_replicate_consensus = TRUE,
  max_cv_percent = 20
)

# Check replicate statistics
validated$metadata$n_runs           # 3
validated$metadata$mean_fwhm_cv_pct # e.g., 8.5%
```

### Configuration
```json
{
  "enable_replicate_consensus": true,
  "min_replicates": 1,      // Include singletons
  "max_cv_percent": 20      // Filter high-CV precursors
}
```
```

---

#### Task 3.2: End-to-End Pipeline Test (30 min)

**E2E Test as Documentation**:
```r
# tests/test_e2e_pipeline.R

test_that("Complete pipeline runs successfully with replicates", {
  # This test serves as documentation for full workflow

  # Stage 1: Data Validation
  validated <- create_validated_dataset(
    "fixtures/30min_3runs.parquet",
    enable_replicate_consensus = TRUE,
    max_cv_percent = 20
  )

  expect_equal(validated$metadata$n_runs, 3)
  expect_lt(validated$metadata$mean_fwhm_cv_pct, 20)

  # Stage 2: Optimization Planning
  plan <- create_optimization_plan(
    validated,
    target_dppp = 7.0,
    instrument_type = "astral"
  )

  expect_true(plan$feasible)
  expect_gt(plan$expected_window_count, 0)

  # Stage 3: Window Optimization
  windows <- optimize_isolation_windows(
    validated,
    plan,
    mz_strategy = "smoothing",
    window_mode = "variable"
  )

  expect_equal(nrow(windows$windows), plan$expected_window_count, tolerance = 1)

  # Stage 4: Visualization
  viz <- generate_visualizations(
    validated,
    plan,
    windows,
    output_dir = tempdir()
  )

  expect_true(file.exists(viz$pdf_report))
  expect_true(file.exists(viz$method_file))
})
```

**This test documents**:
- ✅ Complete workflow from input to output
- ✅ Replicate handling integration
- ✅ Stage-to-stage data flow
- ✅ Expected outputs

---

## 📊 TDD Best Practices for This Project

### 1. Arrange-Act-Assert (AAA) Pattern

**Always follow AAA structure**:
```r
test_that("function does expected behavior", {
  # Arrange - Set up test data and expectations
  test_data <- create_test_data()
  expected_result <- 42

  # Act - Execute the function under test
  result <- my_function(test_data)

  # Assert - Verify expectations
  expect_equal(result, expected_result)
})
```

### 2. Test Naming Convention

**Pattern**: `test_that("function_name does_what when_condition", { })`

**Good examples**:
```r
test_that("calculate_dppp returns correct value for valid inputs", { })
test_that("geometric_cv returns NA when n < 2", { })
test_that("filter_by_cv keeps singletons regardless of CV threshold", { })
```

### 3. One Assertion per Test (when possible)

**Prefer specific tests**:
```r
# Good - Focused tests
test_that("geometric_cv returns numeric value", {
  expect_type(geometric_cv(c(1, 2, 3)), "double")
})

test_that("geometric_cv returns positive value", {
  expect_gt(geometric_cv(c(1, 2, 3)), 0)
})

# Acceptable - Related assertions
test_that("geometric_cv returns valid CV percentage", {
  result <- geometric_cv(c(10.0, 10.2, 10.1))
  expect_type(result, "double")
  expect_gt(result, 0)
  expect_lt(result, 100)
})
```

### 4. Test Independence

**Each test should be self-contained**:
```r
# Good - Independent test
test_that("function works", {
  data <- create_test_data()  # Fresh data
  result <- my_function(data)
  expect_true(result$valid)
})

# Bad - Depends on global state
# Assumes 'data' exists from previous test
test_that("function works", {
  result <- my_function(data)  # Where does 'data' come from?
})
```

### 5. Use Fixtures for Complex Data

**Create reusable test fixtures**:
```r
# tests/fixtures/create_test_fixtures.R

create_replicate_test_data <- function(n_precursors = 100, n_runs = 3) {
  tibble(
    Precursor.Id = rep(paste0("P", 1:n_precursors), each = n_runs),
    Run = rep(paste0("R", 1:n_runs), n_precursors),
    RT.Start = rnorm(n_precursors * n_runs, 50, 10),
    Precursor.Mz = rnorm(n_precursors * n_runs, 600, 100),
    FWHM = rnorm(n_precursors * n_runs, 0.5, 0.1)
  )
}

# Use in tests
test_that("consensus works", {
  data <- create_replicate_test_data(n_precursors = 10, n_runs = 3)
  result <- calculate_consensus_dataset(data)
  # ...
})
```

---

## 🎯 TDD Anti-Patterns to Avoid

### ❌ Don't: Write tests after implementation
```r
# Wrong order
implement_feature()  # Implementation first
write_test()         # Test second

# Correct TDD order
write_test()         # Test first (RED)
implement_feature()  # Implementation second (GREEN)
refactor()           # Clean up (REFACTOR)
```

### ❌ Don't: Test implementation details
```r
# Bad - Tests HOW function works internally
test_that("function uses for loop", {
  # Checking internal implementation
})

# Good - Tests WHAT function does (behavior)
test_that("function returns correct result for valid input", {
  expect_equal(my_function(input), expected_output)
})
```

### ❌ Don't: Make tests dependent on each other
```r
# Bad - Sequential dependency
test_that("step 1", { global_data <<- create_data() })
test_that("step 2", { result <- process(global_data) })  # Fails if run alone

# Good - Independent tests
test_that("step 1", {
  data <- create_data()
  expect_valid(data)
})
test_that("step 2", {
  data <- create_data()  # Create own data
  result <- process(data)
  expect_equal(result, expected)
})
```

### ❌ Don't: Skip the RED phase
```r
# Bad - Write code first, then test
calculate_dppp <- function(fwhm, cycle_time) {
  (1.7 * fwhm) / cycle_time
}
test_that("dppp works", { ... })  # Test always passes

# Good - Test first (RED → GREEN → REFACTOR)
# 1. Write test (fails - RED)
test_that("dppp works", { ... })
# 2. Write code to pass (GREEN)
calculate_dppp <- function(...) { ... }
# 3. Refactor while keeping tests green
```

---

## 📈 TDD Metrics & Success Criteria

### Code Coverage Targets
- **Stage 1**: ≥ 85% coverage
- **Stage 2**: ≥ 85% coverage
- **Stage 3**: ≥ 80% coverage (complex algorithms)
- **Stage 4**: ≥ 75% coverage (visualization)
- **Overall Project**: ≥ 80% coverage

### Test Success Rate
- **Unit Tests**: 100% pass (no failures allowed)
- **Integration Tests**: 100% pass
- **E2E Tests**: 100% pass

### Test Execution Time
- **Unit Tests**: < 30 seconds (all tests)
- **Integration Tests**: < 2 minutes
- **E2E Tests**: < 5 minutes

---

## 🗓️ TDD Development Schedule

### Week 1: Milestone 2 Implementation (TDD)

**Day 1**: Core Functions (1 hour)
- Task 2.1.1: Replicate identification (RED → GREEN → REFACTOR) - 15 min
- Task 2.1.2: Geometric CV (RED → GREEN → REFACTOR) - 15 min
- Task 2.1.3: Consensus calculation (RED → GREEN → REFACTOR) - 30 min

**Day 2**: Stage 1 Integration (30 min)
- Task 2.2.1: Extend create_validated_dataset() - 20 min
- Task 2.2.2: Update configuration - 10 min

**Day 3**: Testing & Validation (30 min)
- Task 2.3.1: Complete unit test suite - 20 min
- Task 2.3.2: Integration tests with real data - 10 min

### Week 2: Milestone 3 Validation

**Day 1**: Documentation (30 min)
- Task 3.1: README update with runnable examples - 30 min

**Day 2**: E2E Testing (30 min)
- Task 3.2: End-to-end pipeline test - 30 min

**Day 3**: Final Validation
- Run all tests (unit + integration + E2E)
- Code coverage analysis
- Performance benchmarks

**Total Estimated Time**: 3 hours
**Expected Completion**: 2025-11-20

---

## ✅ Milestone Success Criteria (TDD-Based)

### Milestone 2: Technical Replicate Management

**Test-Driven Success Criteria**:
1. ✅ All unit tests pass (100%)
2. ✅ Code coverage ≥ 85% for replicate_utils.R
3. ✅ Integration test with 3-run data passes
4. ✅ Geometric CV% < 20% for quality precursors
5. ✅ Singleton handling verified (CV% = NA)
6. ✅ QC filtering retains >90% of precursors

### Milestone 3: Documentation & Validation

**Test-Driven Success Criteria**:
1. ✅ Documentation examples run without errors
2. ✅ E2E pipeline test passes (100%)
3. ✅ Stage-to-stage data flow validated
4. ✅ Method file generation verified
5. ✅ All workflow tests green

---

## 📚 References

### Kent Beck's TDD Principles
- **"Test-Driven Development: By Example"** (2002)
  - Chapter 1: Multi-Currency Money (TDD basics)
  - Chapter 2: Red-Green-Refactor cycle
  - Chapter 18: Test first vs. test after

### TDD Patterns Applied
1. **Test First** - All functions have tests written before implementation
2. **Assert First** - Write assertions before setup code
3. **Test List** - Maintain list of tests to write
4. **Triangulation** - Add test cases to force generalization
5. **Fake It Till You Make It** - Start with hard-coded values, generalize incrementally

### Project-Specific Guides
- [docs/PRD.md](PRD.md) - Product requirements
- [docs/SMOOTHING_GLOBAL_VS_LOCAL.md](SMOOTHING_GLOBAL_VS_LOCAL.md) - m/z optimization
- [docs/GEOMETRIC_CV_GUIDE.md](GEOMETRIC_CV_GUIDE.md) - CV calculation guide
- [docs/ARCHITECTURE.md](ARCHITECTURE.md) - System architecture

---

## 🎓 TDD Learning Path

### Beginner TDD Workflow
```
1. Read requirements from PRD
2. Write ONE failing test (RED)
3. Run test - confirm it fails
4. Write MINIMAL code to pass (GREEN)
5. Run test - confirm it passes
6. Refactor code (REFACTOR)
7. Run test - confirm still passes
8. Repeat for next requirement
```

### Intermediate TDD Workflow
```
1. Write multiple related tests (test list)
2. Pick simplest test - make it pass
3. Refactor continuously
4. Use fixtures for complex data
5. Triangulate to force generalization
```

### Advanced TDD Workflow
```
1. Design through tests
2. Use tests as specifications
3. Refactor aggressively with safety net
4. Write integration tests for workflows
5. Document through executable examples
```

---

**TDD Motto**: *"Red, Green, Refactor - The rhythm of reliable code"*

**Remember**:
- Tests are not just verification - they are **specifications**, **documentation**, and **design tools**
- Write the test you wish you had
- Let tests drive your design
- Refactor fearlessly with green tests as your safety net

---

**Author**: Claude Code Assistant
**Last Updated**: 2025-11-18
**Version**: 1.0 (TDD-Based Development Plan)
**Base Document**: PRD.md v2.0.1
