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
  -c
     Credit mode - we give credit to customers. They do not have to pay in
     advance. Currently, the only effect of this option is that a warning is
     omitted when a person's balance is less than a few Euros.
  -K
     Skip syntax check of files $PERSONS_FILE and $COMMODITIES_FILE on startup.
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
readonly PERSONS_FILE=personen.txt
readonly COMMODITIES_FILE=artikel.txt
readonly REGEX_METACHAR_REGEX='[][(){}\^$*+?.|]'

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
    while getopts 'hcKf:VP' option; do
        case $option in
            h)
                printUsage
                exit 0
                ;;
            f)
                declare -gr LEDGER_FILE=$OPTARG
                ;;
            c)
                declare -gr CREDIT_MODE=1
                ;;
            K)
                declare -gr SKIP_SYNTAX_CHECK=1
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

printPersonNamesOnly() {
    cut -d$'\t' -f1 < "$PERSONS_FILE"
}

checkSyntax() {
    echo "Checking syntax..."
    # Must not contain ","! Because hledger tag values are seperated by comma.
    if grep -v '[A-Za-z0-9]' "$COMMODITIES_FILE"; then
        exitWithError "$COMMODITIES_FILE: invalid characters"
    fi
    if grep -E "$REGEX_METACHAR_REGEX|," "$PERSONS_FILE"; then
        exitWithError "$PERSONS_FILE: invalid characters"
    fi

    echo "Checking person names for duplicates..."
    if ! diff <(printPersonNamesOnly | sort) <(printPersonNamesOnly | sort -u); then
        exitWithError "$PERSONS_FILE: found duplicate names. use a nickname or number to distinguish."
    fi
}

pressAnyKey() {
    read -rp "Press enter to continue"
}

# $*: command line options for hledger balance
hledgerBalance() {
    hledger bal --drop=1 --flat --invert "$@" 'assets:forderungen|liabilities:lagerkasse' tag:'^person$'="^$person$"
}

# $1: selected commodity
# return value: 0 on success
# other return value: global variable $amount
askForNumber() {
    declare commodity=$1
    declare input

    echo
    echo " $commodity"
    echo

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
    number=$(hledger -f "$LEDGER_FILE" balance "assets:forderungen:$COMMODITY_PFANDFLASCHE" tag:person="$person" \
        | awk '{ print $1; exit }')
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
        "assets:forderungen:$COMMODITY_PFANDFLASCHE" \
        "assets:getränke:$COMMODITY_PFANDFLASCHE"
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

$(date -I) $description ; person: $person, gruppe: $group, time: $(date +%T)
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

    if [[ $commodity != "$COMMODITY_PFANDFLASCHE" && -z $CREDIT_MODE ]]; then
        # Standardmodus: Guthaben auf Lagerkasse
        # Check if person can effort $amount of $commodity + deposit
        # TODO schwierig... dazu müsste dieses Programm wissen was
        # $commodity wert ist und selbst Berechnungen machen...
        # Vllt einfach warnen, wenn debit < 3 €?
        declare balanceValue
        balanceValue=$(hledgerBallanceValue)
        if math "${balanceValue/,/.} < 3"; then
            echo "Vorsicht: Guthaben < 3 €"
            pressAnyKey
        fi
    fi

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

# $*: args for fzf
runFzf() {
    fzf --reverse "$@"
}

verkaufen() {
    declare person=$1
    declare group=$2

    declare commodity
    commodity=$(runFzf < "$COMMODITIES_FILE") || return 1
    sell "$person" "$group" "$commodity"
}

einzahlen() {
    declare person=$1
    declare group=$2

    declare amount balanceAmount
    balanceAmount=$(hledgerBallanceValue)

    if math "${balanceAmount/,/.} < 0"; then
        balanceAmount=${balanceAmount#-}
        read -rp "Einzuzahlender Betrag [enter for balance amount: $balanceAmount]: " amount
        if [[ -z $amount ]]; then
            if math "${balanceAmount/,/.} == 0"; then
                return
            else
                if confirmYn "$balanceAmount wirklich einbezahlen?"; then
                    amount=$balanceAmount
                else
                    return 1
                fi
            fi
        fi
    else

        read -rp "Einzuzahlender Betrag: " amount
        amount=${amount/,/.}
        if [[ -z $amount ]]; then
            return 1
        fi
    fi

    amount=${amount/,/.}
    if [[ $amount =~ ^[0-9]+(.[0-9]*)?$ ]]; then
        addTransaction "$person" "$group" \
            "Einzahlung" \
            "$amount" "€" \
            "expenses:einzahlung" \
            "liabilities:lagerkasse"
    else
        echo "Ungültige Eingabe."
        pressAnyKey
        return 1
    fi
}

confirmYn() {
    declare question=$1

    declare answer
    read -rp "$question [Y/n] " answer
    [[ $answer =~ ^([Yy]|)$ ]]
}

math() {
    declare expression=$1

    declare result
    result=$(bc <<< "$expression")
    [[ $result == 1 ]]
}

hledgerBallanceValue() {
    hledgerBalance -V | awk 'END { print $1 }'
}

abrechnen() {
    declare person=$1
    declare group=$2

    declare restAmount
    restAmount=$(hledgerBallanceValue)
    if math "${restAmount/,/.} < 0"; then
        echo "${restAmount#-} ausstehend! Bitte Einzahlung machen."
        einzahlen "$person" "$group" \
            && return || return 1
    fi
    read -rp "Auszuzahlender Betrag [enter for rest amount: $restAmount]: " amount
    if [[ -z $amount ]]; then
        if math "${restAmount/,/.} == 0"; then
            return
        else
            if confirmYn "$restAmount wirklich ausbezahlen?"; then
                amount=$restAmount
            else
                return 1
            fi
        fi
    fi
    if [[ $amount =~ ^[0-9]+(.[0-9]*)?$ ]]; then
        amount=${amount/,/.}
        if math "$amount > ${restAmount/,/.}"; then
            echo "Auszuzahlender Betrag ist größer als Restbetrag."
            if ! confirmYn "Das bedeutet, die Kasse ist nacher im Minus. Fortfahren?"; then
                return 1
            fi
        fi
        addTransaction "$person" "$group" \
            "Auszahlung" \
            "$amount" "€" \
            "liabilities:lagerkasse" \
            "expenses:einzahlung"
    else
        echo "Ungültige Eingabe."
        pressAnyKey
        return 1
    fi
}

printMenu() {
    echo "Choose an option:"
    echo " enter for Verkauf"
    echo " e Einzahlen"
    echo " a Abrechnen"
    echo " b Bilanz mit €-Werten"
    echo " r Buchungssätze manuell reparieren"
    echo " n, x for next person"
    echo " q quit"
}

main() {
    parseCommandLine "$@"

    if [[ -z $SKIP_SYNTAX_CHECK ]]; then
        checkSyntax
    fi

    while true; do
        declare personSelection person group
        personSelection=$(sort "$PERSONS_FILE" | runFzf --delimiter='\t')
        IFS=$'\t' read -r person group <<< "$personSelection"

        if [[ -z $NO_DEPOSIT_RETURN ]]; then
            echo "$person, $group"
            sell "$person" "$group" "$COMMODITY_PFANDFLASCHE"
        fi

        declare choice=default
        while true; do

            echo
            echo "$person, $group"

            case $choice in
                default)
                    if [[ -z $NO_SELL ]]; then
                        verkaufen "$person" "$group" \
                            || true
                    fi
                    ;;
                '')
                    verkaufen "$person" "$group" \
                        || true
                    ;;
                e)
                    einzahlen "$person" "$group" \
                        || true
                    ;;
                a)
                    abrechnen "$person" "$group" \
                        || true
                    ;;
                b)
                    hledgerBalance -V
                    ;;
                r)
                    vim "$LEDGER_FILE"
                    ;;
                n|x) break ;;
                q) return ;;
            esac

            echo
            hledgerBalance
            # Also print sum of balance -V
            # Leider geht durch tail die Farbe verloren
            hledgerBalance -V | tail -2
            echo

            printMenu
            read -rp "> " choice
            echo
        done
    done
}

main "$@"
