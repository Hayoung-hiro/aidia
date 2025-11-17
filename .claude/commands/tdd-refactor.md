---
description: "TDD Refactor Phase: Improve code structure while keeping tests green"
---

# TDD Refactor Phase: Improve Structure

You are following Kent Beck's Test-Driven Development (TDD) methodology.

## Current Phase: REFACTOR (Improve Structure)

### Your Task:
1. **Improve code structure** without changing behavior
2. Keep ALL tests passing throughout
3. Follow the "Tidy First" principle - structural changes only

### Refactoring Checklist:
- [ ] Eliminate duplication (DRY principle)
- [ ] Improve naming for clarity
- [ ] Extract methods for better organization
- [ ] Simplify complex conditionals
- [ ] Remove dead code
- [ ] Make dependencies explicit

### Common Refactoring Patterns:
1. **Extract Function**: Pull out repeated code blocks
2. **Rename**: Use more descriptive names
3. **Extract Variable**: Name complex expressions
4. **Inline**: Remove unnecessary indirection
5. **Move**: Organize code by responsibility

### R Refactoring Examples:
```r
# Before: Duplication
calculate_cv_fwhm <- sd(fwhm) / mean(fwhm) * 100
calculate_cv_rt <- sd(rt) / mean(rt) * 100

# After: Extract Function
calculate_cv <- function(values) {
  sd(values) / mean(values) * 100
}
calculate_cv_fwhm <- calculate_cv(fwhm)
calculate_cv_rt <- calculate_cv(rt)

# Before: Unclear naming
res <- process_data(d, 2, 0.05)

# After: Clear naming
consensus_data <- create_consensus_dataset(
  raw_data,
  min_replicates = 2,
  max_cv_percent = 0.05
)
```

### Refactoring Protocol:
1. Run ALL tests before refactoring (confirm GREEN)
2. Make ONE refactoring change at a time
3. Run ALL tests after each change
4. If tests fail, revert and try a different approach
5. Commit each successful refactoring separately

### After Refactoring:
1. Confirm ALL tests still pass (stay GREEN)
2. Review code for further improvements
3. Commit with message: "refactor: <description of structural change>"
4. Ready for next Red-Green-Refactor cycle

**Remember**: Never change behavior during refactoring. Tests must stay green throughout.
