\name{fixed_method_config}
\alias{fixed_method_config}
\title{Describe the Original Fixed DIA Method}
\usage{
fixed_method_config(n_windows, mz_min = 400, mz_max = 1000)
}
\arguments{
\item{n_windows}{Original number of MS2 windows per cycle.}
\item{mz_min}{Lower edge of the original range (default 400).}
\item{mz_max}{Upper edge of the original range (default 1000).}
}
\value{List of original fixed-method settings.}
\description{
Defines contiguous equal-width windows over one constant m/z range.
These settings describe the reference method, not optimization constraints.
}
