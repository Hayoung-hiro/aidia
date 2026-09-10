# Shared visual structure for all three workflow pages.
.workflow_help <- function(title, ...) {
  tags$details(class = "config-help",
    tags$summary(`aria-label` = paste("Help:", title), "?"),
    div(class = "config-help-body", tags$strong(title), ...))
}

.workflow_row <- function(label, ..., info = NULL) {
  div(class = "config-row",
    div(class = "config-row-label", tags$span(label), info),
    div(class = "config-row-fields", role = "group", `aria-label` = label, ...))
}

.workflow_section <- function(page, number, title, ..., action = NULL, info = NULL) {
  heading_id <- paste0(page, "-heading-", number)
  tags$section(class = "config-section", `aria-labelledby` = heading_id,
    tags$header(class = "config-section-heading",
      tags$span(class = "config-section-number", `aria-hidden` = "true", number),
      h3(id = heading_id, title), info, action),
    div(class = "config-section-body", ...))
}

.workflow_subheading <- function(title, info = NULL) {
  div(class = "workflow-subheading", h4(title), info)
}
