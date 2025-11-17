---
description: "Start TDD for a new feature: plan test-first approach"
---

# Start TDD: Plan Your Test-First Approach

You are following Kent Beck's Test-Driven Development (TDD) methodology.

## Starting a New Feature with TDD

### Before Writing Any Code:

1. **Understand the Requirement**
   - What is the user story or feature request?
   - What is the expected behavior?
   - What are the acceptance criteria?

2. **Break Down into Small Increments**
   - Identify the SMALLEST testable behavior
   - List the sequence of behaviors to implement
   - Plan 3-5 iterations to reach the complete feature

3. **Design the API First**
   - What would be the ideal function signature?
   - What would make this easy to use?
   - What would make this easy to test?

### Test List Template

Create a test list for your feature:

```markdown
## Feature: <Feature Name>

### Goal:
<Brief description of what we're building>

### Test Sequence:
1. [ ] Test: <first simplest behavior>
2. [ ] Test: <second behavior>
3. [ ] Test: <third behavior>
4. [ ] Test: <edge case 1>
5. [ ] Test: <edge case 2>

### API Design:
```r
# Proposed function signature
function_name <- function(
  required_param,
  optional_param = default_value
) {
  # Returns: <description>
}
```

### Implementation Notes:
- Dependencies: <list required functions/libraries>
- Data structures: <what objects are involved>
- Integration points: <how this fits into existing code>
```

### Example: Replicate Handling Feature

```markdown
## Feature: Technical Replicate Consensus Dataset

### Goal:
Create consensus dataset from technical replicates using median aggregation

### Test Sequence:
1. [ ] Returns median RT for single precursor with 3 replicates
2. [ ] Returns median FWHM for single precursor with 3 replicates
3. [ ] Returns median m/z for single precursor with 3 replicates
4. [ ] Handles multiple precursors correctly
5. [ ] Calculates CV% for each metric
6. [ ] Filters precursors with CV > threshold
7. [ ] Returns QC report with metrics
8. [ ] Handles missing values (NA) gracefully
9. [ ] Works with single replicate (no aggregation needed)
10. [ ] Works with 2+ replicates

### API Design:
```r
create_consensus_dataset <- function(
  data,                    # Raw replicate data
  min_replicates = 2,      # Minimum replicates required
  max_cv_percent = 20,     # Maximum CV% for QC filtering
  use_median = TRUE        # Use median (vs mean)
) {
  # Returns: list(
  #   data = consensus_data_tibble,
  #   qc_report = list(metrics, filters, stats)
  # )
}
```

### Implementation Notes:
- Dependencies: dplyr, tidyr
- Data structures: ValidatedData from Stage 1
- Integration: Called from create_validated_dataset()
- Helper functions needed: calculate_geometric_cv()
```

### Next Steps

After creating your test list:

1. **Start with Test #1**: Use `/tdd-red` command
2. **Work through sequence**: One test at a time
3. **Update test list**: Check off completed tests
4. **Refactor as needed**: Keep code clean throughout
5. **Review progress**: After every 2-3 tests

### Starting the First Test

When ready to begin:
```bash
# Command to start first test
/tdd-red
```

Then work through RED → GREEN → REFACTOR cycle for each test in sequence.

### Tips for Success

- **Start Simple**: First test should be trivially simple
- **Build Gradually**: Each test adds one small behavior
- **Don't Skip Ahead**: Resist urge to implement everything at once
- **Trust the Process**: TDD works through small, disciplined steps
- **Commit Often**: After each green refactor cycle

**Remember**: The test list is a guide, not a contract. Adjust as you learn.
