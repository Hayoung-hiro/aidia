# Result-driven input only — no raw / method file ingestion

AIDIA's input contract is **DIA-NN `report.parquet` (required) + `*.stats.tsv` (optional)**.
Vendor raw files (Thermo `.raw`, Bruker `.d`, SCIEX `.wiff`) and method files
(`.meth`, `.xml`) are explicitly out of scope. This was reconsidered in the
v0.4.x acquisition-capacity-KPI design and reaffirmed.

The proposal under review was to accept raw / method files so AIDIA could
(a) measure *actual* acquired MS2 scan count instead of estimating from
gradient × cycle rate, (b) auto-populate instrument parameters (resolution,
IT, AGC, current isolation scheme) from file headers, and (c) compute a true
*detect rate* (MS1 features → IDs) separable from search-FDR ID rate. All
three are real gains, but we declined them because:

- `rawrr` (the only viable R-side Thermo `.raw` reader) requires Windows
  .NET / mono. This breaks cross-platform CI and Bioconductor portability,
  which AIDIA currently respects.
- Bruker and SCIEX have no comparable R-native readers — adopting raw input
  would either lock AIDIA to Thermo or require vendor-specific code paths.
- Typical raw files are 1–10 GB; Shiny upload of even one file is
  impractical (browser timeouts, server memory). Header-only reads via
  `rawrr::readFileHeader` mitigate compute cost but not file-size cost.
- Adopting raw input changes AIDIA's identity from "DIA-NN result-driven
  optimizer" to a general MS-data tool. That is a larger product decision
  that should not be smuggled in through a KPI feature.
- The user's stated intent — "did I use the instrument well?" — is fully
  satisfied by four capacity KPIs derived from existing fields
  (filled-window ratio, DPPP headroom, cycle-time headroom, window-count
  headroom). Raw input would add precision but not change the answer.

Users who need true acquired-scan counts, AGC underfilling diagnosis, or
auto-extracted instrument parameters should use a separate tool upstream of
AIDIA and feed the resulting DIA-NN output here.

## Rejected alternative — Thermo `.raw` header-only ingestion via `rawrr`

The lightest viable raw-input form was `rawrr::readFileHeader()` (scan
metadata only, no spectra), exposed as `Suggests`. We rejected it because
the cross-platform breakage and the precedent of "AIDIA reads raw files"
together outweigh the partial gain — header reads still need the user to
upload a multi-GB file to Shiny, and the vendor scope problem is unsolved.

## Rejected alternative — Thermo method file (`.meth` / `.xml`) ingestion

Method files are small (tens of KB) and would give instrument parameters
and the current isolation scheme but not scan count. We rejected this for
the same identity-change reason: even small Thermo-only ingestion would
establish that AIDIA accepts vendor files, opening pressure to support
Bruker and SCIEX equivalents.

## Consequences

- The "filled-window ratio" KPI is computed from
  `evaluate_windows()$quality_flags$empty_windows`, which is window-level,
  not true scan-level. It approximates detect rate but is not identical.
- The total scan-slot count used in any future composite metric is an
  *estimate* (`gradient_length_s × actual_scan_rate_hz`) derived from the
  AIDIA-produced method, not a measurement.
- Instrument parameters (resolution, IT, gradient length, etc.) remain
  user-entered. UX cost of manual entry is accepted.
- Revisit when there is concrete user demand for detect-vs-ID separation
  or AGC underfilling diagnosis. A second ADR would supersede this one.
