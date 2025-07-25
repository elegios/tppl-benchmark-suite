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
# maximize the odds of similarly configured tests behaving
# similarly. We also run tests meant to measure performance multiple
# times with different seeds, since different random choices may
# easily take different execution paths and thus have different
# performance.
set max_runs 200
set seeds (for i in (seq $max_runs); random; end)
setMetadataKV seeds (asJsonList $seeds)


# === Test runner, including the specification for the output ===

# Assumes the input data can be found adjacent to the model, e.g., if
# `model` is `path/to/foo.tppl` then the data is `path/to/foo.json`.
function runTests --argument-names c model
    set -l flags $argv[3..]
    set -l data (path change-extension .json $model)
    set -l exitCodes
    set -l startTime (date +%s)
    for i in (seq $c)
        command time --format '{"maxMemoryKB":%M,"totalDurationS":%e}' --output $i.compile-perf.json tpplc $model --output exe --seed $seeds[$i] $flags
        and command time --format '{"maxMemoryKB":%M,"totalDurationS":%e}' --output $i.perf.json ./exe $data > $i.samples.json 2> $i.debug-info.json
        set -a exitCodes $status
    end
    set -l endTime (date +%s)
    setMetadataKV exitCodes (asJsonList $exitCodes)
    setMetadataKV model $model
    setMetadataKV data $data
    setMetadataKV numRuns $c
    setMetadataKV seeds (asJsonList $seeds[..$c])
    setMetadataKV flags (asJsonList (string escape -- $flags))
    setMetadataKV totalDurationS (math $endTime - $startTime)
    rm -f exe
end


# === Define the actual tests ===

set models phylogeny/clads.tppl phylogeny/crbd.tppl lang/coin.tppl

for m in $models
    setDir correctness/(path basename --no-extension $m)
    set -l model (repoPath tppl)/models/$m
    set -l commonOpts --particles 10000
    if defineTest mcmc-lightweight-cps-full
        runTests 1 $model -m mcmc-lightweight --cps full --debug-iterations $commonOpts
    end
    if defineTest mcmc-lightweight-cps-partial
        runTests 1 $model -m mcmc-lightweight --cps partial --debug-iterations $commonOpts
    end
    if defineTest mcmc-lightweight-cps-none
        runTests 1 $model -m mcmc-lightweight --cps none --debug-iterations $commonOpts
    end
end

for m in $models
    setDir performance/(path basename --no-extension $m)
    set -l model (repoPath tppl)/models/$m
    set -l commonOpts --particles 10000
    if defineTest mcmc-lightweight-cps-full
        runTests 20 $model -m mcmc-lightweight --cps full $commonOpts
    end
    if defineTest mcmc-lightweight-cps-partial
        runTests 20 $model -m mcmc-lightweight --cps partial $commonOpts
    end
    if defineTest mcmc-lightweight-cps-none
        runTests 20 $model -m mcmc-lightweight --cps none $commonOpts
    end
end
