---
description: "TDD Red Phase: Write a failing test"
---

# TDD Red Phase: Write a Failing Test

You are following Kent Beck's Test-Driven Development (TDD) methodology.

## Current Phase: RED (Write Failing Test)

### Your Task:
1. **Write ONE failing test** that defines the next small increment of functionality
2. The test should be:
   - Simple and focused on one behavior
   - Have a meaningful name describing the expected behavior
   - Produce a clear, informative failure message
   - Test the smallest possible unit of functionality

### Test Naming Convention:
- Use descriptive names: `test_<behavior>_<expected_outcome>`
- Example: `test_aggregate_replicates_returns_median_values()`
- Example: `test_consensus_dataset_filters_high_cv_precursors()`

### Guidelines:
- Write ONLY the test - do NOT implement the production code yet
- The test should fail because the functionality doesn't exist
- Make the test as simple as possible while still being meaningful
- Focus on API design - what would be the easiest interface to use?

### R Testing Convention:
```r
test_that("<descriptive test name>", {
  # Arrange: Set up test data
  input_data <- create_test_data()

  # Act: Call the function
  result <- function_to_test(input_data)

  # Assert: Verify expected behavior
  expect_equal(result$output, expected_value)
  expect_true(result$property)
})
```

### After Writing the Test:
1. Run the test to confirm it fails
2. Verify the failure message is clear
3. Do NOT proceed to implementation yet - wait for confirmation

**Remember**: The test should fail for the RIGHT reason (missing functionality), not because of typos or syntax errors.
