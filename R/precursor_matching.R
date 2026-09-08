# precursor_matching.R - Window-Precursor Matching
#
# Purpose: Efficiently count and match precursors to DIA isolation windows.
# Uses vectorized operations and binary search for O(n + m*log(n)) performance.


#' Count Precursors in Windows (Vectorized)
#'
#' Efficiently counts precursors in each window using vectorized operations.
#' This is 50-100x faster than nested loops.
#'
#' @param precursor_mz Numeric vector, precursor m/z values
#' @param window_starts Numeric vector, window start m/z values
#' @param window_ends Numeric vector, window end m/z values
#'
#' @return Integer vector, precursor count per window
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' precursors <- c(400.5, 450.2, 500.8, 550.3, 600.1)
#' counts <- count_precursors_in_windows(precursors, c(400, 500, 600), c(500, 600, 700))
#' }
count_precursors_in_windows <- function(precursor_mz, window_starts,
                                       window_ends) {
  n_windows <- length(window_starts)

  if (length(window_ends) != n_windows) {
    stop("window_starts and window_ends must have same length")
  }
  if (n_windows == 0L) return(integer(0))

  # Count each window independently as the half-open interval [start, end).
  #
  # This replaces a cut()-based single-bin assignment, which is only valid for
  # contiguous, non-overlapping windows: cut() places each precursor in exactly
  # one bin, so it cannot represent overlap. Staggered mode passes two
  # interleaved cycles (generate_staggered_windows_internal returns both), where
  # a precursor in an overlap region is legitimately isolated by one window per
  # cycle and must be counted in both. Per-window findInterval handles tiling
  # and overlap identically, in O((n + m) log n).
  mz_sorted <- sort(precursor_mz)
  left  <- findInterval(window_starts, mz_sorted, left.open = TRUE)  # #{v <  start}
  right <- findInterval(window_ends,   mz_sorted, left.open = TRUE)  # #{v <  end}
  counts <- right - left

  # Preserve the historical include.lowest behaviour: a precursor exactly at the
  # overall maximum window end (closed on the tiling's top edge) is attributed
  # to the window(s) ending there, which the half-open count would drop.
  max_end <- max(window_ends)
  n_at_max <- sum(precursor_mz == max_end, na.rm = TRUE)  # na.rm: stay NA-safe like the old cut() path
  if (n_at_max > 0L) {
    at_max <- window_ends == max_end
    counts[at_max] <- counts[at_max] + n_at_max
  }

  counts
}

#' Count Precursors in 2D Windows (RT x m/z)
#'
#' Memory-efficient function to count precursors in each 2D window.
#' Groups windows by RT segment and uses findInterval() on sorted m/z
#' for O(n + m*log(n)) time and O(n + m) memory instead of O(n*m).
#'
#' @param precursor_rt Numeric vector, precursor retention times
#' @param precursor_mz Numeric vector, precursor m/z values
#' @param window_rt_start Numeric vector, window RT start values
#' @param window_rt_end Numeric vector, window RT end values
#' @param window_mz_start Numeric vector, window m/z start values
#' @param window_mz_end Numeric vector, window m/z end values
#'
#' @return Integer vector with precursor counts for each window
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' rt <- c(10.1, 10.5, 20.2, 20.8)
#' mz <- c(400.5, 450.2, 500.8, 550.3)
#' counts <- count_precursors_in_2d_windows(
#'   rt, mz, c(10, 20), c(15, 25), c(400, 500), c(500, 600)
#' )
#' }
count_precursors_in_2d_windows <- function(precursor_rt, precursor_mz,
                                            window_rt_start, window_rt_end,
                                            window_mz_start, window_mz_end) {
  .match_precursors_in_2d_windows(
    precursor_rt, precursor_mz, window_rt_start, window_rt_end,
    window_mz_start, window_mz_end
  )$counts
}

# Final m/z geometry is authoritative. Use the same sorted interval positions for
# per-window counts and the union of covered precursor rows. Shared edges are
# half-open; the maximum RT edge and each segment's maximum m/z edge are closed.
.match_precursors_in_2d_windows <- function(precursor_rt, precursor_mz,
                                           window_rt_start, window_rt_end,
                                           window_mz_start, window_mz_end,
                                           precursor_group = NULL, window_group = NULL) {
  n_windows <- length(window_rt_start)
  n_precursors <- length(precursor_rt)
  if (length(window_rt_end) != n_windows ||
      length(window_mz_start) != n_windows || length(window_mz_end) != n_windows) {
    stop("All window vectors must have same length")
  }
  if (length(precursor_mz) != n_precursors) {
    stop("precursor_rt and precursor_mz must have same length")
  }
  counts <- integer(n_windows)
  covered <- rep(FALSE, n_precursors)
  if (n_windows == 0L) return(list(counts = counts, covered = covered))
  if (any(!is.finite(c(window_rt_start, window_rt_end, window_mz_start, window_mz_end))) ||
      any(window_rt_end < window_rt_start) || any(window_mz_end <= window_mz_start)) {
    stop("Final windows must have finite, ordered RT and m/z bounds.")
  }
  rt_key <- paste(window_rt_start, window_rt_end, sep = "_")
  # Preserve the established adaptive/merged-bin rule: explicit membership
  # takes precedence over RT ranges when both sides carry bin labels.
  use_groups <- !is.null(precursor_group) && !is.null(window_group)
  if (use_groups) rt_key <- as.character(window_group)
  global_max_rt <- max(window_rt_end)
  for (win_idx in split(seq_len(n_windows), rt_key)) {
    first <- win_idx[1L]
    rt_mask <- if (use_groups) {
      bin_membership(list(rt_group = precursor_group), window_rt_start[first],
                     window_rt_end[first], window_group[first])
    } else {
      is.finite(precursor_rt) & precursor_rt >= window_rt_start[first] &
        (precursor_rt < window_rt_end[first] |
           (window_rt_end[first] == global_max_rt & precursor_rt == global_max_rt))
    }
    idx <- which(rt_mask & is.finite(precursor_mz))
    if (!length(idx)) next
    idx <- idx[order(precursor_mz[idx])]
    mz <- precursor_mz[idx]
    left <- findInterval(window_mz_start[win_idx], mz, left.open = TRUE)
    right <- findInterval(window_mz_end[win_idx], mz, left.open = TRUE)
    at_top <- window_mz_end[win_idx] == max(window_mz_end[win_idx])
    right[at_top] <- findInterval(window_mz_end[win_idx][at_top], mz)
    counts[win_idx] <- right - left
    # Difference array marks the union without materializing a precursor x
    # window matrix, and without counting overlapping/staggered windows twice.
    changes <- tabulate(left + 1L, nbins = length(idx) + 1L) -
      tabulate(right + 1L, nbins = length(idx) + 1L)
    covered[idx[cumsum(changes)[seq_along(idx)] > 0L]] <- TRUE
  }
  list(counts = counts, covered = covered)
}


#' Find Windows Containing Precursor
#'
#' For each precursor, finds which windows contain it.
#' Returns a list where each element corresponds to a precursor.
#'
#' @param precursor_mz Numeric, single precursor m/z value
#' @param window_starts Numeric vector, window start m/z values
#' @param window_ends Numeric vector, window end m/z values
#'
#' @return Integer vector, indices of windows containing this precursor
#' @keywords internal
find_windows_for_precursor <- function(precursor_mz, window_starts,
                                       window_ends) {
  which(precursor_mz >= window_starts & precursor_mz < window_ends)
}

#' Calculate Precursor Temporal Density (Co-Elution Proxy)
#'
#' For each isolation window, computes the maximum and mean number of
#' concurrently eluting identified precursors using a sweepline algorithm.
#' Each precursor's elution interval is \code{[RT.Apex - 1*FWHM, RT.Apex + 1*FWHM]}.
#'
#' \strong{Important:} This metric is a \strong{lower bound} of actual co-isolation
#' because report.parquet only contains successfully identified precursors.
#' Precursors that failed deconvolution due to co-isolation interference are
#' absent from the data (survivor bias).
#'
#' @param precursor_mz Numeric vector, precursor m/z values
#' @param precursor_rt Numeric vector, precursor RT.Apex values (minutes)
#' @param precursor_fwhm Numeric vector, precursor FWHM values (auto-detected units)
#' @param window_mz_start Numeric vector, window m/z start values
#' @param window_mz_end Numeric vector, window m/z end values
#' @param window_rt_start Numeric vector, window RT start values (minutes)
#' @param window_rt_end Numeric vector, window RT end values (minutes)
#'
#' @return data.frame with columns: window_idx, density_max, density_mean, n_precursors
#' @keywords internal
calculate_precursor_temporal_density <- function(precursor_mz,
                                                  precursor_rt,
                                                  precursor_fwhm,
                                                  window_mz_start,
                                                  window_mz_end,
                                                  window_rt_start,
                                                  window_rt_end) {
  n_windows <- length(window_mz_start)

  # Validate input lengths
  if (length(window_mz_end) != n_windows ||
      length(window_rt_start) != n_windows ||
      length(window_rt_end) != n_windows) {
    stop("All window vectors must have the same length")
  }

  n_prec <- length(precursor_mz)
  if (length(precursor_rt) != n_prec || length(precursor_fwhm) != n_prec) {
    stop("precursor_mz, precursor_rt, and precursor_fwhm must have the same length")
  }

  # Convert FWHM to minutes: ensure_fwhm_seconds() returns seconds, divide by 60
  fwhm_min <- ensure_fwhm_seconds(precursor_fwhm) / 60

  # Precompute elution interval boundaries for every precursor (vectorized)
  elut_start <- precursor_rt - fwhm_min
  elut_end   <- precursor_rt + fwhm_min

  # Output accumulators
  out_density_max  <- numeric(n_windows)
  out_density_mean <- numeric(n_windows)
  out_n_prec       <- integer(n_windows)

  # Group windows by unique RT segment to filter precursors once per segment
  rt_key    <- paste(window_rt_start, window_rt_end, sep = "_")
  unique_rt <- unique(data.frame(
    rt_start = window_rt_start,
    rt_end   = window_rt_end,
    key      = rt_key,
    stringsAsFactors = FALSE
  ))

  for (r in seq_len(nrow(unique_rt))) {
    seg_rt_start <- unique_rt$rt_start[r]
    seg_rt_end   <- unique_rt$rt_end[r]
    seg_span     <- seg_rt_end - seg_rt_start

    # Pre-filter precursors for this RT segment ONCE
    rt_mask <- precursor_rt >= seg_rt_start & precursor_rt <= seg_rt_end
    rt_mask[is.na(rt_mask)] <- FALSE
    seg_mz    <- precursor_mz[rt_mask]
    seg_start <- elut_start[rt_mask]
    seg_end   <- elut_end[rt_mask]
    seg_fwhm  <- fwhm_min[rt_mask]

    # Windows belonging to this RT segment
    win_idx <- which(rt_key == unique_rt$key[r])

    for (w in win_idx) {
      # Filter by m/z within pre-filtered segment (not full vector)
      mz_sel <- seg_mz >= window_mz_start[w] & seg_mz <= window_mz_end[w]
      mz_sel[is.na(mz_sel)] <- FALSE
      n_in_win <- sum(mz_sel)
      out_n_prec[w] <- n_in_win

      if (n_in_win == 0L) next

      if (n_in_win == 1L) {
        out_density_max[w]  <- 1
        out_density_mean[w] <- if (seg_span > 0) seg_fwhm[mz_sel] * 2 / seg_span else 1
        next
      }

      # Sweepline: vectorized event processing
      starts_clamped <- pmax(seg_start[mz_sel], seg_rt_start)
      ends_clamped   <- pmin(seg_end[mz_sel],   seg_rt_end)

      # Build and sort events (vectors, no data.frame allocation)
      all_times  <- c(starts_clamped, ends_clamped)
      all_deltas <- c(rep(1L, n_in_win), rep(-1L, n_in_win))
      ord <- order(all_times, all_deltas)
      times  <- all_times[ord]
      deltas <- all_deltas[ord]

      # Vectorized cumsum for max density
      running <- cumsum(deltas)
      density_max_val <- max(running)

      # Time-weighted mean via vectorized diff
      dt <- diff(times)
      # running[1:(n-1)] is the level during each interval
      weighted_sum <- sum(dt * running[-length(running)])

      out_density_max[w]  <- density_max_val
      out_density_mean[w] <- if (seg_span > 0) weighted_sum / seg_span else density_max_val
    }
  }

  data.frame(
    window_idx   = seq_len(n_windows),
    density_max  = out_density_max,
    density_mean = out_density_mean,
    n_precursors = out_n_prec,
    stringsAsFactors = FALSE
  )
}
