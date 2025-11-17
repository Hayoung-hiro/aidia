---
description: "TDD for Bug Fixes: Test-driven defect resolution"
---

# TDD for Bug Fixes: Test-Driven Defect Resolution

You are following Kent Beck's Test-Driven Development (TDD) methodology for fixing bugs.

## Bug Fix Workflow

When fixing a defect, follow this strict sequence:

### Step 1: Write API-Level Failing Test
**Purpose**: Verify the bug exists at the user-facing level

```r
test_that("create_consensus_dataset handles multiple runs correctly", {
  # Reproduce the bug at API level
  data <- load_real_data_that_triggers_bug()

  result <- create_consensus_dataset(data)

  # What SHOULD happen (currently fails)
  expect_equal(nrow(result$data), expected_unique_count)
  expect_false(has_duplicate_precursors(result$data))
})
```

Run test → FAILS (confirms bug exists)

### Step 2: Write Smallest Possible Failing Test
**Purpose**: Isolate the root cause

```r
test_that("aggregate_replicates removes duplicate precursor entries", {
  # Minimal reproduction case
  data <- tibble(
    Precursor.Id = c("P1", "P1", "P1"),  # 3 runs, same precursor
    Run = c("Run1", "Run2", "Run3"),
    RT.Start = c(10.0, 10.1, 10.2)
  )

  result <- aggregate_replicates(data)

  # Should return 1 row, not 3
  expect_equal(nrow(result), 1)
  expect_equal(result$Precursor.Id[1], "P1")
  expect_equal(result$RT.Start[1], 10.1)  # median
})
```

Run test → FAILS (pinpoints exact issue)

### Step 3: Make Both Tests Pass
**Purpose**: Fix the bug

```r
aggregate_replicates <- function(data) {
  # FIX: Group by Precursor.Id to aggregate replicates
  result <- data %>%
    group_by(Precursor.Id) %>%
    summarise(
      RT.Start = median(RT.Start),
      n_replicates = n(),
      .groups = "drop"
    )

  return(result)
}
```

Run tests → BOTH PASS

### Step 4: Refactor If Needed
**Purpose**: Improve code quality

```r
# Extract aggregation logic for reuse
calculate_consensus_value <- function(values, method = "median") {
  switch(method,
    median = median(values, na.rm = TRUE),
    mean = mean(values, na.rm = TRUE),
    stop("Unknown method: ", method)
  )
}

aggregate_replicates <- function(data, method = "median") {
  result <- data %>%
    group_by(Precursor.Id) %>%
    summarise(
      RT.Start = calculate_consensus_value(RT.Start, method),
      n_replicates = n(),
      .groups = "drop"
    )

  return(result)
}
```

Run tests → ALL PASS

## Complete Bug Fix Example

### Scenario: 30min dataset has 23,379 rows but should have ~7,793

**Problem**: Technical replicates (3 runs) not being aggregated

#### Test 1: API-Level Test
```r
test_that("30min dataset aggregates technical replicates correctly", {
  # Load real problematic data
  data_raw <- load_diann_data("data/30min_report.parquet")

  # Current: 23,379 rows (3 runs × ~7,793 precursors)
  expect_equal(nrow(data_raw), 23379)

  # Apply consensus
  result <- create_consensus_dataset(data_raw)

  # Should: ~7,793 unique precursors
  expect_lt(nrow(result$data), 8000)
  expect_gt(nrow(result$data), 7500)

  # No duplicates
  expect_false(any(duplicated(result$data$Precursor.Id)))
})
```

#### Test 2: Unit-Level Test
```r
test_that("group_by Precursor.Id aggregates replicates", {
  # Minimal case
  data <- tibble(
    Precursor.Id = c("P1", "P1", "P1", "P2", "P2"),
    Run = c("R1", "R2", "R3", "R1", "R2"),
    RT.Start = c(10.0, 10.2, 10.1, 15.0, 15.1)
  )

  result <- aggregate_by_precursor(data)

  expect_equal(nrow(result), 2)  # 2 unique precursors
  expect_equal(result$Precursor.Id, c("P1", "P2"))
  expect_equal(result$RT.Start[1], 10.1)  # median of P1
  expect_equal(result$RT.Start[2], 15.05)  # median of P2
})
```

#### Implementation
```r
aggregate_by_precursor <- function(data) {
  data %>%
    group_by(Precursor.Id) %>%
    summarise(
      RT.Start = median(RT.Start, na.rm = TRUE),
      FWHM = median(FWHM, na.rm = TRUE),
      Precursor.Mz = median(Precursor.Mz, na.rm = TRUE),
      n_replicates = n(),
      .groups = "drop"
    )
}

create_consensus_dataset <- function(data, ...) {
  # Detect multiple runs
  n_runs <- length(unique(data$Run))

  if (n_runs > 1) {
    cat(sprintf("📊 Detected %d runs - aggregating replicates\n", n_runs))
    data <- aggregate_by_precursor(data)
  }

  return(list(data = data, qc_report = generate_qc_report(data)))
}
```

#### Verification
```r
# Run both tests
testthat::test_file("tests/test_replicate_aggregation.R")
# ✓ 30min dataset aggregates technical replicates correctly
# ✓ group_by Precursor.Id aggregates replicates

# Run all tests
testthat::test_dir("tests/")
# ✓ All tests passing
```

## Bug Fix Commit Strategy

**Commit 1** (Tests only):
```bash
git add tests/
git commit -m "test: add failing tests for replicate aggregation bug

- API-level test: 30min dataset should have ~7,793 unique precursors
- Unit test: aggregate_by_precursor should group by Precursor.Id
- Both tests currently fail (expected)"
```

**Commit 2** (Fix):
```bash
git add R/
git commit -m "fix: aggregate technical replicates in consensus dataset

- Add aggregate_by_precursor() to group replicates
- Detect multiple runs and auto-aggregate
- Resolves: 23,379 rows → 7,793 unique precursors
- Tests: Both API and unit tests now pass"
```

**Commit 3** (Optional refactor):
```bash
git commit -m "refactor: extract consensus calculation helper

- Add calculate_consensus_value() for flexibility
- Support median (default) and mean methods
- No behavior change, all tests pass"
```

## Key Principles for Bug Fixes

1. **Reproduce First**: API-level test proves bug exists
2. **Isolate**: Unit test pinpoints root cause
3. **Fix Minimal**: Change only what's necessary
4. **Verify**: Both tests must pass
5. **Prevent Regression**: Tests stay in suite permanently

## Anti-Patterns to Avoid

❌ **Don't**: Fix the bug without writing tests first
❌ **Don't**: Write only unit tests (miss integration issues)
❌ **Don't**: Write only API tests (hard to debug)
❌ **Don't**: Fix multiple bugs in one commit
❌ **Don't**: Skip refactoring if code quality is poor

✅ **Do**: API test + Unit test + Minimal fix + Refactor + Commit

**Remember**: Every bug is an opportunity to improve your test coverage.
