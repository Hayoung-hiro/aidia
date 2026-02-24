# TDD Custom Commands for Claude Code

Custom commands implementing Kent Beck's Test-Driven Development (TDD) and Tidy First principles.

## Available Commands

### 🔴 `/tdd-red` - Write Failing Test
Start the TDD cycle by writing a failing test that describes expected behavior.
- Focus on ONE small increment
- Use meaningful test names
- Confirm test fails for the right reason

### 🟢 `/tdd-green` - Make Test Pass
Implement the minimum code needed to make the failing test pass.
- Simplest solution possible
- No extra features
- Get to green quickly

### 🔵 `/tdd-refactor` - Improve Structure
Improve code quality while keeping all tests passing.
- Eliminate duplication
- Improve naming
- One change at a time

### 🔄 `/tdd-cycle` - Complete TDD Workflow
Full Red-Green-Refactor cycle with examples and best practices.
- Complete workflow guide
- Commit strategy
- Real-world examples

### 🎯 `/tdd-start` - Plan Test-First Approach
Begin a new feature with TDD methodology.
- Break down requirements
- Create test list
- Design API first

### 🐛 `/tdd-fix` - Fix Bugs Test-First
Test-driven defect resolution workflow.
- API-level test (reproduces bug)
- Unit-level test (isolates cause)
- Minimal fix
- Prevents regression

### 🧹 `/tidy-first` - Separate Structure from Behavior
Kent Beck's principle: structural changes before behavioral changes.
- Structural vs behavioral changes
- Commit discipline
- Workflow examples

## Quick Start

### For a New Feature:
```bash
1. /tdd-start    # Plan your approach
2. /tdd-red      # Write first failing test
3. /tdd-green    # Make it pass
4. /tdd-refactor # Clean up
5. Repeat steps 2-4 for each increment
```

### For a Bug Fix:
```bash
1. /tdd-fix      # Follow bug fix workflow
   - Write API-level test
   - Write unit-level test
   - Fix
   - Refactor
```

### For Refactoring:
```bash
1. /tidy-first   # Learn structural vs behavioral
2. Make structural changes (keep tests green)
3. Commit structural changes
4. Make behavioral changes
5. Commit behavioral changes
```

## TDD Principles

1. **Red-Green-Refactor**: The fundamental cycle
2. **Small Steps**: One test at a time
3. **Simplest Solution**: Make it work first
4. **Continuous Refactoring**: Keep code clean
5. **Commit Discipline**: Only commit when green

## Based On

- Kent Beck's "Test-Driven Development: By Example"
- Kent Beck's "Tidy First?: A Personal Exercise in Empirical Software Design"
- Kent Beck's TDD and Tidy First principles

## Integration with Project

These commands are designed for the DIA Window Optimizer project:
- R language conventions
- testthat testing framework
- dplyr/tidyverse style
- Scientific computing context

## Examples in Commands

Each command includes:
- ✅ Clear guidelines
- ✅ R code examples
- ✅ Checklist for completion
- ✅ Real project scenarios
- ✅ Common pitfalls to avoid

---

**Remember**: TDD is a discipline. Follow the cycle strictly for best results.
