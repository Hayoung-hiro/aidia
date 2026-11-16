# Candidate-boundary proximity on the periodic mass-defect lattice. Counts are
# identified precursor rows, not measured ion transmission or isotope envelopes.
prepare_fz_profile <- function(precursor_data) {
  mz <- precursor_data$Precursor.Mz
  if (!is.numeric(mz)) stop("Precursor.Mz must be numeric.")
  valid <- is.finite(mz) & mz > 0
  charge <- precursor_data[["Precursor.Charge"]]
  if (is.null(charge)) charge <- rep(NA_real_, length(mz))
  charge <- suppressWarnings(as.numeric(as.character(charge)))
  charge[!is.finite(charge) | charge < 1 | charge != floor(charge)] <- NA_real_
  phase <- mz[valid] %% OPTIMAL_INCREMENT
  charge <- charge[valid]
  labels <- ifelse(is.na(charge), "Unknown", paste0(charge, "+"))
  known <- sort(unique(charge[!is.na(charge)]))
  levels <- c(if (length(known)) paste0(known, "+"),
    if (anyNA(charge)) "Unknown")
  groups <- lapply(levels, function(label) {
    values <- sort(phase[labels == label])
    list(label = label, n = length(values), phase = values)
  })
  list(groups = groups, phase = sort(phase), z2 = sort(phase[!is.na(charge) & charge == 2]),
    n = length(phase), excluded = sum(!valid), increment = OPTIMAL_INCREMENT,
    precursors = data.frame(mz = mz[valid], phase = phase,
      charge = factor(labels, levels = levels)))
}

count_fz_margin <- function(phase, offsets, margin) {
  if (length(margin) != 1L || !is.finite(margin) || margin <= 0 || margin >= OPTIMAL_INCREMENT / 2)
    stop("Margin must be positive and below half the mass-defect period.")
  if (any(!is.finite(offsets))) stop("Offsets must be finite.")
  if (!length(phase)) return(integer(length(offsets)))
  phase <- sort(phase %% OPTIMAL_INCREMENT)
  wrapped <- c(phase - OPTIMAL_INCREMENT, phase, phase + OPTIMAL_INCREMENT)
  offsets <- offsets %% OPTIMAL_INCREMENT
  # Include both band edges, tolerating floating-point modulo error.
  tolerance <- 1e-10
  findInterval(offsets + margin + tolerance, wrapped) -
    findInterval(offsets - margin - tolerance, wrapped)
}

suggest_fz_offset <- function(profile, target = c("z2", "all"), margin = 0.05) {
  target <- match.arg(target)
  if (!profile$n) return(list(offset = NULL, reason = "No valid precursor m/z values available."))
  if (target == "z2" && !length(profile$z2))
    return(list(offset = NULL, reason = "No 2+ precursors available. Select All charges to use the available precursors."))
  offsets <- seq_len(9999L) / 10000
  all_counts <- count_fz_margin(profile$phase, offsets, margin)
  target_counts <- if (target == "z2") count_fz_margin(profile$z2, offsets, margin) else all_counts
  # Lexicographic priority: never trade a 2+ precursor for other charges in z2
  # mode. Remaining ties prefer the established 0.25, then the smaller offset.
  best <- order(target_counts, all_counts, abs(offsets - 0.25), offsets)[1]
  list(offset = offsets[best], target_count = target_counts[best],
    target_n = if (target == "z2") length(profile$z2) else profile$n,
    all_count = all_counts[best], all_n = profile$n, reason = NULL)
}

# Count each covered precursor once if it is near any active cycle's edge.
# Use the same RT/m/z membership as final window coverage; this is proximity,
# not a prediction of loss after combining staggered cycles.
summarize_fz_edges <- function(precursor_data, windows, margin) {
  if (!nrow(windows)) return(NULL)
  matches <- .match_precursors_in_2d_windows(precursor_data$RT.Apex,
    precursor_data$Precursor.Mz, windows$rt_start, windows$rt_end,
    windows$mz_start, windows$mz_end)
  covered <- matches$covered
  close <- rep(FALSE, nrow(precursor_data))
  for (idx in split(seq_len(nrow(windows)), paste(windows$rt_start, windows$rt_end))) {
    first <- idx[1]
    in_time <- precursor_data$RT.Apex >= windows$rt_start[first] &
      (precursor_data$RT.Apex < windows$rt_end[first] |
        (windows$rt_end[first] == max(windows$rt_end) & precursor_data$RT.Apex == windows$rt_end[first]))
    rows <- which(in_time & covered)
    if (!length(rows)) next
    edges <- sort(unique(c(windows$mz_start[idx], windows$mz_end[idx])))
    mz <- precursor_data$Precursor.Mz[rows]
    left <- findInterval(mz, edges)
    distance <- pmin(abs(mz - edges[pmax(1L, left)]),
      abs(mz - edges[pmin(length(edges), left + 1L)]))
    close[rows] <- close[rows] | distance <= margin + 1e-10
  }
  charge <- suppressWarnings(as.numeric(as.character(precursor_data[["Precursor.Charge"]])))
  z2 <- if (length(charge)) !is.na(charge) & charge == 2 else rep(FALSE, length(covered))
  list(all_n = sum(covered), all_count = sum(close & covered),
    z2_n = sum(covered & z2), z2_count = sum(close & covered & z2))
}
