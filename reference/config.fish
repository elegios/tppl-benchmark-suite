# This example is written for treeppl to run coin, but skips some
# steps that would be important for treeppl, in particular, that you'd
# need to clone and build miking and miking-dppl as well, and set some
# environment variables to make them see each other. The steps for
# this can be seen in the beginning of `collect/config.fish`, if
# relevant, but I figure most tools we use for data collections will
# just be one repository, and environment variables will already be
# set from having installed their system dependencies (e.g., node or
# julia).


# The name given after `defineTest` serves two purposes:
# - It's a name to filter by when picking what to run.
# - It's the name of the folder created to house data.
if defineTest clads
  # === Fetch sources ===

  # `addRepo` clones a repo. First argument is a name, second is a
  # URL. There is an optional third argument that can be a branch name
  # or commit hash, if you don't want the latest commit. The name
  # should be unique across all tests.
  addRepo tppl https://github.com/treeppl/treeppl.git
  # Might as well store the commit hash
  setMetadataKV commitHash (repoCommitHash tppl)

  # === Apply patches ===

  # If we have a patch to apply, called `fix-stuff.patch`, stored
  # adjacent to this file (config.fish), it can be run as follows:

  # runInRepo tppl git apply (status dirname)/fix-stuff.patch

  # === Fetch dependencies ===

  # This step isn't required for treeppl, but if it, e.g., was a node
  # project, we'd want to run `npm install`:

  # runInRepo tppl npm install

  # === Build the project, if needed ===

  runInRepo tppl make
  runInRepo tppl build/tpplc -m mcmc-lightweight models/lang/coin.tppl --output build/coin

  # === Produce the data ===

  # Here we run an arbitrary command that writes to files in the
  # current directory. We can access files in the repo via
  # `(repoPath tppl)`, and stuff relative to this config file via
  # `(status dirname)`.
  (repoPath tppl)/build/coin (status dirname)/../collect/input_data/coin_input_stuff.json > data.json
end
