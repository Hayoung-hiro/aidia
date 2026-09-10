\name{evaluate_fixed_method_baseline}
\alias{evaluate_fixed_method_baseline}
\title{Evaluate the Input-Defined Fixed Reference Method}
\usage{
evaluate_fixed_method_baseline(validated_data, optimization_plan, optimized_windows)
}
\arguments{
\item{validated_data}{ValidatedData used for the optimization.}
\item{optimization_plan}{OptimizationPlan with original method settings.}
\item{optimized_windows}{OptimizedWindows result.}
}
\value{Reference density summary, or NULL when original settings are absent.}
\description{
Reuses the temporal-density proxy on the same RT segments as the candidate.
The reference m/z range and window count come from the execution snapshot.
No reference is fabricated for older results without that snapshot.
}
