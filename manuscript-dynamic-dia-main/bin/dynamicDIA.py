import numpy as np
import os
from enum import Enum
import math
import re
from IPython.display import set_matplotlib_formats
import matplotlib.pyplot as plt
from cycler import cycler
from datetime import datetime
import random




def _sg_smooth(y_array, kernel):
    '''
        The savitsky golay kernel is used to smooth a set of data.
        https://en.wikipedia.org/wiki/Savitzky%E2%80%93Golay_filter
        A kernel is convolved with the data to remove higher frequency
        oscillations.  S-G uses a least-squares formulation to get the job done.
        It uses the fact that to solve the a polynomial least squares equation,
        you'd have A * x = b, where b are the observed data, x are the coefficients,
        and A is the special polynomial basis.  The matrix A is set up as follows :
        each column is a basis of increasing order from 0 to k.  For each observed point's
        x value, the column would be x^i, where i is the column index.  So if we had
        X = {1, 2, 3, 4}, the first rows of A would be

        1, 1, 1, 1
        1, 2, 4, 8
        1, 4, 16, 64

        The least squares solution is x = (At*A)^-1 * At * b
        If you make the matrix (At*A)^-1 * At, it will have size
        k x N, where N is the number of points in b.  The savitsky-golay coefficients
        for smoothing are the zeroth order, or first row of this matrix.  Incidentally,
        the second row can be used to estimate the first derivative of a set of data,
        third row the second derivative, etc.  Below is the code to find the coefficients
        in C++ using the eigen library.

        // make the J matrix, which is the polynomial basis matrix
        auto polyOrder = params.filterOrder;
        MatrixXf J(N, polyOrder + 1);

        for (auto order = 0; order <= polyOrder; ++order) {
            for (int z = -halfSize, row = 0; z <= halfSize; ++z, ++row) {
                J(row, order) = powf(z, order);
            }
        }

        MatrixXf Jt = J.transpose();
        MatrixXf C = (Jt*J).inverse() * Jt;
        _savitskyGolayCoefficients = C.row(0).transpose();

        param y_array : array of data to be smoothed
        param kernel : SG array that gets convolved with the data
    '''
    size_kernel, size_data = len(kernel), len(y_array)
    halfsize_kernel = math.floor(size_kernel // 2)
    # we need enough data to at least get one pass on it
    if size_data < size_kernel:
        return None

    smooth_y = []
    for i in range(size_data):
        result = 0.0
        # the start and stop indices of the data.  this may be
        # outside of the bounds of the data, but we'll just use the
        # actual data for those points
        start, stop = i - halfsize_kernel, i + halfsize_kernel + 1
        if start < 0 or stop >= size_data:
            result = y_array[i]
        else:
            # convolve the data with the kernel
            k = 0
            for j in range(start, stop):
                if j >= 0 and j < size_data:
                    result = result + kernel[k] * y_array[j]
                k += 1
        smooth_y.append(result)
    return smooth_y


_SG_7_3 = [
    -0.0952381,
    0.142857,
    0.285714,
    0.333333,
    0.285714,
    0.142857,
    -0.0952381,
]

def savitsky_golay_7pt_3order(y_array):
    '''
        7pt smoothing with 3rd order polynomial
    '''
    return _sg_smooth(y_array, _SG_7_3)


def round_to_closest(a):
    flor = math.floor(a)
    frac = a - flor
    if frac < 0.5:
        return flor
    else:
        return math.ceil(a)

def validate_mz_bin_size(mz_bin_size, OPT_DIA_SLOPE):
    '''
        Given a value like 0.5, or 2.0, convert
        into a multiple of the OPT_DIA_SLOPE
    '''
    assert(mz_bin_size > 0), 'Bin size must be > 0'

    if mz_bin_size < OPT_DIA_SLOPE:
        factor = round_to_closest(OPT_DIA_SLOPE / mz_bin_size)
        return OPT_DIA_SLOPE / factor
    else:
        factor = round_to_closest(mz_bin_size / OPT_DIA_SLOPE)
        return factor * OPT_DIA_SLOPE

def convert_to_optimized_mz(mz, OPT_DIA_SLOPE, OPT_DIA_INT):
    return np.floor(mz / OPT_DIA_SLOPE) * OPT_DIA_SLOPE + OPT_DIA_INT;

def compute_precursor_locations(isolation_width_th, instrument_speed_hz, cycle_time_sec, hist, mz_axis):
    '''
        given the histogram computed above, for each time bin, determine the best placement
        in m/z space of set of continguous DIA scans.  The isolation width, instrument speed,
        and cycle time determine how many scans there will be.  I allowed for using some alignment
        scans in for Retrospective alignment, so lowered the instrument speed from 70 to 57
    '''
    scans_per_cycle = np.floor(cycle_time_sec * instrument_speed_hz)
    mz_range_per_cycle = int(scans_per_cycle * isolation_width_th)

    num_mz_bins = len(hist[0])
    mz_step = mz_axis[1]-mz_axis[0]
    mz_indices_per_cycle = int(mz_range_per_cycle / mz_step)
    num_trials = num_mz_bins - mz_indices_per_cycle + 1
    best_mz_bins = []
    total_num_peptides = 0
    for ridx,rt_row in enumerate(hist):
        # try each possible location of the swatch
        max_idx, max_peptides = 0, 0
        for tidx in range(num_trials):
            peptides_covered = np.sum(rt_row[tidx:min(num_mz_bins, tidx+mz_indices_per_cycle)])
            if peptides_covered > max_peptides:
                max_idx = tidx
                max_peptides = peptides_covered
        if max_peptides == 0:
            max_idx = 0 if ridx==0 else best_mz_bins[-1]
        best_mz_bins.append(max_idx)
        total_num_peptides += max_peptides

    # compute and smooth
    low_mz_values = savitsky_golay_7pt_3order([x*mz_step + mz_axis[0] for x in best_mz_bins])
    high_mz_values = savitsky_golay_7pt_3order([x+mz_range_per_cycle for x in low_mz_values])

    return low_mz_values, high_mz_values, total_num_peptides

def create_scheduled_dia_scans(rt_axis, low_mz_values, high_mz_values, isolation_width_th, OPT_DIA_SLOPE, OPT_DIA_INT):
    '''
        Create a set of information that could be written to a file and loaded onto
        a method
    '''
    dia_isolation_width = validate_mz_bin_size(isolation_width_th, OPT_DIA_SLOPE)
    scheduled_dia = []
    for rt,low,high in zip(rt_axis, low_mz_values, high_mz_values):
        dia_low = convert_to_optimized_mz(low, OPT_DIA_SLOPE, OPT_DIA_INT)
        dia_high = convert_to_optimized_mz(high, OPT_DIA_SLOPE, OPT_DIA_INT)
        num_scans = int(np.ceil((dia_high - dia_low)/dia_isolation_width) + 1)
        dia_scans = []
        for sidx in range(num_scans):
            dia_scans.append(sidx*dia_isolation_width + dia_low)
        scheduled_dia.append({
            'rt': rt,
            'scans': dia_scans
        })
    return scheduled_dia

def save_scheduled_dia_scans(file_name, scheduled_dia):
    with open(file_name, 'w') as f:
        f.write('m/z,t start (min),t stop (min)\n')
        for sidx in range(len(scheduled_dia)-1):
            period,next_period = scheduled_dia[sidx],scheduled_dia[sidx+1]
            start_time = period['rt']
            stop_time = next_period['rt']
            for prec in period['scans']:
                f.write(f'{prec},{start_time},{stop_time}\n')
