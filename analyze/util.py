def iter_test_dirs(path):
    """Iterate over all sub-directories of the given one that contain
    a 'metadata.json' file. By construction, this will be the root of
    an archive, and the test directories. This function is thus
    intended to be called on subdirectories of the root, not the root
    itself.

    If you do want to iterate over all test directories, and assuming
    `root` is the path pointing at the root of the archive:

    for dir in root.iterdir():
        if dir.is_file():
            continue
        for test in iter_test_dirs(dir):
            ...do stuff with test...

    """
    if (path / "metadata.json").exists():
        yield path
        return
    for dir in path.iterdir():
        if dir.is_dir():
            yield from iter_test_dirs(dir)
