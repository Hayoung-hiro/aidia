# AIDIA

AIDIA compares DIA isolation-window strategies under a shared acquisition setup.
Scientific background and existing domain decisions are in [docs/domain-knowledge.md](docs/domain-knowledge.md).

## Language

**Strategy comparison**:
A comparison of isolation-window strategies using the same input precursors and common acquisition conditions, with each strategy's own user-selected settings captured when optimization is run.
_Avoid_: Default-strategy comparison

**Completed optimization settings**:
The common acquisition conditions and all strategy-specific settings selected when optimization was run. Later changes to setup controls do not change these settings.
_Avoid_: Current screen settings

**Precursor accounting**:
The number of input precursor observations within each final RT and m/z window, and the fraction covered by at least one window. Overlapping windows may each count an observation, while overall coverage counts each observation once.
Explicit RT-bin assignments take precedence for adaptive and merged bins; without assignments, RT intervals are half-open with an inclusive final edge.

**Method delivery**:
Writing a completed isolation-window result in selected instrument formats, individually or together in a directory or ZIP. Void filling and acquisition bounds are export choices; the result's strategy and instrument identify the completed optimization.
