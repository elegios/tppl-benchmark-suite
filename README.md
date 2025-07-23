# TreePPL Benchmark Suite

This repo contains the scripts necessary to run the benchmark suite
for TreePPL. The purpose of this suite is to a) verify accuracy of
inference and b) produce performance metrics like time and memory
required to achieve that accuracy. The intent is also te be able to
compare these metrics across different versions of the compiler and
model implementations, which is the primary reason the suite is in a
separate repository from the compiler.

We divide the scripts in two major categories: those that run
experiments to produce data, and those that analyze that data. The
former is a pair of [fish](https://fishshell.com/) scripts, while the
latter is a small [Python](https://www.python.org/) application.


## Configuring and Running Experiments

The experiment runner is structured as two scripts:

- `collect/run.fish` is the main entry point and defines a number of functions
  with which to define and configure tests. Can be run with, e.g.,
  `./run.fish --help` to see the available command line flags. This
  script is written to be quite general, it has no TreePPL specific
  functionality, though it is very much designed to be precisely what
  this particular suite needs.
- `collect/config.fish` specifies the repositories to fetch and build (TreePPL
  and its direct dependencies), sets the environment variables
  necessary for the repositories to see each other, and then defines
  tests and what data to collect.

Typical usage is as follows:

```bash
./run.fish out.zip  # Run all tests, put data in `out.zip`
```


## Analyzing Collected Data
