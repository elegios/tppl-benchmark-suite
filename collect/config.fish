# === Setup repositories and environment variables, collect metadata for the run ===

setMetadataKV secondsSinceEpochAtStart (date +%s)
setMetadataKV lshw (lshw -json 2>/dev/null | string collect)

set -x --path MCORE_LIBS

addRepo mi https://github.com/miking-lang/miking.git
set -xp OCAMLPATH (repoPath mi)/build/lib/
set -p PATH (repoPath mi)/build/
set -a MCORE_LIBS stdlib=(repoPath mi)/src/stdlib
runInRepo mi make
setMetadataKV miHash (repoCommitHash mi)

addRepo dppl https://github.com/miking-lang/miking-dppl.git
set -p PATH (repoPath dppl)/build/
set -a MCORE_LIBS coreppl=(repoPath dppl)/coreppl/src
runInRepo dppl make
setMetadataKV dpplHash (repoCommitHash dppl)

addRepo tppl https://github.com/treeppl/treeppl.git
set -p PATH (repoPath tppl)/build/
set -a MCORE_LIBS treeppl=(repoPath tppl)/src
runInRepo tppl make
setMetadataKV tpplHash (repoCommitHash tppl)

# We initialize all tests with the same seed across the run, to try to
# maximize the odds of similarly configured tests behaving similarly.
set seed (random)
setMetadataKV seed $seed


# === Test runner, including the specification for the output ===

# Assumes the input data can be found adjacent to the model, e.g., if
# `model` is `path/to/foo.tppl` then the data is `path/to/foo.json`.
function runTest --argument-names model
    set -l flags $argv[2..]
    set -l data (path change-extension .json $model)
    set -l startTime (date +%s)
    command time --format '{"maxMemoryKB":%M,"totalDurationS":%e}' --output compile-perf.json tpplc $model --output exe $flags
    and command time --format '{"maxMemoryKB":%M,"totalDurationS":%e}' --output perf.json ./exe $data > samples.json 2> debug-info.json
    setMetadataKV exitCode $status
    set -l endTime (date +%s)
    setMetadataKV model $model
    setMetadataKV data $data
    setMetadataKV flags (string join " " -- (string escape -- $flags))
    setMetadataKV totalDurationS (math $endTime - $startTime)
    rm -f exe
end


# === Define the actual tests ===

set models phylogeny/clads.tppl phylogeny/crbd.tppl lang/coin.tppl

for m in $models
    setDir correctness/(path basename --no-extension $m)
    set -l model (repoPath tppl)/models/$m
    set -l commonOpts --seed $seed --particles 10000
    if defineTest mcmc-lightweight-cps-full
        runTest $model -m mcmc-lightweight --cps full --debug-iterations $commonOpts
    end
    if defineTest mcmc-lightweight-cps-partial
        runTest $model -m mcmc-lightweight --cps partial --debug-iterations $commonOpts
    end
    if defineTest mcmc-lightweight-cps-none
        runTest $model -m mcmc-lightweight --cps none --debug-iterations $commonOpts
    end
end
