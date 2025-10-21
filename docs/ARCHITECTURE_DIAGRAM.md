# DIA Window Optimizer - Architecture Diagrams

Complete architecture diagrams showing function and object relationships for Phase 1-3.

## Overview: 4-Stage Pipeline Flow

```mermaid
flowchart TB
    subgraph Input[Input Data]
        A1[DIA-NN Output<br/>Parquet/TSV/CSV]
        A2[Raw Files Optional]
    end

    subgraph Stage1[Stage 1: Data Validation]
        S1[validate_diann_data]
    end

    subgraph Stage2[Stage 2: DPPP Diagnosis]
        S2[diagnose_dppp_status]
    end

    subgraph Stage3[Stage 3: Window Optimization]
        S3A[determine_window_count]
        S3B[segment_rt_bins]
        S3C[optimize_mz_ranges]
        S3D[generate_isolation_windows]
    end

    subgraph Stage4[Stage 4: Visualization]
        S4[generate_visualizations]
    end

    subgraph Output[Output Files]
        O1[PDF Report]
        O2[Method File CSV]
        O3[Individual Plots]
    end

    A1 --> S1
    A2 -.-> S1
    S1 -->|ValidatedData| S2
    S2 -->|DiagnosisResult| S3A
    S3A -->|WindowCountResult| S3B
    S3B -->|RTBinningResult| S3C
    S3C -->|MzRangeResult| S3D
    S3D -->|WindowGenerationResult| S4
    S4 --> O1
    S4 --> O2
    S4 --> O3

    style Stage1 fill:#e1f5e1
    style Stage2 fill:#e1f0ff
    style Stage3 fill:#fff4e1
    style Stage4 fill:#ffe1f0
```

---

## Stage 1: Data Validation

### Function Dependencies

```mermaid
flowchart TB
    subgraph Main[Main Function]
        V1[validate_diann_data]
    end

    subgraph Helpers[Helper Functions]
        H1[detect_file_format]
        H2[load_parquet_data]
        H3[load_csv_data]
        H4[detect_diann_columns]
        H5[validate_required_columns]
        H6[validate_data_quality]
        H7[calculate_basic_statistics]
    end

    V1 --> H1
    H1 -->|parquet| H2
    H1 -->|csv/tsv| H3
    H2 --> H4
    H3 --> H4
    H4 --> H5
    H5 --> H6
    H6 --> H7

    style V1 fill:#90EE90
```

### Data Object Flow

```mermaid
flowchart LR
    subgraph Input[Input]
        I1[File Path]
        I2[Raw DataFrame]
    end

    subgraph Processing[Processing]
        P1[Column Detection]
        P2[Quality Validation]
        P3[Statistics Calculation]
    end

    subgraph Output[ValidatedData Object]
        O1[data: tibble]
        O2[metadata: list]
        O3[validation_status: list]
    end

    I1 --> P1
    I2 --> P1
    P1 --> P2
    P2 --> P3
    P3 --> O1
    P3 --> O2
    P3 --> O3

    O1 -.->|contains| D1[RT.Start]
    O1 -.->|contains| D2[Precursor.Mz]
    O1 -.->|contains| D3[FWHM]

    style Output fill:#e1f5e1
```

### ValidatedData S3 Object Structure

```mermaid
classDiagram
    class ValidatedData {
        +tibble data
        +list metadata
        +list validation_status
    }

    class data {
        +numeric RT.Start
        +numeric Precursor.Mz
        +numeric FWHM
        +other_columns
    }

    class metadata {
        +integer n_precursors
        +numeric[2] rt_range
        +numeric[2] mz_range
        +list fwhm_stats
        +POSIXct validation_timestamp
    }

    class validation_status {
        +logical all_passed
        +numeric quality_score
        +character[] warnings
        +character[] errors
    }

    ValidatedData *-- data
    ValidatedData *-- metadata
    ValidatedData *-- validation_status
```

---

## Stage 2: DPPP Diagnosis

### Function Dependencies

```mermaid
flowchart TB
    subgraph Main[Main Function]
        D1[diagnose_dppp_status]
    end

    subgraph Analysis[Analysis Functions]
        A1[calculate_dppp_distribution]
        A2[calculate_satisfaction_ratio]
        A3[analyze_cycle_time]
        A4[recommend_scan_time]
    end

    subgraph Utilities[Utility Functions]
        U1[get_instrument_config]
        U2[validate_cycle_time_feasibility]
        U3[calculate_dppp_tolerance_bounds]
    end

    D1 --> A1
    D1 --> A2
    D1 --> A3
    D1 --> A4
    A3 --> U1
    A4 --> U2
    A2 --> U3

    style D1 fill:#87CEEB
```

### Data Object Flow

```mermaid
flowchart LR
    subgraph Input[Input]
        I1[ValidatedData]
        I2[target_dppp: 7.0]
        I3[dppp_tolerance: 0.5]
    end

    subgraph Processing[Processing]
        P1[Calculate Current DPPP]
        P2[Analyze Satisfaction]
        P3[Recommend Scan Time]
    end

    subgraph Output[DiagnosisResult Object]
        O1[current_state]
        O2[recommendation]
        O3[instrument_constraints]
    end

    I1 --> P1
    I2 --> P1
    I3 --> P2
    P1 --> P2
    P2 --> P3
    P3 --> O1
    P3 --> O2
    P3 --> O3

    style Output fill:#e1f0ff
```

### DiagnosisResult S3 Object Structure

```mermaid
classDiagram
    class DiagnosisResult {
        +list current_state
        +list recommendation
        +list instrument_constraints
        +list metadata
    }

    class current_state {
        +numeric[] dppp_distribution
        +list dppp_stats
        +numeric satisfaction_ratio
        +numeric current_cycle_time_sec
    }

    class recommendation {
        +numeric optimal_scan_time_ms
        +numeric required_cycle_time_sec
        +integer expected_window_count
        +character scan_time_rationale
    }

    class instrument_constraints {
        +character instrument_type
        +numeric max_scan_rate_hz
        +numeric min_cycle_time_sec
        +logical is_feasible
    }

    DiagnosisResult *-- current_state
    DiagnosisResult *-- recommendation
    DiagnosisResult *-- instrument_constraints
```

---

## Stage 3A: Window Count Determination

### Function Dependencies

```mermaid
flowchart TB
    subgraph Main[Main Function]
        W1[determine_window_count]
    end

    subgraph Config[Instrument Config]
        C1[get_instrument_preset]
        C2[load_instrument_config]
    end

    subgraph Calculation[Calculation Functions]
        CA1[calculate_cycle_time]
        CA2[calculate_max_windows]
        CA3[validate_window_count_feasibility]
    end

    subgraph Integration[Raw Metadata Integration]
        I1[has_raw_metadata]
        I2[adjust_for_actual_injection_time]
    end

    W1 --> C1
    C1 --> C2
    W1 --> CA1
    CA1 --> CA2
    CA2 --> CA3
    W1 -.->|optional| I1
    I1 -.->|if available| I2

    style W1 fill:#FFD700
```

### Data Object Flow

```mermaid
flowchart LR
    subgraph Input[Input]
        I1[DiagnosisResult]
        I2[target_cycle_time_sec]
        I3[instrument_preset]
    end

    subgraph Processing[Processing]
        P1[Get Instrument Config]
        P2[Calculate Cycle Time]
        P3[Determine Max Windows]
        P4[Feasibility Check]
    end

    subgraph Output[WindowCountResult Object]
        O1[window_count]
        O2[cycle_time_analysis]
        O3[instrument_config]
    end

    I1 --> P1
    I2 --> P2
    I3 --> P1
    P1 --> P2
    P2 --> P3
    P3 --> P4
    P4 --> O1
    P4 --> O2
    P4 --> O3

    style Output fill:#fff4e1
```

### WindowCountResult S3 Object Structure

```mermaid
classDiagram
    class WindowCountResult {
        +integer window_count
        +list cycle_time_analysis
        +list instrument_config
        +list metadata
    }

    class cycle_time_analysis {
        +numeric calculated_cycle_time_sec
        +numeric target_cycle_time_sec
        +logical is_achievable
        +character feasibility_notes
    }

    class instrument_config {
        +character name
        +numeric ms1_time_sec
        +numeric ms2_time_sec
        +numeric max_scan_rate_hz
        +character acquisition_mode
    }

    WindowCountResult *-- cycle_time_analysis
    WindowCountResult *-- instrument_config
```

---

## Stage 3B: RT Binning

### Function Dependencies

```mermaid
flowchart TB
    subgraph Main[Main Function]
        R1[segment_rt_bins]
    end

    subgraph Core[Core Segmentation]
        C1[segment_rt_by_time_unit]
        C2[segment_rt_by_time_breaks]
    end

    subgraph Analysis[Analysis Functions]
        A1[calculate_rt_group_stats]
        A2[validate_rt_segments]
    end

    R1 -->|method: time_unit| C1
    R1 -->|method: time_breaks| C2
    C1 --> A1
    C2 --> A1
    A1 --> A2

    style R1 fill:#FFA500
```

### Data Object Flow

```mermaid
flowchart LR
    subgraph Input[Input]
        I1[ValidatedData]
        I2[method: time_unit]
        I3[rt_bin_width_min]
    end

    subgraph Processing[Processing]
        P1[Segment by Time]
        P2[Assign RT Groups]
        P3[Calculate Stats]
    end

    subgraph Output[RTBinningResult Object]
        O1[data: ValidatedData]
        O2[rt_group_stats]
        O3[parameters]
    end

    I1 --> P1
    I2 --> P1
    I3 --> P1
    P1 --> P2
    P2 --> P3
    P3 --> O1
    P3 --> O2
    P3 --> O3

    style Output fill:#fff4e1
```

### RTBinningResult S3 Object Structure

```mermaid
classDiagram
    class RTBinningResult {
        +ValidatedData data
        +tibble rt_group_stats
        +list parameters
    }

    class rt_group_stats {
        +integer rt_group
        +numeric rt_start
        +numeric rt_end
        +integer n_precursors
    }

    class parameters {
        +character segmentation_method
        +numeric rt_bin_width_min
        +integer n_bins
        +numeric[] rt_range
    }

    RTBinningResult *-- rt_group_stats
    RTBinningResult *-- parameters
```

---

## Stage 3C: m/z Range Optimization

### Function Dependencies

```mermaid
flowchart TB
    subgraph Main[Main Function]
        M1[optimize_mz_ranges]
    end

    subgraph Strategies[4 Optimization Strategies]
        S1[optimize_mz_quantile]
        S2[optimize_mz_smoothing]
        S3[optimize_mz_outlier]
        S4[optimize_mz_coverage]
    end

    subgraph Smoothing[DynamicDIA Smoothing]
        SM1[compute_smooth_mz_boundaries]
        SM2[savitzky_golay_smoothing]
        SM3[moving_average_smoothing]
        SM4[gaussian_smoothing]
    end

    subgraph Analysis[Analysis Functions]
        A1[calculate_coverage_ratio]
        A2[compare_strategies]
        A3[validate_mz_ranges]
    end

    M1 -->|strategy: quantile| S1
    M1 -->|strategy: smoothing| S2
    M1 -->|strategy: outlier| S3
    M1 -->|strategy: coverage| S4

    S2 --> SM1
    SM1 -->|method: savgol| SM2
    SM1 -->|method: ma| SM3
    SM1 -->|method: gaussian| SM4

    S1 --> A1
    S2 --> A1
    S3 --> A1
    S4 --> A1
    A1 --> A2
    A2 --> A3

    style M1 fill:#FF6347
    style S2 fill:#90EE90
```

### Data Object Flow

```mermaid
flowchart LR
    subgraph Input[Input]
        I1[RTBinningResult]
        I2[strategy: smoothing]
        I3[target_coverage: 0.95]
    end

    subgraph Processing[Processing]
        P1[Apply Strategy]
        P2[Calculate Coverage]
        P3[Validate Ranges]
    end

    subgraph Output[MzRangeResult Object]
        O1[mz_ranges]
        O2[strategy_comparison]
        O3[smoothing_data]
        O4[optimization_stats]
    end

    I1 --> P1
    I2 --> P1
    I3 --> P2
    P1 --> P2
    P2 --> P3
    P3 --> O1
    P3 --> O2
    P3 --> O3
    P3 --> O4

    style Output fill:#fff4e1
```

### MzRangeResult S3 Object Structure

```mermaid
classDiagram
    class MzRangeResult {
        +tibble mz_ranges
        +list strategy_comparison
        +list smoothing_data
        +list optimization_stats
        +list metadata
        +RTBinningResult rt_binning_result
    }

    class mz_ranges {
        +integer rt_segment_id
        +numeric rt_start
        +numeric rt_end
        +numeric mz_min
        +numeric mz_max
        +numeric mz_range_width
        +integer n_precursors_covered
        +numeric coverage_ratio
    }

    class smoothing_data {
        +tibble continuous_boundaries
        +character smoothing_method
        +list smoothing_params
    }

    class optimization_stats {
        +integer n_segments
        +integer total_precursors
        +numeric overall_coverage_ratio
        +numeric mz_range_reduction_mean
    }

    MzRangeResult *-- mz_ranges
    MzRangeResult *-- smoothing_data
    MzRangeResult *-- optimization_stats
```

---

## Stage 3D: Window Generation

### Function Dependencies

```mermaid
flowchart TB
    subgraph Main[Main Function]
        G1[generate_isolation_windows]
    end

    subgraph Modes[3 Window Generation Modes]
        M1[generate_fixed_windows]
        M2[generate_variable_windows]
        M3[generate_overlapped_windows]
    end

    subgraph Variable[Variable Mode Components]
        V1[calculate_density_per_segment]
        V2[allocate_windows_by_density]
        V3[apply_largest_remainder_method]
        V4[generate_windows_from_boundaries]
    end

    subgraph Analysis[Analysis Functions]
        A1[calculate_window_statistics]
        A2[analyze_coverage]
        A3[validate_windows]
    end

    subgraph Export[Export Functions]
        E1[export_windows_to_csv]
    end

    G1 -->|mode: fixed| M1
    G1 -->|mode: variable| M2
    G1 -->|mode: overlapped| M3

    M2 --> V1
    V1 --> V2
    V2 --> V3
    V3 --> V4

    M1 --> A1
    M2 --> A1
    M3 --> A1
    A1 --> A2
    A2 --> A3

    G1 -.->|optional| E1

    style G1 fill:#FF1493
    style M2 fill:#90EE90
```

### Data Object Flow

```mermaid
flowchart LR
    subgraph Input[Input]
        I1[WindowCountResult]
        I2[MzRangeResult]
        I3[mode: variable]
    end

    subgraph Processing[Processing]
        P1[Allocate Windows]
        P2[Generate Windows]
        P3[Calculate Statistics]
        P4[Analyze Coverage]
    end

    subgraph Output[WindowGenerationResult]
        O1[windows]
        O2[statistics]
        O3[coverage_analysis]
        O4[metadata]
    end

    I1 --> P1
    I2 --> P1
    I3 --> P2
    P1 --> P2
    P2 --> P3
    P3 --> P4
    P4 --> O1
    P4 --> O2
    P4 --> O3
    P4 --> O4

    style Output fill:#fff4e1
```

### WindowGenerationResult S3 Object Structure

```mermaid
classDiagram
    class WindowGenerationResult {
        +tibble windows
        +list statistics
        +list coverage_analysis
        +list metadata
        +list input_results
    }

    class windows {
        +integer window_id
        +integer rt_segment_id
        +numeric mz_start
        +numeric mz_end
        +numeric mz_center
        +numeric window_width
        +integer n_precursors
    }

    class statistics {
        +integer total_windows
        +numeric mean_precursors_per_window
        +numeric cv_precursors
        +numeric mean_window_width
        +numeric overall_coverage_ratio
    }

    class coverage_analysis {
        +numeric coverage_ratio
        +tibble uncovered_regions
        +integer n_uncovered_precursors
    }

    WindowGenerationResult *-- windows
    WindowGenerationResult *-- statistics
    WindowGenerationResult *-- coverage_analysis
```

---

## Complete Data Flow: Stage 1 to Stage 3D

```mermaid
flowchart TB
    subgraph S1[Stage 1: Validation]
        V[validate_diann_data]
        VD[ValidatedData<br/>16,273 precursors]
    end

    subgraph S2[Stage 2: Diagnosis]
        D[diagnose_dppp_status]
        DD[DiagnosisResult<br/>DPPP 714, 100% satisfaction<br/>Recommended: 15ms scan]
    end

    subgraph S3A[Stage 3A: Window Count]
        WC[determine_window_count]
        WCD[WindowCountResult<br/>209 windows/RT bin<br/>Astral: 0.627s cycle]
    end

    subgraph S3B[Stage 3B: RT Binning]
        RT[segment_rt_bins]
        RTD[RTBinningResult<br/>22 RT segments<br/>5-min bins]
    end

    subgraph S3C[Stage 3C: m/z Range]
        MZ[optimize_mz_ranges]
        MZD[MzRangeResult<br/>Smoothing strategy<br/>89.5% coverage]
    end

    subgraph S3D[Stage 3D: Window Gen]
        WG[generate_isolation_windows]
        WGD[WindowGenerationResult<br/>4,389 total windows<br/>Variable mode]
    end

    V --> VD
    VD --> D
    D --> DD
    DD --> WC
    WC --> WCD
    WCD --> RT
    VD --> RT
    RT --> RTD
    RTD --> MZ
    MZ --> MZD
    MZD --> WG
    WCD --> WG
    WG --> WGD

    style VD fill:#e1f5e1
    style DD fill:#e1f0ff
    style WCD fill:#fff4e1
    style RTD fill:#fff4e1
    style MZD fill:#fff4e1
    style WGD fill:#fff4e1
```

---

## Integration Points Summary

### Key Function Calls

```mermaid
sequenceDiagram
    participant User
    participant S1 as Stage 1
    participant S2 as Stage 2
    participant S3A as Stage 3A
    participant S3B as Stage 3B
    participant S3C as Stage 3C
    participant S3D as Stage 3D

    User->>S1: validate_diann_data(file_path)
    S1-->>User: ValidatedData

    User->>S2: diagnose_dppp_status(validated_data)
    S2-->>User: DiagnosisResult

    User->>S3A: determine_window_count(diagnosis)
    S3A-->>User: WindowCountResult

    User->>S3B: segment_rt_bins(validated_data)
    S3B-->>User: RTBinningResult

    User->>S3C: optimize_mz_ranges(rt_binning)
    S3C-->>User: MzRangeResult

    User->>S3D: generate_isolation_windows(window_count, mz_range)
    S3D-->>User: WindowGenerationResult
```

### Object Dependency Graph

```mermaid
graph TB
    VD[ValidatedData]
    DR[DiagnosisResult]
    WCR[WindowCountResult]
    RTR[RTBinningResult]
    MZR[MzRangeResult]
    WGR[WindowGenerationResult]

    VD -->|required by| DR
    DR -->|required by| WCR
    VD -->|required by| RTR
    RTR -->|required by| MZR
    WCR -->|required by| WGR
    MZR -->|required by| WGR

    VD -.->|stored in| RTR
    RTR -.->|stored in| MZR
    WCR -.->|stored in| WGR
    MZR -.->|stored in| WGR

    style VD fill:#e1f5e1
    style DR fill:#e1f0ff
    style WCR fill:#fff4e1
    style RTR fill:#fff4e1
    style MZR fill:#fff4e1
    style WGR fill:#fff4e1
```

---

## File Organization

```mermaid
graph TB
    subgraph R[R Directory]
        S1F[stage1_data_validation.R]
        S2F[stage2_dppp_diagnosis.R]

        subgraph S3[stage3_window_optimization]
            S3AF[module3a_window_count.R]
            S3BF[module3b_rt_binning.R]
            S3CF[module3c_mz_range_optimization.R]
            S3DF[module3d_window_generation.R]
        end

        S4F[stage4_visualization.R]

        subgraph Config[config]
            CF[instruments.R]
        end
    end

    subgraph Tests[tests]
        T1[test_stage1.R]
        T2[test_stage2.R]
        T3[test_stage3a.R]
        TF[test_final_workflow.R]
    end

    S1F -.->|tested by| T1
    S2F -.->|tested by| T2
    S3AF -.->|tested by| T3
    S1F -.->|uses| CF
    S2F -.->|uses| CF
    S3AF -.->|uses| CF

    style S1F fill:#e1f5e1
    style S2F fill:#e1f0ff
    style S3AF fill:#fff4e1
    style S3BF fill:#fff4e1
    style S3CF fill:#fff4e1
    style S3DF fill:#fff4e1
    style S4F fill:#ffe1f0
```

---

## Summary

This document provides comprehensive architecture diagrams for the DIA Window Optimizer pipeline (Phase 1-3). Each stage has:

1. **Function dependency graph**: Shows how functions call each other
2. **Data flow diagram**: Shows input to processing to output transformation
3. **S3 object structure**: Shows the internal structure of result objects
4. **Integration points**: Shows how stages connect together

All diagrams use valid Mermaid syntax compatible with GitHub, VS Code, and other Mermaid renderers.
