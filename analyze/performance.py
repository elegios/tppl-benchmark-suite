import pandas
import json
import os

def simple_perf_row(path):
    """Produce a dict describing a row suitable for inclusion in a
    dataframe, describing the "simple" performance metrics available
    in the collected data, i.e., those that result in a single number
    per test.

    """
    with (path / "metadata.json").open() as f:
        metadata = json.load(f)
    with (path / "perf.json").open() as f:
        perf = json.load(f)
    with (path / "compile-perf.json").open() as f:
        compile_perf = json.load(f)

    return {
        'model': metadata['model'],
        'data': metadata['data'],
        'flags': metadata['flags'],
        'runMaxMemory': perf['maxMemoryKB'],
        'runTime': perf['totalDurationS'],
        'compileMaxMemory': compile_perf['maxMemoryKB'],
        'compileTime': compile_perf['totalDurationS'],
    }

def simple_perf_for_all(root, simplify_paths=True):
    """Produce a pandas dataframe of simple performance data (i.e.,
    performance metrics that only produce a single number per
    test). Intended to be run on the root of an archive.

    If `simplify_paths` is `True` (which is the default), strip common
    prefixes of the paths to models and datasets, respectively.

    Example usage:

    with zipfile.open("path/to/archive.zip", "r") as archive:
        root = zipfile.Path(archive)
        simple_perf_for_all(root)

    """
    rows = []
    for dir in root.iterdir():
        if dir.is_file():
            continue
        for test in iter_test_dirs(dir):
            rows.append(simple_perf_row(test))
    df = pandas.DataFrame.from_records(rows)
    if simplify_paths:
        common = os.path.commonprefix(list(df['model']))
        df['model'] = df['model'].map(lambda p: p.removeprefix(common))
        common = os.path.commonprefix(list(df['data']))
        df['data'] = df['data'].map(lambda p: p.removeprefix(common))
    return df
