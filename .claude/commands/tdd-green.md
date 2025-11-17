---
description: "TDD Green Phase: Make the test pass with minimal code"
---

# TDD Green Phase: Make the Test Pass

You are following Kent Beck's Test-Driven Development (TDD) methodology.

## Current Phase: GREEN (Make Test Pass)

### Your Task:
1. **Implement the MINIMUM code needed** to make the failing test pass
2. Focus on making it work, not making it perfect
3. Use the simplest solution that could possibly work

### Guidelines:
- Write ONLY enough code to make the current test pass
- Do NOT add extra features or handle cases not covered by the test
- Do NOT refactor yet - that comes in the next phase
- Hardcoding values is acceptable if it makes the test pass
- Focus on getting to green as quickly as possible

### Implementation Approach:
1. Read the failing test to understand what's required
2. Implement the minimal solution
3. Run the test to verify it passes
4. If test fails, make minimal adjustments
5. Once green, STOP - do not add more code

### R Implementation Pattern:
```r
# Minimal implementation example
function_name <- function(input) {
  # Only implement what the test requires
  # No extra logic, no edge cases not covered by tests

  result <- process_input(input)  # Simplest possible approach

  return(result)
}
```

### After Implementation:
1. Run the test to confirm it passes (GREEN)
2. Run ALL tests to ensure nothing broke
3. If all tests pass, you're ready for the Refactor phase
4. Do NOT refactor yet - confirm green status first

**Remember**: "Make it work, make it right, make it fast" - in that order. We're at "make it work".
