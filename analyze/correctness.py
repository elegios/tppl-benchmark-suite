import os
import json
import pandas
import subprocess
import pickle
import math
import numpy
import scipy
import zipfile
import sys

import matplotlib.pyplot as plt
import scipy.stats
import seaborn as sns

from util import iter_test_dirs

def cumulative_distrib(df):
    cumul_df = df.sort_values(by=['samples'])
    cumul_df.reset_index(drop=True, inplace=True)

    # Verification and construction of the cumulative ref
    for lign in cumul_df.index:
        cumul_df.at[lign,"weights"] = math.exp(cumul_df.at[lign,"weights"])

    if not math.isclose(cumul_df.sum(axis=0, numeric_only=True).weights, 1):
        raise Exception("Sorry, sum of the ref weight is not equal to 1")

    cumul = 0.0
    for lign in cumul_df.index:
        cumul += cumul_df.at[lign,"weights"]
        cumul_df.at[lign,"weights"] = cumul

    cumul_df.rename(columns={'weights': 'cumul_weights'}, inplace = True)
    return cumul_df

def quantile_limit(cumul_df, quantile):
    quant_seq = [x / quantile for x in range(0, quantile, 1)]
    quant_seq.pop(0) #Search for the right value of the quantile
    q = 0
    index = 1
    result = pandas.DataFrame([], columns=['samples', 'cumul_p'])
    while (q < (quantile-1)) or (index > len(cumul_df.index)):
        if cumul_df.at[index,"cumul_weights"] > quant_seq[q]:
            result.loc[q] = ([cumul_df.at[index-1,"samples"], quant_seq[q]])
            q += 1
        index += 1
    return result

def correctness(path):
    """Check correctness of the collected data from test in directory
    `path`.

    # TODO(vipa, 2025-07-24): Record assumptions that are not encoded
    # in the collection scripts, e.g., the location and form of
    # reference data.

    """
    #Launcher
    ##Options

    with (path / "metadata.json").open() as f:
        metadata = json.load(f)
    with (path / "1.samples.json").open() as f:
        samples = json.load(f)
    with (path / "1.debug-info.json").open() as f:
        debug_info = f.readlines()

    ##Format
    result_df = pandas.DataFrame(samples, columns=['samples', 'weights'])
    lst = []
    for line in debug_info:
        line = line.rstrip()
        lst.append(json.loads(line))
    sample_df = result_df.join(pandas.DataFrame(lst, columns=['accepted', 'durationMs']))

    ##Find ref value
    model = os.path.splitext(os.path.basename(metadata["model"]))[0]
    with open(("ref/"+model), "rb") as f:
        ref_df = pickle.load(f)

    ##Compare
    ref_cumul = cumulative_distrib(ref_df)
    result_cumul  = cumulative_distrib(sample_df)

    ref_quantile = quantile_limit(ref_cumul, 1000)
    result_quantile = quantile_limit(result_cumul, 1000)

    repres = pandas.DataFrame({model+'_ref': ref_quantile.samples,
                            model: result_quantile.samples,
                            'cumul_p': ref_quantile.cumul_p})
    repres = repres.melt('cumul_p', var_name=model, value_name='samples')

    kstest_res = scipy.stats.kstest(ref_quantile.samples, result_quantile.samples)

    # Visualize the results using Seaborn and Matplotlib
    fig = sns.lineplot(x="samples", y="cumul_p", hue=model, data=repres)
    # TODO(vipa, 2025-07-31): Better output here
    plt.show(block=True)
    # fig.get_figure().show() # .savefig(path+"/kstest_pvalue_"+f'{kstest_res.pvalue:.4f}'+".png")

def correctness_for_all(root):
    """Example usage:

    with zipfile.ZipFile("path/to/archive.zip", "r") as archive:
        root = zipfile.Path(archive)
        df = correctness_for_all(root)

    """
    for test in iter_test_dirs(root / "correctness"):
        correctness(test)


if __name__  == '__main__':
    with zipfile.ZipFile(sys.argv[1], "r") as archive:
        root = zipfile.Path(archive)
        correctness_for_all(root)
