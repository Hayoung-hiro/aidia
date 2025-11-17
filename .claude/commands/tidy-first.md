---
description: "Tidy First: Separate structural changes from behavioral changes"
---

# Tidy First: Structural Changes Before Behavioral Changes

You are following Kent Beck's "Tidy First" philosophy.

## Principle: Separate Structure from Behavior

### Core Rule:
**NEVER mix structural and behavioral changes in the same commit**

### Two Types of Changes:

#### 1. STRUCTURAL CHANGES (Tidy First)
Changes that rearrange code WITHOUT changing behavior:
- Renaming variables, functions, classes
- Extracting methods or functions
- Moving code to different files
- Reorganizing code structure
- Removing dead code
- Improving comments and documentation
- Formatting and style improvements

**Validation**: ALL tests must pass before AND after

#### 2. BEHAVIORAL CHANGES (After Tidying)
Changes that modify actual functionality:
- Adding new features
- Fixing bugs
- Changing algorithms
- Modifying business logic
- Adding/removing functionality

**Validation**: May require new tests or modify existing tests

### Workflow:

```
Before making behavioral changes:
1. Identify needed structural improvements
2. Make structural changes (Tidy First)
3. Run tests to verify no behavior changed
4. Commit: "refactor: <structural change description>"
5. Then make behavioral changes
6. Write/update tests for new behavior
7. Commit: "feat: <behavioral change description>"
```

### Example Workflow:

**Scenario**: Add replicate handling to Stage 1

**Step 1 - Tidy First** (Structural):
```r
# Structural changes BEFORE adding new feature
# 1. Extract helper function for clarity
validate_column_exists <- function(data, column_name) {
  if (!column_name %in% names(data)) {
    stop(sprintf("Required column '%s' not found", column_name))
  }
}

# 2. Rename for clarity
create_validated_dataset <- function(...)  # was: validate_data()

# Commit: "refactor: extract validation helper and improve naming"
```

**Step 2 - Behavioral Change**:
```r
# NOW add new feature
create_validated_dataset <- function(
  proteome_file,
  replicate_handling = "consensus"  # NEW parameter
) {
  # ... existing code ...

  # NEW behavior
  if (n_runs > 1) {
    data <- handle_replicates(data, replicate_handling)
  }

  # ... rest of code ...
}

# Commit: "feat: add replicate handling to Stage 1 validation"
```

### Benefits:
- Easier code review (structure vs behavior separated)
- Safer refactoring (behavior validated unchanged)
- Clearer git history
- Easier to revert if needed
- Better understanding of changes

### Commit Message Format:
```
# Structural changes
refactor: extract consensus_dataset helper function
refactor: rename variables for clarity in stage1
refactor: reorganize helper functions into utils

# Behavioral changes
feat: add geometric CV calculation for replicates
fix: handle missing FWHM values in DPPP calculation
feat: implement median-based consensus aggregation
```

**Remember**: Always tidy FIRST, then add behavior. Keep them separate.
