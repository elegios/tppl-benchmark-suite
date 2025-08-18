import pandas
import numpy as np
import json
import os
import zipfile
import sys

from util import iter_test_dirs

def add_simple_perf_row(path, res):
    """Add dicts describing a row suitable for inclusion in a
    dataframe, describing the "simple" performance metrics available
    in the collected data, i.e., those that result in a single number
    per test.

    """
    with (path / "metadata.json").open() as f:
        metadata = json.load(f)
    for i in range(1, metadata["numRuns"]):
        try:
            with (path / f"{i}.perf.json").open() as f:
                perf = json.load(f)
        except:
            print("Failed to load json: " + str(path / f"{i}.perf.json"))
            return
        try:
            with (path / f"{i}.compile-perf.json").open() as f:
                compile_perf = json.load(f)
        except:
            print("Failed to load json: " + str(path / f"{i}.compile-perf.json"))()
            return
        res.append({
            'model': metadata['model'],
            'data': metadata['data'],
            'flags': metadata['flags'],
            'runIdx': i,
            'runMaxMemory': perf['maxMemoryKB'],
            'runTime': perf['totalDurationS'],
            'compileMaxMemory': compile_perf['maxMemoryKB'],
            'compileTime': compile_perf['totalDurationS'],
        })

def simple_perf_for_all(root, simplify_paths=True):
    """Produce a pandas dataframe of simple performance data (i.e.,
    performance metrics that only produce a single number per
    test). Intended to be run on the root of an archive.

    If `simplify_paths` is `True` (which is the default), strip common
    prefixes of the paths to models and datasets, respectively.

    Example usage:

    with zipfile.ZipFile("path/to/archive.zip", "r") as archive:
        root = zipfile.Path(archive)
        simple_perf_for_all(root)

    """
    rows = []
    for test in iter_test_dirs(root / 'performance'):
        add_simple_perf_row(test, rows)
    df = pandas.DataFrame.from_records(rows)
    with (root / "metadata.json").open() as f:
        s = json.load(f)["secondsSinceEpochAtStart"]
        print(s)
        df['runStart'] = pandas.to_datetime(s, unit="s")
    if simplify_paths:
        common = os.path.commonprefix(list(df['model']))
        df['model'] = df['model'].map(lambda p: p.removeprefix(common))
        common = os.path.commonprefix(list(df['data']))
        df['data'] = df['data'].map(lambda p: p.removeprefix(common))
    return df


if __name__  == '__main__':
    dfs = []
    for p in sys.argv[1:]:
        with zipfile.ZipFile(p, "r") as archive:
            root = zipfile.Path(archive)
            dfs.append(simple_perf_for_all(root))
    df = pandas.concat(dfs)
    df['flags'] = df['flags'].map(lambda x: ' '.join(map(str, x)))
    timing = df.pivot(index=['model','data','runIdx'], columns=['runStart', 'flags'], values=['runTime'])
    with pandas.option_context('display.max_rows', None, 'display.max_columns', None, 'display.width', 1000000000000):
        print(timing)
