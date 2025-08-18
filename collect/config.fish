# === Platform specific stuff ===

# NOTE(vipa, 2025-08-21): lshw is not available on Mac, so we skip it if it's not available
if command --query lshw
    setMetadataKV lshw (lshw -json 2>/dev/null | string collect)
end

# NOTE(vipa, 2025-08-21): Mac has a 'time' with different flags, we
# prefer gnu's time, which when installed via brew can be found as
# 'gtime', so default to that if it's installed.
set -g time time
if command --query gtime
    set -g time gtime
end


# === Setup repositories and environment variables, collect metadata for the run ===

setMetadataKV secondsSinceEpochAtStart (date +%s)

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

set -g numRuns 1
set -g timeout 0
set -g killTimeout 20s
set -g keepData true

function runTests --argument-names model data
    set -l flags $argv[3..]
    set -l exitCodes
    set -l startTime (date +%s)
    for i in (seq $numRuns)
        overwriteCurrentLine (math $i - 1)/$numRuns
        command $time --quiet --format '{"maxMemoryKB":%M,"totalDurationS":%e}' --output $i.compile-perf.json tpplc $model --output exe --seed $seeds[$i] $flags > $i.compile-out 2> $i.compile-err
        and command $time --quiet --format '{"maxMemoryKB":%M,"totalDurationS":%e}' --output $i.perf.json timeout --kill-after=$killTimeout $timeout ./exe $data > $i.samples.json 2> $i.debug-info.json
        set -a exitCodes $status
        if test "$keepData" != true
            rm -f $i.samples.json
        end
    end
    set -l endTime (date +%s)
    overwriteCurrentLine
    setMetadataKV exitCodes (asJsonList $exitCodes)
    setMetadataKV model $model
    setMetadataKV data $data
    setMetadataKV numRuns $numRuns
    setMetadataKV seeds (asJsonList $seeds[..$numRuns])
    setMetadataKV flags (asJsonList (string escape -- $flags))
    setMetadataKV totalDurationS (math $endTime - $startTime)
    rm -f exe
end

# The default location of test data relative to each model
function find_data_file --argument-names model_file
    string match --regex --quiet '(?<dir>.*)/(?<base>[^/]+)\.tppl' -- $model_file
    echo $dir/data/testdata_$base.json
end


# === Define the actual tests ===

set -g numRuns 1
set -g timeout 240m
set -g killTimeout 20s
set -g keepData true

set -l mcmcOptions -m mcmc-lightweight --cps full --debug-iterations --kernel --align
set -l smcOptions -m smc-bpf --cps full --resample align

setDir correctness/tree_inference
if defineTest gtr_pruning_scaled_mcmc
    set -l dir (repoPath tppl)/models/tree-inference
    set -l model $dir/tree_inference_pruning_gtr.tppl
    runTests $model (find_data_file $model) $mcmcOptions --particles 1000000
end
if defineTest gtr_pruning_scaled_smc
    set -l dir (repoPath tppl)/models/tree-inference
    set -l model $dir/tree_inference_pruning_gtr.tppl
    runTests $model (find_data_file $model) $smcOptions --particles 1000000
end

# NOTE(vipa, 2025-08-26): This doesn't seem to complete, rather it
# gets killed, presumably by running out of RAM
# setDir correctness/host_repertoire
# if defineTest mcmc
#     set -l dir (repoPath tppl)/models/host-repertoire-evolution
#     set -l model $dir/host_repertoire.tppl
#     runTests $model (find_data_file $model) $mcmcOptions --particles 100000
# end

setDir correctness/clads
if defineTest mcmc
    set -l dir (repoPath tppl)/models/diversification
    set -l model $dir/clads.tppl
    runTests $model (find_data_file $model) $mcmcOptions --particles 1000000
end
# TODO(vipa, 2025-08-21): BDD-model

# NOTE(vipa, 2025-08-21): We do not include the QT model for now,
# since it's not currently in development, and it's relatively slow
set all_models (find (repoPath tppl)/models -name '*.tppl' -a ! -name 'qt.tppl')
# Configurations, one per line. Arguments with a space should be quoted.
set all_configurations '
-m is-lw --cps none
-m is-lw --cps partial
-m is-lw --cps full
-m smc-bpf --cps full --resample align
-m smc-bpf --cps full --resample likelihood
-m smc-bpf --cps full --resample manual
-m smc-bpf --cps partial --resample align
-m smc-bpf --cps partial --resample likelihood
-m smc-bpf --cps partial --resample manual
-m smc-apf --cps full --resample align
-m smc-apf --cps full --resample likelihood
-m smc-apf --cps full --resample manual
-m smc-apf --cps partial --resample align
-m smc-apf --cps partial --resample likelihood
-m smc-apf --cps partial --resample manual
-m mcmc-lightweight --cps none
-m mcmc-lightweight --align --cps none
-m mcmc-lightweight --align --cps none --kernel
-m mcmc-lightweight --align --cps full
-m mcmc-lightweight --align --cps full --kernel
-m mcmc-lightweight --align --cps partial
-m mcmc-lightweight --align --cps partial --kernel
-m mcmc-trace
-m mcmc-naive
-m pmcmc-pimh --cps full
-m pmcmc-pimh --cps partial
'

function format_filename --argument-names filename
    echo -n "t"
    echo -n $filename | tr --complement a-zA-Z0-9._- _
end

function split_opts --argument-names opts
    echo -n $opts | read --tokenize --list res --local
    for o in $res
        echo $o
    end
end

set -g numRuns 20
set -g timeout 120s
set -g killTimeout 130s
set -g keepData false

for m in $all_models
    setDir performance/(path basename --no-extension $m)
    set -l model $m
    set -l commonOpts --particles 3000
    for opts in (string trim -- $all_configurations)
        if defineTest (format_filename $opts)
            runTests $model (find_data_file $model) (split_opts $opts) $commonOpts
        end
    end
end
