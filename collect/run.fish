#!/usr/bin/env fish

# === Command line flags and parameters ===

set -l options --name (status basename)
set -a options (fish_opt --short c --long config-file --required-val)
set -a options (fish_opt --short v --long verbose)
set -a options (fish_opt --short f --long filter --required-val)
set -a options (fish_opt --short k --long keep-dirs)
set -a options (fish_opt --short h --long help)

argparse $options -- $argv

set -q _flag_c || set _flag_c ./config.fish
set -g config_file (path resolve $_flag_c)
set -q _flag_v && set -g verbose $_flag_v
set -q _flag_f && set -g filter $_flag_f
set -q _flag_k && set -g keepDirs $_flag_k

if set -q _flag_h
    echo (status basename) "[options] ZIPFILE"
    echo
    echo "Run a benchmark suite and compress the results into the given zipfile."
    echo
    echo "Valid options:"
    echo "  -c --config-file <file>  The config file to read. Defaults to './config.fish'."
    echo "  -v --verbose             Print additional output from commands run."
    echo "  -f --filter      <regex> Run only tests that match the given regex."
    echo "  -k --keep-dirs           Keep (and print) temporary directories on exit, for debugging."
    echo "  -h --help                Show this help text."
    echo
    echo "Example:"
    echo "  "(status basename)" result.zip"

    exit 0
end

if set -q argv[1]
    set -g zipFile (path resolve $argv[1])
else
    echo "Missing argument: ZIPFILE"
    exit 1
end


# === Global state ===

set -g repoWorkDir (mktemp -d)
set -g outputWorkDir (mktemp -d)
set -g relDir ""

cd $outputWorkDir
if set -q verbose
    echo "Working in:"
    echo "- repositories: $repoWorkDir"
    echo "- output:       $outputWorkDir"
end


# === Helpers ===

function runQuietOrExit
    set -l output ($argv[1] $argv[2..] &| string collect --allow-empty)
    set -l res $pipestatus[1]
    if test $res -ne 0
        echo "Command failed:" (string escape $argv)
        echo "Output:"
        echo $output
        echo
        exit $res
    else if set -q verbose
        echo "Command succeeded:" (string escape $argv)
        echo "Output:"
        echo
        echo $output
    end
end

function _finalCleanup --on-event fish_exit
    cd $outputWorkDir
    echo "Compressing output..."
    zip -r $zipFile -- *
    if set -q keepDirs
        echo "Keeping temporary directories:"
        echo "- repositories: $repoWorkDir"
        echo "- output:       $outputWorkDir"
    else
        echo "Deleting temporary directories"
        rm -rf $repoWorkDir $outputWorkDir
    end
end

function overwriteCurrentLine --argument-names msg
    echo -ne "\33[2K\r"
    echo -n $msg
end


# === Setup repositories ===

# Clone a repository in the temporary working directory. Takes a
# `name`, a `url`, and an optional commit/branch to checkout after
# cloning.
function addRepo --argument-names name url checkout
    set -l wd (pwd)
    echo "$name: Cloning from $url" (if test -n "$checkout"; echo "(checkout $checkout)"; end)
    runQuietOrExit git clone $url $repoWorkDir/$name
    if test -n "$checkout"
        cd $repoWorkDir/$name
        runQuietOrExit git checkout $checkout
    end
    cd $wd
end

# Run a command in the root directory of a repository. Takes the `name`
# as specified to `addRepo`.
function runInRepo --argument-names name
    set -l wd (pwd)
    echo "$name:" (string escape $argv[2..])
    cd $repoWorkDir/$name
    runQuietOrExit $argv[2..]
    cd $wd
end

# Helper to produce the absolute path to the checkout of a
# repository. Takes the `name` as specified to `addRepo`.
function repoPath --argument-names name
    path resolve $repoWorkDir/$name
end

# Helper to print the hash of the current commit used for a given
# repository. Takes the `name` as specified to `addRepo`.
function repoCommitHash --argument-names name
    git -C $repoWorkDir/$name rev-parse HEAD
end


# === Collect Metadata for the run ===

# Append metadata for the run as a whole (if run before `defineTest`)
# or the current test (if run after `defineTest`). The `value` will be
# interpreted as a json-value if possible, otherwise it will be quoted
# as a string.
function setMetadataKV --argument-names key value
    set -l result '{}'
    if not begin; echo $value | jq -Rs fromjson &>/dev/null; end
        # NOTE(vipa, 2025-07-21): Not valid json, quote it
        set value '"'$value'"'
    end
    if test -f ./metadata.json
        set -l result (jq -c '.["'$key'"] = '$value < ./metadata.json)
        echo $result > ./metadata.json
    else
        echo '{"'$key'":'$value'}' > ./metadata.json
    end
end

# Take the supplied list of arguments and turn them into a json list,
# interpreting each value as is if it parses, otherwise as a string.
function asJsonList
    string join0 -- $argv | jq -Rsc 'rtrimstr("\u0000") | split("\u0000") | map(try fromjson // .)'
end


# === Setup tests ===

# Place subsequent tests in this directory inside the final
# archive. Supports paths that include "/", as well as the empty
# path. Including ".." is not recommended.
function setDir --argument-names dir
    set -g relDir "$dir"
end

# Define a test. Will be placed in a directory with the given name, in
# the directory set by `setDir`, inside the final archive. Intended
# usage:
#
# if defineTest name-of-test
#   # run test, and write results to files in the
#   # current working directory
# end
function defineTest --argument-names name
    set -l testName (path normalize "$relDir/$name")
    set -l dir (path normalize "$outputWorkDir/$testName")
    if test -e $dir
        echo "Skipping duplicate definition of test $testName"
        status stack-trace
        return 1
    else if set -q filter; and not string match --regex --quiet -- "$filter" $testName
        echo "Skipping test $testName"
        return 1
    else
        echo "Running test $testName"
    end

    mkdir -p $dir
    cd $dir
    return 0
end


# === Do The Thing ===

source $config_file
