#!/bin/bash
# Short description

printUsage() {
    cat <<EOF
usage: $PROGNAME [options] ARG

options:
  -h
     print help message
EOF
}

set -o errexit -o pipefail -o nounset
shopt -s nullglob

readonly PROGNAME=${0##*/}
readonly COMMODITY_PFANDFLASCHE=pfandflasche

# Do not use $0 or $BASH_SOURCE to get the program's directory
# Use ~/.script.conf or wrapper script with cd in ~/.local/bin/ instead
# [[ -e ~/.script.conf ]] && source ~/.script.conf
# [[ -n $PROGDIR ]] || exitWithError "error: PROGDIR variable is not defined in the config file"
# [[ -d $PROGDIR ]] || exitWithError "error: PROGDIR is not a directory"

# Always use declare instead of local!
# It's more general, can do more, and leads to more consistency.

readonly TEMPDIR=$(mktemp -d /tmp/tmp.XXXXXXXXXX)
finish() {
    rm -rf "$TEMPDIR"
}
trap finish EXIT

# $1: error message
exitWithError() {
    declare msg=${1:-}
    echo "$msg" >&2
    exit 1
}

# $*: command line arguments = "$@"
parseCommandLine() {

    declare args arg
    # this syntax iterates over all function args
    for arg; do
        declare delim=""
        case "$arg" in
            # translate --gnu-long-options to -g (short options)
            --config)         args="${args}-c " ;;
            --pretend)        args="${args}-n " ;;
            --test)           args="${args}-t " ;;
            --help-config)    usage_config && exit 0 ;;
            --help)           args="${args}-h " ;;
            --verbose)        args="${args}-v " ;;
            --debug)          args="${args}-x " ;;
            # pass through anything else
            *) [[ "${arg:0:1}" == "-" ]] || delim="\""
                args="${args}${delim}${arg}${delim} " ;;
        esac
    done
    # Reset the positional parameters to the short options
    eval set -- $args

    declare -a includeResources=()
    declare verboseOptionCount=0
    # declare options globally and readonly
    declare option
    while getopts 'nvhxt:c:f:' option; do
        case $option in
            h)
                printUsage
                exit 0
                ;;
            c)
                declare -gr CONFIG_FILE=$OPTARG
                ;;
            v)
                ((verboseOptionCount++))
                ;;
            x)
                declare -gr DEBUG='-x'
                set -x
                ;;
            t)
                RUN_TESTS=$OPTARG
                verbose VINFO "Running tests"
                ;;
            n)
                declare -gr PRETEND=1
                ;;
            f)  includeResources+=("$OPTARG")
                ;;
            *)  printUsage >&2
                # prints usage after the default error message (invalid option or missing option argument).
                # default error messages are disabled if the first character of optstring is ":".
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))

    declare -gr VERBOSE=$verboseOptionCount
    declare -rga INCLUDE_RESOURCES=("${includeResources[@]}")

    if [[ -z $RUN_TESTS ]]; then
        [[ ! -f $CONFIG_FILE ]] \
            && exitWithError "You must provide --config file"
    fi

    if (( $# != 1 )); then
        printUsage
        exit 1
    fi

    return 0
}

pressAnyKey() {
    read -rp "Press enter to continue"
}

# $1: selected commodity
# return value: 0 on success
# other return value: global variable $amount
askForNumber() {
    declare commodity=$1
    declare input
    echo "$commodity"
    IFS= read -rp "Anzahl oder '..' oder '  ' eingeben: " input
    if [[ $input =~ ^[0-9]+$ ]]; then
        amount=$input
    elif [[ $input =~ ^(\ *|\.*)$ ]]; then
        amount=${#input}
    else
        return 1
    fi
}

# See askForNumber
askForNumberHandleErrors() {
    while ! askForNumber "$@"; do
        echo "error: malformed input."
        pressAnyKey
    done
}

depositReturn() {
    declare person=$1
    declare group=$2
    declare amount=$3
    declare commodity=$COMMODITY_PFANDFLASCHE
    # TODO check if it's possible for this person to return deposit.
    echo "$amount $commodity zurück"
    addTransaction "$person" "$group" "Pfandrückgabe" \
        "-$amount" "$commodity" \
        "assets:forderungen:pfand" \
        "assets:getränke:pfand"
}

purchase() {
    declare person=$1
    declare group=$2
    declare amount=$3
    echo "$amount $commodity"
    addTransaction "$person" "$group" "Getränkekauf" \
        "-$amount" "$commodity" \
        "assets:getränke:$commodity" \
        "assets:forderungen:$commodity"
}

addTransaction() {
    declare person=$1
    declare group=$2
    declare description=$3
    declare amount=$4
    declare commodity=$5
    declare acc1=$6
    declare acc2=$7
    hledger add -- "$(date -I)" \
        "$description ; person: $person, gruppe: $group, time: $(date +%T)" \
        "$acc1" "$amount $commodity" \
        "$acc2"
}

main() {
    #parseCommandLine "$@"
    while true; do
        declare personSelection person group
        personSelection=$(fzf --delimiter='\t' < personen.txt)
        IFS=$'\t' read -r person group <<< "$personSelection"
        echo "$person, $group"

        declare amount
        askForNumberHandleErrors "$COMMODITY_PFANDFLASCHE"
        if (( amount > 0 )); then
            depositReturn "$person" "$group" "$amount"
        fi

        while true; do

            declare commodity
            commodity=$(fzf < commodities.txt)
            askForNumberHandleErrors "$commodity"
            if (( amount > 0 )); then
                if [[ $commodity == $COMMODITY_PFANDFLASCHE ]]; then
                    depositReturn "$person" "$group" "$amount"
                else
                    purchase "$person" "$group" "$amount" "$commodity"
                fi
            fi

            declare choice
            read -rp "Choice [enter to continue, n for next person, q for quit]: " choice
            case $choice in
                n) break ;;
                '') continue ;;
                q) return ;;
            esac
        done
    done
}

main "$@"
