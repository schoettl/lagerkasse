#!/bin/bash
# Lagerkasse (Getränkeverkauf, Einzahlung, Abrechnung).

printUsage() {
    cat <<EOF
usage: $PROGNAME [options]

options:
  -V
     Verkauf nicht automatisch starten. Nützlich für Abrechnung der
     Lagerkasse.
  -P
     Pfandrückgabe nicht automatisch starten. Nützlich bei Einzahlung in
     Lagerkasse.
  -f LEDGER_FILE
     Ledger journal file - used to record book entries and passed to hledger.
     If not specified, the environment variable LEDGER_FILE is used.
  -h
     Print help message.
EOF
}

set -o errexit -o pipefail
shopt -s nullglob

readonly PROGNAME=${0##*/}
readonly COMMODITY_PFANDFLASCHE=pfandflasche

# $1: error message
exitWithError() {
    declare msg=${1:-}
    echo "$msg" >&2
    exit 1
}

# $*: command line arguments = "$@"
parseCommandLine() {

    # declare options globally and readonly
    declare option
    while getopts 'hf:VP' option; do
        case $option in
            h)
                printUsage
                exit 0
                ;;
            f)
                declare -gr LEDGER_FILE=$OPTARG
                ;;
            V)
                declare -gr NO_SELL=1
                ;;
            P)
                declare -gr NO_DEPOSIT_RETURN=1
                ;;
            *)  printUsage >&2
                # prints usage after the default error message (invalid option or missing option argument).
                # default error messages are disabled if the first character of optstring is ":".
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [[ -z $LEDGER_FILE ]]; then
        exitWithError "error: ledger file not defined. use -f or export environment variable LEDGER_FILE."
    fi

    if (( $# != 0 )); then
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

printNotReturnedDeposit() {
    declare person=$1
    declare number
    number=$(hledger -f "$LEDGER_FILE" balance assets:forderungen:pfand tag:person="$person" \
        | awk 'NR==1 { print $1; exit }')
    if [[ $number =~ ^[0-9]+$ ]]; then
        echo "$number"
    else
        echo 0
    fi
}

depositReturn() {
    declare person=$1
    declare group=$2
    declare amount=$3
    declare commodity=$COMMODITY_PFANDFLASCHE
    declare purchasedDeposit
    purchasedDeposit=$(printNotReturnedDeposit "$person")
    if (( purchasedDeposit == 0 )); then
        echo "Geht nicht. $purchasedDeposit Pfandflaschen ausstehend."
        pressAnyKey
        return 1
    elif (( amount > purchasedDeposit )); then
        echo "Geht nicht. Nur $purchasedDeposit Pfandflaschen ausstehend."
        read -rp "$purchasedDeposit statt $amount Pfandflaschen zurückgeben? [Y/n] " answer
        if [[ $answer =~ ^[yY]$|^$ ]]; then
            amount=$purchasedDeposit
        else
            return 1
        fi
    fi
    echo "$amount $commodity zurück"
    echo "noch $(( purchasedDeposit - amount )) $commodity ausstehend"
    addTransaction "$person" "$group" "Pfandrückgabe" \
        "-$amount" "$commodity" \
        "assets:forderungen:pfand" \
        "assets:getränke:pfand"
}

purchase() {
    declare person=$1
    declare group=$2
    declare amount=$3
    declare commodity=$4
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
    cat <<TEXT >> "$LEDGER_FILE"
$(date -I) $description ; person: $person, gruppe: $group, time: $(date +%T)"
    $acc1     $amount $commodity
    $acc2
TEXT
    # hledger -f "$LEDGER_FILE" add -- "$(date -I)" \
    #     "$description ; person: $person, gruppe: $group, time: $(date +%T)" \
    #     "$acc1" "$amount $commodity" \
    #     "$acc2"
}

sell() {
    declare person=$1
    declare group=$2
    declare commodity=$3

    askForNumberHandleErrors "$commodity"
    if (( amount > 0 )); then
        if [[ $commodity == "$COMMODITY_PFANDFLASCHE" ]]; then
            depositReturn "$person" "$group" "$amount" \
                || true
        else
            purchase "$person" "$group" "$amount" "$commodity"
            purchase "$person" "$group" "$amount" "$COMMODITY_PFANDFLASCHE"
        fi
    fi
}

verkauf() {
    declare person=$1
    declare group=$2

    declare commodity
    commodity=$(fzf < commodities.txt)
    sell "$person" "$group" "$commodity"
}

einzahlen() {
    echo "einzahlen..."
    pressAnyKey
}

abrechnen() {
    echo "abrechnen..."
    pressAnyKey
}

printMenu() {
    echo "Choose an option:"
    echo " enter to continue Verkauf"
    echo " e Einzahlen"
    echo " a Abrechnen"
    echo " n, x for next person"
    echo " q quit"
}

main() {
    parseCommandLine "$@"

    while true; do
        declare personSelection person group
        personSelection=$(fzf --delimiter='\t' < personen.txt)
        IFS=$'\t' read -r person group <<< "$personSelection"
        echo "$person, $group"

        if [[ -z $NO_DEPOSIT_RETURN ]]; then
            sell "$person" "$group" "$COMMODITY_PFANDFLASCHE"
        fi

        declare choice=default
        while true; do
            case $choice in
                default)
                    if [[ -z $NO_SELL ]]; then
                        verkauf "$person" "$group"
                    fi
                    ;;
                '')
                    verkauf "$person" "$group"
                    ;;
                e)
                    einzahlen "$person" "$group"
                    ;;
                a)
                    abrechnen "$person" "$group"
                    ;;
            esac

            printMenu
            read -rp "> " choice
            case $choice in
                n|x) break ;;
                q) return ;;
            esac
        done
    done
}

main "$@"
