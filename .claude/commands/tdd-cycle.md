---
description: "Complete TDD Cycle: Red-Green-Refactor workflow"
---

# Complete TDD Cycle: Red-Green-Refactor

You are following Kent Beck's Test-Driven Development (TDD) methodology.

## The TDD Cycle

```
   ┌─────────────────────────────────────┐
   │                                     │
   │  1. RED: Write Failing Test         │
   │     └─> Test describes behavior     │
   │                                     │
   └────────────┬────────────────────────┘
                ↓
   ┌─────────────────────────────────────┐
   │                                     │
   │  2. GREEN: Make Test Pass           │
   │     └─> Minimal implementation      │
   │                                     │
   └────────────┬────────────────────────┘
                ↓
   ┌─────────────────────────────────────┐
   │                                     │
   │  3. REFACTOR: Improve Structure     │
   │     └─> Keep tests passing          │
   │                                     │
   └────────────┬────────────────────────┘
                ↓
          (Repeat for next feature)
```

## Complete Workflow

### Phase 1: RED (Write Failing Test)
```bash
# Use command: /tdd-red
```
1. Write ONE failing test for smallest unit of functionality
2. Test should have meaningful name
3. Run test - confirm it FAILS for the right reason
4. Do NOT implement yet

**Checklist**:
- [ ] Test written with clear name
- [ ] Test runs and fails
- [ ] Failure message is informative
- [ ] Ready for implementation

### Phase 2: GREEN (Make Test Pass)
```bash
# Use command: /tdd-green
```
1. Write MINIMAL code to make test pass
2. Use simplest solution possible
3. Run test - confirm it PASSES
4. Run ALL tests - confirm nothing broke

**Checklist**:
- [ ] Minimal implementation written
- [ ] New test passes
- [ ] All tests pass
- [ ] Ready for refactoring

### Phase 3: REFACTOR (Improve Structure)
```bash
# Use command: /tdd-refactor
```
1. Identify structural improvements
2. Make ONE change at a time
3. Run tests after EACH change
4. Commit when complete

**Checklist**:
- [ ] Code duplication eliminated
- [ ] Names are clear and descriptive
- [ ] Structure is clean
- [ ] All tests still pass
- [ ] Changes committed

### Commit Strategy

**After GREEN** (Optional - if no refactoring needed):
```bash
git add .
git commit -m "feat: implement <feature description>

- Add <function_name>() for <purpose>
- Test: <test_name> passes
- All tests passing"
```

**After REFACTOR** (Preferred - separate commits):
```bash
# Commit behavioral change (GREEN)
git commit -m "feat: implement <feature description>"

# Commit structural change (REFACTOR)
git commit -m "refactor: <structural improvement description>"
```

## Example: Complete Cycle for Replicate Handling

### Iteration 1: Basic Median Calculation

**RED**:
```r
test_that("consensus dataset returns median RT for replicates", {
  # Arrange
  data <- tibble(
    Precursor.Id = c("P1", "P1", "P1"),
    RT.Start = c(10.0, 10.2, 10.1)
  )

  # Act
  result <- create_consensus_dataset(data)

  # Assert
  expect_equal(result$data$RT.Start[1], 10.1)  # median
})
```
Run test → FAILS (function doesn't exist)

**GREEN**:
```r
create_consensus_dataset <- function(data) {
  result <- data %>%
    group_by(Precursor.Id) %>%
    summarise(RT.Start = median(RT.Start))

  return(list(data = result))
}
```
Run test → PASSES

**REFACTOR**: (Not needed yet, simple code)

**Commit**: `feat: implement median RT calculation for consensus dataset`

### Iteration 2: Add FWHM

**RED**:
```r
test_that("consensus dataset returns median FWHM for replicates", {
  data <- tibble(
    Precursor.Id = c("P1", "P1", "P1"),
    RT.Start = c(10.0, 10.2, 10.1),
    FWHM = c(0.05, 0.06, 0.055)
  )

  result <- create_consensus_dataset(data)

  expect_equal(result$data$FWHM[1], 0.055)  # median
})
```
Run test → FAILS (FWHM not in result)

**GREEN**:
```r
create_consensus_dataset <- function(data) {
  result <- data %>%
    group_by(Precursor.Id) %>%
    summarise(
      RT.Start = median(RT.Start),
      FWHM = median(FWHM)
    )

  return(list(data = result))
}
```
Run test → PASSES

**REFACTOR**: Extract aggregation logic
```r
aggregate_column <- function(values) {
  median(values, na.rm = TRUE)
}

create_consensus_dataset <- function(data) {
  result <- data %>%
    group_by(Precursor.Id) %>%
    summarise(
      RT.Start = aggregate_column(RT.Start),
      FWHM = aggregate_column(FWHM)
    )

  return(list(data = result))
}
```
Run tests → ALL PASS

**Commits**:
1. `feat: add FWHM median calculation to consensus dataset`
2. `refactor: extract aggregate_column helper function`

## Key Principles

1. **Small Steps**: Each test covers one small behavior
2. **One Test at a Time**: Don't write multiple tests before implementing
3. **Commit Often**: Small, focused commits
4. **Keep Tests Green**: Never commit with failing tests
5. **Refactor Continuously**: Improve structure throughout

## Next Steps

After completing a full cycle:
1. Review progress
2. Identify next smallest increment
3. Start new RED-GREEN-REFACTOR cycle
4. Repeat until feature complete

**Remember**: TDD is a discipline - follow the cycle strictly for best results.
