# The report can be shorter than the template, but native output cannot extend
# past the template's acquisition duration. Use one check for display and gating.
.shiny_method_rt_issue <- function(validated_data, method) {
  if (is.null(validated_data) || is.null(method)) return(NULL)
  report_rt <- validated_data$data$RT.Apex
  report_rt <- report_rt[is.finite(report_rt)]
  duration <- method$duration_min
  if (!length(report_rt) || length(duration) != 1L || !is.finite(duration)) return(NULL)
  report_end <- max(report_rt)
  if (report_end <= duration) return(NULL)
  list(report_end = report_end, template_end = duration,
    message = sprintf("Report RT reaches %.2f min; the method template ends at %.2f min.",
      report_end, duration))
}
